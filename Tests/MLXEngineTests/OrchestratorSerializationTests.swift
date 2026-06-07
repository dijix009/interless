import Testing
import Shared
import MLXEngine

@Suite(.serialized)
struct OrchestratorSerializationTests {

    @Test(.timeLimit(.minutes(1)))
    func orchestratorRunsSingleActiveStream() async throws {
        let fake = FakeBackend()
        await fake.setScriptedTokens(["a", "b", "c", "d"])
        await fake.setPerTokenDelay(.milliseconds(15))
        let controller = InferenceController(backend: fake)
        try await controller.loadModel(id: "m", role: .orchestrator, quantization: .q4)

        let s1 = await controller.generate(request: .prompt("1", role: .orchestrator))
        let s2 = await controller.generate(request: .prompt("2", role: .orchestrator))
        async let d1: Void = drain(s1)
        async let d2: Void = drain(s2)
        _ = try await (d1, d2)

        #expect(await fake.maxConcurrentGenerations == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func utilityStreamsRunConcurrently() async throws {
        let fake = FakeBackend()
        await fake.setScriptedTokens(["a", "b", "c", "d"])
        await fake.setPerTokenDelay(.milliseconds(15))
        let controller = InferenceController(backend: fake)
        try await controller.loadModel(id: "m", role: .utility, quantization: .q4)

        let s1 = await controller.generate(request: .prompt("1", role: .utility))
        let s2 = await controller.generate(request: .prompt("2", role: .utility))
        async let d1: Void = drain(s1)
        async let d2: Void = drain(s2)
        _ = try await (d1, d2)

        #expect(await fake.maxConcurrentGenerations == 2)
    }
}
