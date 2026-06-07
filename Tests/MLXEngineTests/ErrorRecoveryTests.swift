import Testing
import Shared
import MLXEngine

/// ARCHITECTURE.md §15 — failures recover and never terminate the controller.
struct ErrorRecoveryTests {

    @Test func loadRetriesThenSucceeds() async throws {
        let fake = FakeBackend()
        await fake.setLoadFailures(1) // first attempt fails, second succeeds (default maxLoadAttempts = 2)
        let controller = InferenceController(backend: fake)

        try await controller.loadModel(id: "m", role: .utility, quantization: .q4)
        #expect(await fake.loadCallCount == 2)
        #expect(await controller.loadedRoles == [.utility])
    }

    @Test func loadFailsAfterMaxAttempts() async {
        let fake = FakeBackend()
        await fake.setLoadFailures(5)
        let controller = InferenceController(backend: fake, maxLoadAttempts: 2)

        do {
            try await controller.loadModel(id: "m", role: .utility, quantization: .q4)
            Issue.record("expected load to fail after max attempts")
        } catch let error as InferenceError {
            guard case .modelLoadFailed = error else {
                Issue.record("expected .modelLoadFailed, got \(error)")
                return
            }
        } catch {
            Issue.record("unexpected error type \(error)")
        }
        #expect(await fake.loadCallCount == 2)
        #expect(await controller.loadedRoles.isEmpty)
    }

    @Test func partialStreamSurfacesErrorThenControllerRecovers() async throws {
        let fake = FakeBackend()
        await fake.setScriptedTokens(["a", "b", "c", "d", "e"])
        await fake.setFailAfterTokens(2)
        let controller = InferenceController(backend: fake)
        try await controller.loadModel(id: "m", role: .utility, quantization: .q4)

        var received = 0
        do {
            let stream = await controller.generate(request: .prompt("x", role: .utility))
            for try await chunk in stream where !chunk.isFinal {
                received += 1
            }
            Issue.record("expected mid-stream failure")
        } catch let error as InferenceError {
            guard case .generationFailed = error else {
                Issue.record("expected .generationFailed, got \(error)")
                return
            }
        }
        #expect(received == 2)

        // The controller is still usable.
        await fake.setFailAfterTokens(nil)
        let chunks = try await collect(await controller.generate(request: .prompt("y", role: .utility)))
        #expect(chunks.last?.isFinal == true)
    }
}
