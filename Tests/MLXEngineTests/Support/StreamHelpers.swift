import Testing
import Shared

/// Collect every chunk from a token stream.
func collect(_ stream: AsyncThrowingStream<TokenChunk, Error>) async throws -> [TokenChunk] {
    var chunks: [TokenChunk] = []
    for try await chunk in stream { chunks.append(chunk) }
    return chunks
}

/// Consume a stream to completion, discarding output.
func drain(_ stream: AsyncThrowingStream<TokenChunk, Error>) async throws {
    for try await _ in stream {}
}

/// The backend-contract invariants shared between the fake and (inlined for) the
/// real MLX backend: in-order indices, exactly one final chunk, and it is last.
func assertStreamingInvariants(_ chunks: [TokenChunk]) {
    #expect(!chunks.isEmpty)
    #expect(chunks.map(\.index) == Array(0..<chunks.count))
    #expect(chunks.filter(\.isFinal).count == 1)
    #expect(chunks.last?.isFinal == true)
}
