import Foundation

/// One unit of streamed generation output (ARCHITECTURE.md §11).
///
/// Chunks arrive in `index` order. Exactly one terminal chunk has `isFinal ==
/// true`; it carries the `CompletionInfo` summary and (usually) empty `text`.
public struct TokenChunk: Sendable, Equatable {
    /// Already-detokenized text for this chunk (may be empty on the final chunk).
    public var text: String
    /// Zero-based position in the stream.
    public var index: Int
    /// `true` only for the single terminal chunk.
    public var isFinal: Bool
    /// End-of-generation metrics; populated only on the final chunk.
    public var info: CompletionInfo?
    /// Native model-requested tool call; populated only for tool-call chunks.
    public var toolCall: ModelToolCall?

    public init(
        text: String,
        index: Int,
        isFinal: Bool,
        info: CompletionInfo? = nil,
        toolCall: ModelToolCall? = nil
    ) {
        self.text = text
        self.index = index
        self.isFinal = isFinal
        self.info = info
        self.toolCall = toolCall
    }

    /// Summary metrics emitted once at the end of a generation. These map
    /// directly from MLX's `GenerateCompletionInfo` — tokens/sec is computed by
    /// MLX, not by us.
    public struct CompletionInfo: Sendable, Equatable {
        public var promptTokenCount: Int
        public var generationTokenCount: Int
        public var promptTime: TimeInterval
        public var generateTime: TimeInterval
        public var tokensPerSecond: Double
        public var promptTokensPerSecond: Double
        public var stopReason: String

        public init(
            promptTokenCount: Int = 0,
            generationTokenCount: Int = 0,
            promptTime: TimeInterval = 0,
            generateTime: TimeInterval = 0,
            tokensPerSecond: Double = 0,
            promptTokensPerSecond: Double = 0,
            stopReason: String = ""
        ) {
            self.promptTokenCount = promptTokenCount
            self.generationTokenCount = generationTokenCount
            self.promptTime = promptTime
            self.generateTime = generateTime
            self.tokensPerSecond = tokensPerSecond
            self.promptTokensPerSecond = promptTokensPerSecond
            self.stopReason = stopReason
        }
    }
}
