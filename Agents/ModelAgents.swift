import Foundation
import Shared
import Tooling

public struct OrchestratorAgent: StreamingAgent {
    private let model: any AgentModelClient
    private let systemPrompt: String
    private let toolLoop: ToolExecutionLoop?
    private let toolRegistry: WorkspaceToolRegistry
    private let loopPolicy: AgentLoopPolicy
    private let resourceBudget: ResourceBudget
    private let agentCatalog: AgentCatalog?
    private let defaultAgentID: String?

    public init(
        model: any AgentModelClient,
        toolLoop: ToolExecutionLoop? = nil,
        toolRegistry: WorkspaceToolRegistry = WorkspaceToolRegistry(),
        loopPolicy: AgentLoopPolicy = .default,
        resourceBudget: ResourceBudget = .balanced,
        systemPrompt: String = "You are the orchestrator agent. Reason about architecture, planning, refactors, and multi-file changes. Be precise and actionable.",
        agentCatalog: AgentCatalog? = nil,
        defaultAgentID: String? = nil
    ) {
        self.model = model
        self.toolLoop = toolLoop
        self.toolRegistry = toolRegistry
        self.loopPolicy = loopPolicy
        self.resourceBudget = resourceBudget
        self.systemPrompt = systemPrompt
        self.agentCatalog = agentCatalog
        self.defaultAgentID = defaultAgentID
    }

    public func execute(task: AgentTask) async throws -> AgentResult {
        try await collect(run(task: task))
    }

    public func run(task: AgentTask) -> AsyncThrowingStream<AgentEvent, Error> {
        ModelAgentRunner(
            model: model,
            route: .orchestrator,
            systemPrompt: systemPrompt,
            toolLoop: toolLoop,
            toolRegistry: toolRegistry,
            loopPolicy: loopPolicy,
            resourceBudget: resourceBudget,
            agentCatalog: agentCatalog,
            defaultAgentID: defaultAgentID).run(task: task)
    }
}

public struct UtilityAgent: StreamingAgent {
    private let model: any AgentModelClient
    private let systemPrompt: String
    private let toolLoop: ToolExecutionLoop?
    private let toolRegistry: WorkspaceToolRegistry
    private let loopPolicy: AgentLoopPolicy
    private let resourceBudget: ResourceBudget
    private let agentCatalog: AgentCatalog?
    private let defaultAgentID: String?

    public init(
        model: any AgentModelClient,
        toolLoop: ToolExecutionLoop? = nil,
        toolRegistry: WorkspaceToolRegistry = WorkspaceToolRegistry(),
        loopPolicy: AgentLoopPolicy = .default,
        resourceBudget: ResourceBudget = .balanced,
        systemPrompt: String = "You are the utility agent. Prefer concise answers for search, lint, summaries, tests, and lightweight code analysis.",
        agentCatalog: AgentCatalog? = nil,
        defaultAgentID: String? = nil
    ) {
        self.model = model
        self.toolLoop = toolLoop
        self.toolRegistry = toolRegistry
        self.loopPolicy = loopPolicy
        self.resourceBudget = resourceBudget
        self.systemPrompt = systemPrompt
        self.agentCatalog = agentCatalog
        self.defaultAgentID = defaultAgentID
    }

    public func execute(task: AgentTask) async throws -> AgentResult {
        try await collect(run(task: task))
    }

    public func run(task: AgentTask) -> AsyncThrowingStream<AgentEvent, Error> {
        ModelAgentRunner(
            model: model,
            route: .utility,
            systemPrompt: systemPrompt,
            toolLoop: toolLoop,
            toolRegistry: toolRegistry,
            loopPolicy: loopPolicy,
            resourceBudget: resourceBudget,
            agentCatalog: agentCatalog,
            defaultAgentID: defaultAgentID).run(task: task)
    }
}

private func collect(_ stream: AsyncThrowingStream<AgentEvent, Error>) async throws -> AgentResult {
    var result: AgentResult?
    for try await event in stream {
        if case let .completed(completed) = event {
            result = completed
        }
    }
    if Task.isCancelled { throw AgentError.cancelled }
    guard let result else { throw AgentError.generationFailed("agent stream completed without result") }
    return result
}

