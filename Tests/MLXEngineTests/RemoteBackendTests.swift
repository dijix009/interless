import Foundation
import Testing
import Shared
import CloudInference
@testable import MLXEngine

struct RemoteBackendTests {

    @Test func remoteBackendDelegatesAndStripsProviderPrefix() async throws {
        let client = FakeCloudModelClient(texts: ["A", "B"])
        let backend = RemoteInferenceBackend(client: client)

        let handle = try await backend.load(
            id: "anthropic/claude-opus-4-8", role: .orchestrator,
            quantization: .q8, toolCallFormat: nil, progressHandler: nil)
        #expect(handle.id == "anthropic/claude-opus-4-8")

        let chunks = try await collect(backend.generate(
            request: .prompt("hi", role: .orchestrator), handle: handle))
        #expect(client.capturedModel == "claude-opus-4-8")
        #expect(chunks.filter { !$0.text.isEmpty }.map(\.text) == ["A", "B"])
        #expect(chunks.last?.isFinal == true)
    }

    @Test func remoteBackendEmbedThrows() async throws {
        let backend = RemoteInferenceBackend(client: FakeCloudModelClient(texts: []))
        let handle = LoadedModelHandle(role: .embeddings, id: "anthropic/x", quantization: .q8)
        await #expect(throws: InferenceError.self) {
            _ = try await backend.embed(texts: ["x"], handle: handle)
        }
    }

    @Test func routingDispatchesByModelId() async throws {
        let local = FakeBackend()
        await local.setScriptedTokens(["LOCAL"])
        let remote = RemoteInferenceBackend(client: FakeCloudModelClient(texts: ["REMOTE"]))
        let routing = RoutingInferenceBackend(local: local, remote: remote)

        let localHandle = try await routing.load(
            id: "mlx-community/model", role: .utility,
            quantization: .q4, toolCallFormat: nil, progressHandler: nil)
        let localChunks = try await collect(routing.generate(
            request: .prompt("x", role: .utility), handle: localHandle))
        #expect(localChunks.filter { !$0.text.isEmpty }.map(\.text) == ["LOCAL"])

        let cloudHandle = try await routing.load(
            id: "anthropic/claude-haiku-4-5", role: .orchestrator,
            quantization: .q8, toolCallFormat: nil, progressHandler: nil)
        let cloudChunks = try await collect(routing.generate(
            request: .prompt("y", role: .orchestrator), handle: cloudHandle))
        #expect(cloudChunks.filter { !$0.text.isEmpty }.map(\.text) == ["REMOTE"])
    }
}

private final class FakeCloudModelClient: CloudModelClient, @unchecked Sendable {
    private let texts: [String]
    private(set) var capturedModel: String?

    init(texts: [String]) { self.texts = texts }

    func validate() async throws {}

    func stream(model: String, request: GenerationRequest) -> AsyncThrowingStream<TokenChunk, Error> {
        capturedModel = model
        let texts = self.texts
        return AsyncThrowingStream { continuation in
            var index = 0
            for text in texts {
                continuation.yield(TokenChunk(text: text, index: index, isFinal: false))
                index += 1
            }
            continuation.yield(TokenChunk(text: "", index: index, isFinal: true,
                                          info: TokenChunk.CompletionInfo(stopReason: "stop")))
            continuation.finish()
        }
    }
}
