import Shared
import MLXEngine

public protocol AgentModelClient: Sendable {
    func stream(request: GenerationRequest) async -> AsyncThrowingStream<TokenChunk, Error>
}

extension InferenceController: AgentModelClient {
    public func stream(request: GenerationRequest) async -> AsyncThrowingStream<TokenChunk, Error> {
        generate(request: request)
    }
}
