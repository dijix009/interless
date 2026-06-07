import Foundation
import Tooling

public struct AgentRouter: Sendable {
    private let forcedRoute: AgentRoute?
    private let catalog: AgentCatalog

    public init(forcedRoute: AgentRoute? = nil, catalog: AgentCatalog = .default) {
        self.forcedRoute = forcedRoute
        self.catalog = catalog
    }

    public func route(for task: AgentTask) -> AgentRoute {
        if let forcedRoute {
            return forcedRoute
        }
        if let catalogRoute = catalog.route(for: task) {
            return catalogRoute
        }
        switch task.kind {
        case .architecture, .plan, .refactor, .multiFileEdit:
            return .orchestrator
        case .search, .summarize, .lint, .test, .simpleQuestion:
            return .utility
        case .auto:
            return classify(prompt: task.prompt)
        }
    }

    private func classify(prompt: String) -> AgentRoute {
        let lower = prompt.lowercased()
        let orchestratorKeywords = [
            "architecture", "architect", "plan", "phase", "refactor", "multi-file",
            "multiple files", "design", "migration", "decompose", "strategy",
        ]
        if orchestratorKeywords.contains(where: { lower.contains($0) }) {
            return .orchestrator
        }
        return .utility
    }
}

public actor AgentOrchestrator: Agent {
    private let orchestrator: any StreamingAgent
    private let utility: any StreamingAgent
    private let contextBuilder: ContextBuilder
    private let toolLoop: ToolExecutionLoop?
    private let retryPolicy: RetryPolicy
    private let router: AgentRouter

    public init(
        orchestrator: any StreamingAgent,
        utility: any StreamingAgent,
        contextBuilder: ContextBuilder = ContextBuilder(),
        toolLoop: ToolExecutionLoop? = nil,
        retryPolicy: RetryPolicy = .default,
        router: AgentRouter = AgentRouter()
    ) {
        self.orchestrator = orchestrator
        self.utility = utility
        self.contextBuilder = contextBuilder
        self.toolLoop = toolLoop
        self.retryPolicy = retryPolicy
        self.router = router
    }

    public func execute(task: AgentTask) async throws -> AgentResult {
        var completed: AgentResult?
        for try await event in run(task: task) {
            if case let .completed(result) = event {
                completed = result
            }
        }
        if Task.isCancelled { throw AgentError.cancelled }
        guard let completed else { throw AgentError.generationFailed("orchestrator stream completed without result") }
        return completed
    }

    public func run(task: AgentTask) -> AsyncThrowingStream<AgentEvent, Error> {
        let orchestrator = self.orchestrator
        let utility = self.utility
        let contextBuilder = self.contextBuilder
        let toolLoop = self.toolLoop
        let retryPolicy = self.retryPolicy
        let router = self.router

        return AsyncThrowingStream(AgentEvent.self, bufferingPolicy: .unbounded) { continuation in
            let taskHandle = Task {
                do {
                    try Task.checkCancellation()
                    let route = router.route(for: task)
                    continuation.yield(.routeSelected(route))

                    let toolResults = try await executeTools(
                        task.toolRequests,
                        toolLoop: toolLoop,
                        continuation: continuation)

                    let context = try await contextBuilder.build(task: task, toolResults: toolResults)
                    continuation.yield(.contextBuilt(context))

                    var routedTask = task.withContext(context)
                    routedTask.observations += toolResults.map { result in
                        "\(result.request.displayName): \(result.stdout)"
                    }
                    let agent = route == .orchestrator ? orchestrator : utility
                    let result = try await runWithRetry(
                        agent: agent,
                        task: routedTask,
                        toolResults: toolResults,
                        retryPolicy: retryPolicy,
                        continuation: continuation)
                    continuation.yield(.completed(result))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.yield(.failed("cancelled"))
                    continuation.finish(throwing: AgentError.cancelled)
                } catch {
                    continuation.yield(.failed(String(describing: error)))
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in taskHandle.cancel() }
        }
    }
}

private func executeTools(
    _ requests: [ToolRequest],
    toolLoop: ToolExecutionLoop?,
    continuation: AsyncThrowingStream<AgentEvent, Error>.Continuation
) async throws -> [ToolResult] {
    guard !requests.isEmpty else { return [] }
    guard let toolLoop else { throw AgentError.toolFailed("tool requests require a ToolExecutionLoop") }
    var results: [ToolResult] = []
    for request in requests {
        try Task.checkCancellation()
        continuation.yield(.toolStarted(request))
        do {
            let result = try await toolLoop.execute(request)
            results.append(result)
            continuation.yield(.toolFinished(result))
        } catch {
            throw AgentError.toolFailed(String(describing: error))
        }
    }
    return results
}

private func runWithRetry(
    agent: any StreamingAgent,
    task: AgentTask,
    toolResults: [ToolResult],
    retryPolicy: RetryPolicy,
    continuation: AsyncThrowingStream<AgentEvent, Error>.Continuation
) async throws -> AgentResult {
    var attempt = 0
    while true {
        do {
            var completed: AgentResult?
            for try await event in agent.run(task: task) {
                switch event {
                case let .token(chunk):
                    continuation.yield(.token(chunk))
                case let .completed(result):
                    completed = AgentResult(
                        taskID: result.taskID,
                        route: result.route,
                        text: result.text,
                        toolResults: toolResults + result.toolResults,
                        completionInfo: result.completionInfo)
                case .failed:
                    break
                default:
                    continuation.yield(event)
                }
            }
            guard let completed else { throw AgentError.generationFailed("agent stream completed without result") }
            return completed
        } catch {
            attempt += 1
            guard retryPolicy.shouldRetry(error, attempt: attempt) else { throw error }
        }
    }
}
