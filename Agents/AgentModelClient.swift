import Shared
import MLXEngine

public protocol AgentModelClient: Sendable {
    func stream(request: GenerationRequest) async -> AsyncThrowingStream<TokenChunk, Error>
    /// Tokenizer-true token count for context fitting; estimate when unavailable.
    func countTokens(_ text: String, role: ModelRole) async -> Int
}

public extension AgentModelClient {
    func countTokens(_ text: String, role: ModelRole) async -> Int {
        InferenceTokenEstimate.estimate(text)
    }
}

extension InferenceController: AgentModelClient {
    public func stream(request: GenerationRequest) async -> AsyncThrowingStream<TokenChunk, Error> {
        generate(request: request)
    }
}