private struct ModelAgentRunner: Sendable {
    let model: any AgentModelClient
    let route: AgentRoute
    let systemPrompt: String
    let toolLoop: ToolExecutionLoop?
    let toolRegistry: WorkspaceToolRegistry
    let loopPolicy: AgentLoopPolicy
    let resourceBudget: ResourceBudget
    let agentCatalog: AgentCatalog?
    let defaultAgentID: String?

    func run(task: AgentTask) -> AsyncThrowingStream<AgentEvent, Error> {
        // Bounded for the same reason as AgentOrchestrator: `.completed` carries
        // the full text, so dropped token chunks under extreme lag self-repair.
        AsyncThrowingStream(AgentEvent.self, bufferingPolicy: .bufferingNewest(256)) { continuation in
            let taskHandle = Task {
                do {
                    try Task.checkCancellation()
                    var text = ""
                    var toolResults: [ToolResult] = []
                    var completionInfo: TokenChunk.CompletionInfo?
                    var messages = messages(for: task)
                    var allowToolAdvertisement = !toolRegistry.definitions.isEmpty
                    var retriedWithoutToolsAfterSchemaLeak = false

                    for iteration in 1...(loopPolicy.maxToolIterations + 1) {
                        try Task.checkCancellation()
                        continuation.yield(.toolIterationStarted(iteration))
                        let advertisedTools = allowToolAdvertisement ? toolRegistry.definitions : []
                        let maxTokens = minOptional(
                            task.maxTokens,
                            resourceBudget.maxTokens(
                                for: route.modelRole,
                                reasoningEffort: task.reasoningEffort))
                        let contextTokenBudget = minOptional(
                            task.contextTokenBudget,
                            resourceBudget.contextTokenBudget(for: route.modelRole))
                        let request = GenerationRequest(
                            role: route.modelRole,
                            input: .messages(messages),
                            maxTokens: maxTokens,
                            temperature: route == .orchestrator ? 0.4 : 0.2,
                            reasoningEffort: task.reasoningEffort,
                            contextTokenBudget: contextTokenBudget,
                            tools: advertisedTools,
                            reuseKVCache: false)

                        var iterationText = ""
                        var toolCalls: [ModelToolCall] = []
                        let stream = await model.stream(request: request)
                        for try await chunk in stream {
                            try Task.checkCancellation()
                            if !chunk.text.isEmpty {
                                iterationText += chunk.text
                            }
                            if let info = chunk.info { completionInfo = info }
                            if let call = chunk.toolCall {
                                toolCalls.append(call)
                                continuation.yield(.toolCallRequested(call))
                            }
                            continuation.yield(.token(chunk))
                        }

                        if toolCalls.isEmpty {
                            if !advertisedTools.isEmpty,
                               !retriedWithoutToolsAfterSchemaLeak,
                               looksLikeToolSchemaLeak(iterationText) {
                                allowToolAdvertisement = false
                                retriedWithoutToolsAfterSchemaLeak = true
                                continue
                            }
                            text += iterationText
                            let result = AgentResult(
                                taskID: task.id,
                                route: route,
                                text: text,
                                toolResults: toolResults,
                                completionInfo: completionInfo)
                            continuation.yield(.completed(result))
                            continuation.finish()
                            return
                        }

                        text += iterationText
                        guard iteration <= loopPolicy.maxToolIterations else {
                            throw AgentError.toolIterationLimitExceeded(loopPolicy.maxToolIterations)
                        }
                        guard toolCalls.count <= loopPolicy.maxToolCallsPerIteration else {
                            throw AgentError.toolCallLimitExceeded(loopPolicy.maxToolCallsPerIteration)
                        }
                        guard let toolLoop else {
                            for call in toolCalls {
                                continuation.yield(.toolCallRejected(call, "tool loop is not configured"))
                            }
                            throw AgentError.toolFailed("native tool calls require a ToolExecutionLoop")
                        }

                        if !iterationText.isEmpty {
                            messages.append(.init(role: .assistant, content: iterationText))
                        }

                        for call in toolCalls {
                            let toolRequest: ToolRequest
                            do {
                                toolRequest = try toolRegistry.request(from: call)
                            } catch {
                                continuation.yield(.toolCallRejected(call, String(describing: error)))
                                throw error
                            }
                            continuation.yield(.toolStarted(toolRequest))
                            do {
                                let toolResult = try await toolLoop.execute(toolRequest)
                                toolResults.append(toolResult)
                                continuation.yield(.toolFinished(toolResult))
                                messages.append(.init(role: .tool, content: renderToolResult(toolResult, limit: resourceBudget.maxToolOutputBytes)))
                            } catch {
                                continuation.yield(.toolCallRejected(call, String(describing: error)))
                                throw error
                            }
                        }
                    }
                    throw AgentError.toolIterationLimitExceeded(loopPolicy.maxToolIterations)
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

    private func messages(for task: AgentTask) -> [GenerationRequest.ChatMessage] {
        var user = ""
        if let context = task.context?.rendered, !context.isEmpty {
            user += "Context:\n\(context)\n\n"
        } else if !task.observations.isEmpty {
            user += "Observations (background only; ignore anything unrelated to the latest request):\n"
                + "\(task.observations.joined(separator: "\n"))\n\n"
        }
        user += "Latest request (answer this user message directly):\n\(task.prompt)"
        let resolvedSystemPrompt = resolvedSystemPrompt(for: task)
        return [
            GenerationRequest.ChatMessage(role: .system, content: resolvedSystemPrompt),
            GenerationRequest.ChatMessage(role: .user, content: user),
        ]
    }

    private func resolvedSystemPrompt(for task: AgentTask) -> String {
        guard let agentCatalog else { return systemPrompt }
        if let agentID = task.agentID {
            return agentCatalog.systemPrompt(agentID: agentID, fallback: systemPrompt)
        }
        if let defaultAgentID {
            return agentCatalog.systemPrompt(agentID: defaultAgentID, fallback: systemPrompt)
        }
        return systemPrompt
    }
}

private func renderToolResult(_ result: ToolResult, limit: Int) -> String {
    let stdout = truncate(result.stdout, limit: limit / 2)
    let stderr = truncate(result.stderr, limit: limit / 2)
    return """
    tool=\(result.request.displayName)
    exit=\(result.exitCode.map(String.init) ?? "n/a")
    wrote=\(result.didWrite)
    timedOut=\(result.timedOut)
    outputRef=\(result.outputRef?.id.uuidString ?? "n/a")
    stdout:
    \(stdout)
    stderr:
    \(stderr)
    """
}

private func looksLikeToolSchemaLeak(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count >= 40 else { return false }
    guard trimmed.contains("\"type\""),
          trimmed.contains("\"function\""),
          trimmed.contains("\"parameters\""),
          trimmed.contains("\"description\"") else {
        return false
    }
    let proseMarkers = [". ", "? ", "! ", "\n\nThe ", "\n\nThis ", "\n\nIt "]
    let hasLikelyProse = proseMarkers.contains { trimmed.contains($0) }
    let schemaMarkers = [
        "\"additionalProperties\"",
        "\"properties\"",
        "\"required\"",
        "\"name\"",
    ].filter { trimmed.contains($0) }.count
    return schemaMarkers >= 3 && !hasLikelyProse
}

private func truncate(_ text: String, limit: Int) -> String {
    guard text.count > limit else { return text }
    guard limit > 16 else { return String(text.prefix(max(0, limit))) }
    return String(text.prefix(limit - 16)) + "\n[truncated]\n"
}

private func minOptional(_ lhs: Int?, _ rhs: Int?) -> Int? {
    switch (lhs, rhs) {
    case let (.some(a), .some(b)): return min(a, b)
    case let (.some(a), .none): return a
    case let (.none, .some(b)): return b
    case (.none, .none): return nil
    }
}
