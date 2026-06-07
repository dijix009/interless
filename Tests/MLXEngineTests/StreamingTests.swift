import Testing
import Shared
import MLXEngine

struct StreamingTests {

    @Test func tokensArriveInOrderWithSingleFinalChunk() async throws {
        let fake = FakeBackend()
        await fake.setScriptedTokens(["Hello", ", ", "world"])
        let controller = InferenceController(backend: fake)
        try await controller.loadModel(id: "m", role: .utility, quantization: .q4)

        let stream = await controller.generate(request: .prompt("hi", role: .utility))
        let chunks = try await collect(stream)

        assertStreamingInvariants(chunks)
        #expect(chunks.dropLast().map(\.text) == ["Hello", ", ", "world"])
        #expect(chunks.last?.info?.generationTokenCount == 3)
    }

    @Test func emptyScriptStillFinishesWithFinalChunk() async throws {
        let fake = FakeBackend()
        await fake.setScriptedTokens([])
        let controller = InferenceController(backend: fake)
        try await controller.loadModel(id: "m", role: .utility, quantization: .q4)

        let chunks = try await collect(await controller.generate(request: .prompt("hi", role: .utility)))
        #expect(chunks.count == 1)
        #expect(chunks.first?.isFinal == true)
    }

    /// The same invariant helper used (inlined) by the real-backend integration test.
    @Test func backendContractInvariantsHoldForFake() async throws {
        let fake = FakeBackend()
        let handle = try await fake.load(id: "m", role: .utility, quantization: .q4)
        let chunks = try await collect(fake.generate(request: .prompt("hi", role: .utility), handle: handle))
        assertStreamingInvariants(chunks)
    }

    @Test func loadAcceptsToolCallFormatAndRequestsCarryTools() async throws {
        let fake = FakeBackend()
        let controller = InferenceController(backend: fake)
        try await controller.loadModel(
            id: "m",
            role: .utility,
            quantization: .q4,
            toolCallFormat: .llama3)
        let tool = ToolDefinition(name: "git_status", description: "status", parameters: .object([:]))

        _ = try await collect(await controller.generate(request: .prompt("hi", role: .utility, tools: [tool])))

        #expect(await fake.loadToolCallFormats[.utility] == .llama3)
        #expect(await fake.generationRequests.last?.tools == [tool])
    }

    @Test func toolCallChunksPreserveStreamOrdering() async throws {
        let fake = FakeBackend()
        await fake.setScriptedChunks([
            TokenChunk(text: "before", index: 0, isFinal: false),
            TokenChunk(text: "", index: 1, isFinal: false, toolCall: ModelToolCall(name: "git_status")),
            TokenChunk(text: "", index: 2, isFinal: true),
        ])
        let controller = InferenceController(backend: fake)
        try await controller.loadModel(id: "m", role: .utility, quantization: .q4)

        let chunks = try await collect(await controller.generate(request: .prompt("hi", role: .utility)))

        assertStreamingInvariants(chunks)
        #expect(chunks[1].toolCall == ModelToolCall(name: "git_status"))
    }
}
