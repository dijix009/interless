import Testing
import Shared
import MLXEngine
// NOTE: deliberately no `import Foundation` here — see IntegrationGate.swift.
// The gate (`IntegrationGate`) and fixtures (`ModelFixtures`) live in that
// Foundation-only file.

/// Gated real-MLX integration tests. Run them via:
///
///     ./scripts/test-integration.sh
///
/// (an `xcodebuild test` invocation that builds mlx-swift's Metal library and
/// defines `-D RUN_MLX_INTEGRATION`). They always skip under a plain `swift test`,
/// which cannot build the metallib. First run downloads two tiny models (~1 GB)
/// from Hugging Face; requires an Apple Silicon GPU + the Metal toolchain.
@Suite(.enabled(if: IntegrationGate.isEnabled), .serialized)
struct RealMLXBackendTests {

    @Test(.timeLimit(.minutes(10)))
    func streamsRealTokensInOrder() async throws {
        let backend = MLXBackend()
        let handle = try await backend.load(id: ModelFixtures.tinyUtility, role: .utility, quantization: .q4)

        var chunks: [TokenChunk] = []
        let stream = backend.generate(
            request: .prompt("Write a haiku about Swift.", role: .utility, maxTokens: 60),
            handle: handle)
        for try await chunk in stream {
            if !chunk.text.isEmpty { print(chunk.text, terminator: "") } // observe streaming by eye
            chunks.append(chunk)
        }
        print("")

        // Inlined backend-contract invariants (the shared helper lives in the
        // fast MLXEngineTests target, which this target can't import).
        #expect(!chunks.isEmpty)
        #expect(chunks.map(\.index) == Array(0..<chunks.count))
        #expect(chunks.filter(\.isFinal).count == 1)
        #expect(chunks.last?.isFinal == true)
        #expect(chunks.contains { !$0.text.isEmpty })
    }

    /// Success Criteria §21.1 on the real backend: two quantized models resident
    /// and generating concurrently. Uses two tiny models (~0.8 GB total) — the
    /// flagship two-35B case requires 64 GB hardware and is not run here.
    @Test(.timeLimit(.minutes(10)))
    func twoModelsGenerateConcurrently() async throws {
        let controller = await EngineBootstrap.liveController()
        try await controller.loadModel(id: ModelFixtures.tinyOrchestrator, role: .orchestrator, quantization: .q4)
        try await controller.loadModel(id: ModelFixtures.tinyUtility, role: .utility, quantization: .q4)
        #expect(await controller.loadedRoles == [.orchestrator, .utility])

        let s1 = await controller.generate(request: .prompt("Count to three.", role: .orchestrator, maxTokens: 40))
        let s2 = await controller.generate(request: .prompt("Name one color.", role: .utility, maxTokens: 40))
        async let a = collectText(s1)
        async let b = collectText(s2)
        let (textA, textB) = try await (a, b)

        #expect(!textA.isEmpty)
        #expect(!textB.isEmpty)
    }

    private func collectText(_ stream: AsyncThrowingStream<TokenChunk, Error>) async throws -> String {
        var text = ""
        for try await chunk in stream { text += chunk.text }
        return text
    }
}
