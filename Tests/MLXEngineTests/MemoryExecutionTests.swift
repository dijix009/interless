import Testing
import Shared
import Core
import MLXEngine

/// The controller correctly *executes* the §8 actions the policy returns. (The
/// policy itself is table-tested in `CoreTests/MemoryPolicyTests`.)
struct MemoryExecutionTests {

    @Test func clearUtilityKVCacheActionClearsOnlyUtility() async {
        let fake = FakeBackend()
        let controller = InferenceController(backend: fake)
        await controller.perform(.clearUtilityKVCache)
        let cleared = await fake.clearedKVRoles
        #expect(cleared == [.utility])
        #expect(!cleared.contains(.orchestrator)) // §8: orchestrator KV is persistent
    }

    @Test func unloadUtilityModelActionUnloadsUtility() async throws {
        let fake = FakeBackend()
        let controller = InferenceController(backend: fake)
        try await controller.loadModel(id: "m", role: .utility, quantization: .q6)
        await controller.perform(.unloadUtilityModel)
        #expect(await fake.unloadedRoles == [.utility])
        #expect(await controller.loadedRoles.isEmpty)
    }

    @Test func suspendEmbeddingsActionUnloadsEmbeddings() async throws {
        let fake = FakeBackend()
        let controller = InferenceController(backend: fake)
        try await controller.loadModel(id: "e", role: .embeddings, quantization: .q8)
        await controller.perform(.suspendEmbeddings)
        #expect(await fake.unloadedRoles == [.embeddings])
    }

    @Test func embeddingRoleProducesRepoOwnedVectors() async throws {
        let fake = FakeBackend()
        await fake.setScriptedEmbeddings([
            EmbeddingVector([1, 0, 0]),
            EmbeddingVector([0, 1, 0]),
        ])
        let controller = InferenceController(backend: fake)
        try await controller.loadModel(id: "embed", role: .embeddings, quantization: .q8)

        let vectors = try await controller.embed(texts: ["one", "two"])

        #expect(vectors.count == 2)
        #expect(vectors[0].cosineSimilarity(to: EmbeddingVector([1, 0, 0])) > 0.99)
        #expect(await fake.embeddingInputs == [["one", "two"]])
    }

    @Test func embeddingRejectedAtNinetyFivePercentWatermark() async throws {
        let fake = FakeBackend()
        await fake.setFootprintFraction(0.96)
        let controller = InferenceController(backend: fake)
        try await controller.loadModel(id: "embed", role: .embeddings, quantization: .q8)

        do {
            _ = try await controller.embed(texts: ["query"])
            Issue.record("expected embedding to be rejected at 95% watermark")
        } catch let error as InferenceError {
            guard case .memoryPressureRejected = error else {
                Issue.record("expected .memoryPressureRejected, got \(error)")
                return
            }
        }
    }

    @Test func generationRejectedAtNinetyFivePercentWatermark() async throws {
        let fake = FakeBackend()
        await fake.setFootprintFraction(0.96)
        let controller = InferenceController(backend: fake)
        try await controller.loadModel(id: "m", role: .utility, quantization: .q4)

        let stream = await controller.generate(request: .prompt("hi", role: .utility))
        do {
            for try await _ in stream {}
            Issue.record("expected inference to be rejected at 95% watermark")
        } catch let error as InferenceError {
            guard case .memoryPressureRejected = error else {
                Issue.record("expected .memoryPressureRejected, got \(error)")
                return
            }
        }
    }

    @Test func generationRequestIsCappedByResourceBudget() async throws {
        let fake = FakeBackend()
        let controller = InferenceController(backend: fake, resourceProfile: .smallRAM)
        try await controller.loadModel(id: "m", role: .orchestrator, quantization: .q4)

        let stream = await controller.generate(request: GenerationRequest(
            role: .orchestrator,
            input: .prompt("hi"),
            maxTokens: 9_999,
            contextTokenBudget: 99_999))
        for try await _ in stream {}

        let request = try #require(await fake.generationRequests.first)
        #expect(request.maxTokens == ResourceBudget.smallRAM.orchestratorMaxTokens)
        #expect(request.contextTokenBudget == ResourceBudget.smallRAM.orchestratorContextTokenBudget)
    }

    @Test func reasoningGenerationRequestUsesReasoningAwareCap() async throws {
        let fake = FakeBackend()
        let controller = InferenceController(backend: fake, resourceProfile: .smallRAM)
        try await controller.loadModel(id: "m", role: .utility, quantization: .q4)

        let stream = await controller.generate(request: GenerationRequest(
            role: .utility,
            input: .prompt("hi"),
            maxTokens: 9_999,
            reasoningEffort: .medium,
            contextTokenBudget: 99_999))
        for try await _ in stream {}

        let request = try #require(await fake.generationRequests.first)
        #expect(request.maxTokens == ResourceBudget.smallRAM.maxTokens(for: .utility, reasoningEffort: .medium))
        #expect(request.contextTokenBudget == ResourceBudget.smallRAM.utilityContextTokenBudget)
    }

    @Test func generationRequestCarriesProfileEngineTuning() async throws {
        let fake = FakeBackend()
        let controller = InferenceController(backend: fake, resourceProfile: .smallRAM)
        try await controller.loadModel(id: "m", role: .orchestrator, quantization: .q4)

        let stream = await controller.generate(request: GenerationRequest(
            role: .orchestrator, input: .prompt("hi")))
        for try await _ in stream {}

        let request = try #require(await fake.generationRequests.first)
        let tuning = try #require(request.engineTuning)
        // smallRAM resolves to aggressive 4-bit KV from the start + a small prefill.
        #expect(tuning.kvCachePolicy.strategy == .quantized)
        #expect(tuning.kvCachePolicy.kvBits == 4)
        #expect(tuning.prefillStepSize == ResourceBudget.smallRAM.engineTuning.prefillStepSize)
        // The resolved budget injects a proactive allocation ceiling.
        #expect(tuning.gpuMemoryLimitBytes != nil)
    }
}
