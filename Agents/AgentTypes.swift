import Foundation
import Shared
import Tooling

public protocol Agent: Sendable {
    func execute(task: AgentTask) async throws -> AgentResult
}

public protocol StreamingAgent: Agent {
    func run(task: AgentTask) -> AsyncThrowingStream<AgentEvent, Error>
}

public enum AgentTaskKind: String, Sendable, Equatable, Codable, CaseIterable {
    case auto
    case architecture
    case plan
    case refactor
    case multiFileEdit
    case search
    case summarize
    case lint
    case test
    case simpleQuestion
}

public struct AgentTask: Sendable, Equatable, Identifiable, Codable {
    public var id: UUID
    public var prompt: String
    public var kind: AgentTaskKind
    public var toolRequests: [ToolRequest]
    public var observations: [String]
    public var context: AgentContext?
    public var maxTokens: Int?
    public var contextTokenBudget: Int?
    public var reasoningEffort: ReasoningEffort?
    public var agentID: String?

    public init(
        prompt: String,
        kind: AgentTaskKind = .auto,
        toolRequests: [ToolRequest] = [],
        observations: [String] = [],
        context: AgentContext? = nil,
        maxTokens: Int? = nil,
        contextTokenBudget: Int? = nil,
        reasoningEffort: ReasoningEffort? = nil,
        agentID: String? = nil,
        id: UUID = UUID()
    ) {
        self.id = id
        self.prompt = prompt
        self.kind = kind
        self.toolRequests = toolRequests
        self.observations = observations
        self.context = context
        self.maxTokens = maxTokens
        self.contextTokenBudget = contextTokenBudget
        self.reasoningEffort = reasoningEffort
        self.agentID = agentID
    }

    public func withContext(_ context: AgentContext) -> AgentTask {
        var copy = self
        copy.context = context
        return copy
    }
}

public enum AgentRoute: String, Sendable, Equatable, Codable {
    case orchestrator
    case utility

    public var modelRole: ModelRole {
        switch self {
        case .orchestrator: return .orchestrator
        case .utility: return .utility
        }
    }
}

public struct AgentResult: Sendable, Equatable {
    public var taskID: UUID
    public var route: AgentRoute
    public var text: String
    public var toolResults: [ToolResult]
    public var completionInfo: TokenChunk.CompletionInfo?

    public init(
        taskID: UUID,
        route: AgentRoute,
        text: String,
        toolResults: [ToolResult] = [],
        completionInfo: TokenChunk.CompletionInfo? = nil
    ) {
        self.taskID = taskID
        self.route = route
        self.text = text
        self.toolResults = toolResults
        self.completionInfo = completionInfo
    }
}

public enum AgentEvent: Sendable, Equatable {
    case routeSelected(AgentRoute)
    case toolIterationStarted(Int)
    case toolCallRequested(ModelToolCall)
    case toolCallRejected(ModelToolCall, String)
    case toolStarted(ToolRequest)
    case toolFinished(ToolResult)
    case contextBuilt(AgentContext)
    /// Pre-send fitting degraded old tool outputs to previews and/or dropped
    /// oldest history to fit the model's real token budget.
    case contextCompacted(degraded: Int, dropped: Int)
    case token(TokenChunk)
    case completed(AgentResult)
    case failed(String)
}

public enum AgentError: Error, Sendable, Equatable {
    case invalidTask(String)
    case cancelled
    case toolFailed(String)
    case toolIterationLimitExceeded(Int)
    case toolCallLimitExceeded(Int)
    case generationFailed(String)
}

public struct AgentLoopPolicy: Sendable, Equatable, Codable {
    public var maxToolIterations: Int
    public var maxToolCallsPerIteration: Int

    public init(maxToolIterations: Int = 4, maxToolCallsPerIteration: Int = 4) {
        self.maxToolIterations = max(0, maxToolIterations)
        self.maxToolCallsPerIteration = max(0, maxToolCallsPerIteration)
    }

    public static let `default` = AgentLoopPolicy()
}

public struct RetryPolicy: Sendable, Equatable, Codable {
    public var maxRetries: Int

    public init(maxRetries: Int = 1) {
        self.maxRetries = max(0, maxRetries)
    }

    public static let `default` = RetryPolicy()

    public func shouldRetry(_ error: Error, attempt: Int) -> Bool {
        guard attempt <= maxRetries else { return false }
        if error is CancellationError { return false }
        if error is ToolError { return false }
        if let inference = error as? InferenceError, inference == .cancelled { return false }
        if let agent = error as? AgentError {
            switch agent {
            case .cancelled, .invalidTask, .toolFailed, .toolIterationLimitExceeded, .toolCallLimitExceeded:
                return false
            case .generationFailed:
                return true
            }
        }
        return true
    }
}
