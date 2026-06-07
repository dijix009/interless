import Foundation

/// A single inference request routed to a loaded model (ARCHITECTURE.md §7).
///
/// `GenerationRequest` is backend-agnostic: it carries the prompt/messages and
/// sampling parameters that `MLXEngine` maps onto MLX's `GenerateParameters`,
/// without referencing any MLX type.
public struct GenerationRequest: Sendable, Identifiable {

    /// The prompt, either as raw text or a chat transcript.
    public enum Input: Sendable, Equatable {
        case prompt(String)
        case messages([ChatMessage])
    }

    /// A single chat message (mirrors MLX's `Chat.Message` without importing MLX).
    public struct ChatMessage: Sendable, Equatable, Codable {
        public enum Role: String, Sendable, Equatable, Codable {
            case system, user, assistant, tool
        }
        public var role: Role
        public var content: String

        public init(role: Role, content: String) {
            self.role = role
            self.content = content
        }
    }

    /// Correlation id used for logging and signpost intervals.
    public let id: UUID
    /// Which loaded model (by role) should serve this request.
    public var role: ModelRole
    public var input: Input
    public var maxTokens: Int?
    public var temperature: Float
    public var topP: Float
    public var topK: Int?
    public var repetitionPenalty: Float?
    /// Optional reasoning mode selected by the user. Backends use it only for
    /// bounded generation policy; prompt semantics stay in the agent layer.
    public var reasoningEffort: ReasoningEffort?
    /// Maximum KV-cache size in tokens (maps to a rotating cache when set).
    public var contextTokenBudget: Int?
    /// Native tool schemas the backend should expose to the model.
    public var tools: [ToolDefinition]
    /// Whether to reuse the role's persisted KV cache. Defaults to `true` for
    /// the orchestrator (persistent cache) and `false` otherwise (§8).
    public var reuseKVCache: Bool

    public init(
        role: ModelRole,
        input: Input,
        maxTokens: Int? = nil,
        temperature: Float = 0.7,
        topP: Float = 1.0,
        topK: Int? = nil,
        repetitionPenalty: Float? = nil,
        reasoningEffort: ReasoningEffort? = nil,
        contextTokenBudget: Int? = nil,
        tools: [ToolDefinition] = [],
        reuseKVCache: Bool? = nil,
        id: UUID = UUID()
    ) {
        self.id = id
        self.role = role
        self.input = input
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.repetitionPenalty = repetitionPenalty
        self.reasoningEffort = reasoningEffort
        self.contextTokenBudget = contextTokenBudget
        self.tools = tools
        self.reuseKVCache = reuseKVCache ?? (role == .orchestrator)
    }

    /// The raw prompt text, if this request was built from `.prompt`.
    public var promptText: String? {
        if case let .prompt(text) = input { return text }
        return nil
    }

    /// Convenience constructor for a plain text prompt.
    public static func prompt(
        _ text: String,
        role: ModelRole = .utility,
        maxTokens: Int? = nil,
        temperature: Float = 0.7,
        reasoningEffort: ReasoningEffort? = nil,
        tools: [ToolDefinition] = []
    ) -> GenerationRequest {
        GenerationRequest(
            role: role,
            input: .prompt(text),
            maxTokens: maxTokens,
            temperature: temperature,
            reasoningEffort: reasoningEffort,
            tools: tools
        )
    }
}
