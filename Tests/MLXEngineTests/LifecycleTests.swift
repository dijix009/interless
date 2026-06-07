import Testing
import Shared
import MLXEngine

struct LifecycleTests {

    @Test func constructionDoesNotLoadEagerly() async {
        let fake = FakeBackend()
        _ = InferenceController(backend: fake)
        #expect(await fake.loadCallCount == 0)
    }

    @Test func liveControllerConstructionDoesNotTouchMetal() async {
        let controller = await EngineBootstrap.liveController()

        #expect(await controller.loadedRoles.isEmpty)
        #expect(await controller.memoryPolicyState().activeActions.isEmpty)
    }

    @Test func loadIsIdempotentPerRole() async throws {
        let fake = FakeBackend()
        let controller = InferenceController(backend: fake)
        try await controller.loadModel(id: "m", role: .utility, quantization: .q4)
        try await controller.loadModel(id: "m", role: .utility, quantization: .q4)
        #expect(await fake.loadCallCount == 1)
    }

    @Test func unloadRemovesRole() async throws {
        let fake = FakeBackend()
        let controller = InferenceController(backend: fake)
        try await controller.loadModel(id: "m", role: .utility, quantization: .q4)
        #expect(await controller.loadedRoles == [.utility])

        await controller.unload(role: .utility)
        #expect(await controller.loadedRoles.isEmpty)
        #expect(await fake.unloadedRoles == [.utility])
    }

    @Test func reloadAfterUnloadWorks() async throws {
        let fake = FakeBackend()
        let controller = InferenceController(backend: fake)
        try await controller.loadModel(id: "m", role: .utility, quantization: .q4)
        await controller.unload(role: .utility)
        try await controller.loadModel(id: "m", role: .utility, quantization: .q4)
        #expect(await controller.loadedRoles == [.utility])
        #expect(await fake.loadCallCount == 2)
    }

    @Test func clearKVCacheKeepsModelLoaded() async throws {
        let fake = FakeBackend()
        let controller = InferenceController(backend: fake)
        try await controller.loadModel(id: "m", role: .orchestrator, quantization: .q4)
        await controller.clearKVCache(role: .orchestrator)
        #expect(await controller.loadedRoles == [.orchestrator])
        #expect(await fake.clearedKVRoles == [.orchestrator])
    }

    /// Success Criteria §21.1 ("load two local quantized models concurrently"),
    /// at fake scale. The real-MLX equivalent is in the gated integration suite.
    @Test func twoModelsLoadConcurrently() async throws {
        let fake = FakeBackend()
        let controller = InferenceController(backend: fake)
        try await controller.loadModel(id: "orch", role: .orchestrator, quantization: .q4)
        try await controller.loadModel(id: "util", role: .utility, quantization: .q6)
        #expect(await controller.loadedRoles == [.orchestrator, .utility])
    }

    /// Reentrant loads of the same role must not start duplicate backend loads
    /// (actors are reentrant; the load gate + post-gate recheck dedupes them).
    @Test func concurrentSameRoleLoadsAreDeduped() async throws {
        let fake = FakeBackend()
        await fake.setLoadDelay(.milliseconds(50)) // widen the reentrancy window
        let controller = InferenceController(backend: fake)

        async let first: Void = controller.loadModel(id: "m", role: .utility, quantization: .q4)
        async let second: Void = controller.loadModel(id: "m", role: .utility, quantization: .q4)
        _ = try await (first, second)

        #expect(await fake.loadCallCount == 1)
        #expect(await controller.loadedRoles == [.utility])
    }
}
