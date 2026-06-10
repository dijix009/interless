import Testing
import Foundation
import Shared

struct SharedTests {

    @Test func quantizationRoleDefaultsMatchSpecSection8() {
        // §8: orchestrator 4-bit, utility 6-bit, embeddings 8-bit.
        #expect(QuantizationLevel.defaultFor(.orchestrator) == .q4)
        #expect(QuantizationLevel.defaultFor(.utility) == .q6)
        #expect(QuantizationLevel.defaultFor(.embeddings) == .q8)
    }

    @Test func quantizationBitWidth() {
        #expect(QuantizationLevel.q4.bitWidth == 4)
        #expect(QuantizationLevel.q8.bitWidth == 8)
    }

    @Test func usedFractionIsFootprintOverTotal() {
        let footprint = MemoryFootprint(processFootprintBytes: 800, totalUnifiedBytes: 1000)
        #expect(abs(footprint.usedFraction - 0.8) < 1e-9)
    }

    @Test func usedFractionIsZeroWhenTotalIsZero() {
        #expect(MemoryFootprint(processFootprintBytes: 100, totalUnifiedBytes: 0).usedFraction == 0)
    }

    @Test func reuseKVCacheDefaultsToTrueOnlyForOrchestrator() {
        #expect(GenerationRequest.prompt("x", role: .orchestrator).reuseKVCache == true)
        #expect(GenerationRequest.prompt("x", role: .utility).reuseKVCache == false)
        #expect(GenerationRequest.prompt("x", role: .embeddings).reuseKVCache == false)
    }

    @Test func snapshotReportsActiveModelCount() {
        let snapshot = MemorySnapshot(
            footprint: MemoryFootprint(processFootprintBytes: 1, totalUnifiedBytes: 10),
            loadedRoles: [.orchestrator, .utility]
        )
        #expect(snapshot.activeModelCount == 2)
    }

    @Test func automaticResourceProfileResolvesFromPhysicalMemory() {
        #expect(ResourceProfile.resolvedProfile(for: .automatic, physicalMemoryBytes: 8 * 1024 * 1024 * 1024) == .smallRAM)
        #expect(ResourceProfile.resolvedProfile(for: .automatic, physicalMemoryBytes: 16 * 1024 * 1024 * 1024) == .balanced)
        #expect(ResourceProfile.resolvedProfile(for: .automatic, physicalMemoryBytes: 64 * 1024 * 1024 * 1024) == .largeRAM)
        #expect(ResourceBudget.resolved(for: .automatic, physicalMemoryBytes: 8 * 1024 * 1024 * 1024).profile == .smallRAM)
    }

    @Test func reducedResourceBudgetHalvesExpandablePromptBudgets() {
        let reduced = ResourceBudget.balanced.reducedForMemoryPressure()

        #expect(reduced.maxContextCharacters < ResourceBudget.balanced.maxContextCharacters)
        #expect(reduced.maxToolOutputBytes < ResourceBudget.balanced.maxToolOutputBytes)
        #expect(reduced.orchestratorContextTokenBudget == 4_096)
        // Under pressure the KV cache compresses hardest: 4-bit, quantized from token 0.
        #expect(reduced.engineTuning.kvCachePolicy.strategy == .quantized)
        #expect(reduced.engineTuning.kvCachePolicy.kvBits == 4)
        #expect(reduced.engineTuning.kvCachePolicy.quantizedKVStart == 0)
        #expect(reduced.engineTuning.embeddingMaxBatchTokens < ResourceBudget.balanced.engineTuning.embeddingMaxBatchTokens)
    }

    @Test func profilesCarryExpectedEngineTuning() {
        // smallRAM: aggressive 4-bit KV from the start; larger profiles near-lossless 8-bit.
        #expect(ResourceBudget.smallRAM.engineTuning.kvCachePolicy.kvBits == 4)
        #expect(ResourceBudget.smallRAM.engineTuning.kvCachePolicy.quantizedKVStart == 0)
        #expect(ResourceBudget.balanced.engineTuning.kvCachePolicy.kvBits == 8)
        #expect(ResourceBudget.balanced.engineTuning.kvCachePolicy.quantizedKVStart == 2_048)
        #expect(ResourceBudget.largeRAM.engineTuning.kvCachePolicy.kvBits == 8)
        #expect(ResourceBudget.smallRAM.engineTuning.prefillStepSize == 256)
        #expect(ResourceBudget.largeRAM.engineTuning.prefillStepSize == 1_024)
        // Static profile constants stay machine-independent (limit resolved later).
        #expect(ResourceBudget.smallRAM.engineTuning.gpuMemoryLimitBytes == nil)
    }

    @Test func resolvedBudgetInjectsProactiveGPUMemoryLimit() throws {
        let eightGB = 8 * 1024 * 1024 * 1024
        let budget = ResourceBudget.resolved(for: .smallRAM, physicalMemoryBytes: eightGB)
        let limit = try #require(budget.engineTuning.gpuMemoryLimitBytes)
        #expect(limit == Int(0.70 * Double(eightGB)))
        // The cache-pool alias still reads through to engineTuning.
        #expect(budget.mlxGPUCacheLimitBytes == budget.engineTuning.gpuCacheLimitBytes)
    }

    @Test func engineTuningCodableRoundTrips() throws {
        let tuning = EngineTuning(
            kvCachePolicy: KVCachePolicy(strategy: .quantized, kvBits: 4, kvGroupSize: 64, quantizedKVStart: 128),
            prefillStepSize: 384,
            gpuMemoryLimitBytes: 5_000_000_000,
            gpuCacheLimitBytes: 128 * 1024 * 1024,
            embeddingMaxBatchTokens: 2_048,
            speculativeDecoding: SpeculativeDecodingPolicy(
                isEnabled: true, draftModelID: "draft", draftQuantization: .q4, numDraftTokens: 3))
        let data = try JSONEncoder().encode(tuning)
        let decoded = try JSONDecoder().decode(EngineTuning.self, from: data)
        #expect(decoded == tuning)
    }

    @Test func advertisedQuantizationBitsParsedFromRepoID() {
        #expect(QuantizationLevel.advertisedBits(inRepoID: "mlx-community/Qwen2.5-0.5B-Instruct-4bit") == 4)
        #expect(QuantizationLevel.advertisedBits(inRepoID: "mlx-community/Llama-3.2-1B-Instruct-8bit") == 8)
        #expect(QuantizationLevel.advertisedBits(inRepoID: "org/Model-q6") == 6)
        // No advertised quantization → nil (validation is then skipped).
        #expect(QuantizationLevel.advertisedBits(inRepoID: "mlx-community/Llama-3.2-1B-Instruct-bf16") == nil)
    }

    @Test func optiQModelsAreMarkedUnsupportedForSwiftRuntime() {
        let optiQ = "mlx-community/Qwen3.5-2B-OptiQ-4bit"
        let regular = "mlx-community/Qwen3.5-2B-4bit"

        #expect(ModelCompatibility.unsupportedReason(for: optiQ)?.contains("OptiQ") == true)
        #expect(!ModelCompatibility.isSupported(optiQ))
        #expect(ModelCompatibility.isSupported(regular))
        #expect(ModelCompatibility.supportedModelIDs([optiQ, regular]) == [regular])
    }

    @Test func reasoningEffortOptionsFollowModelCapability() {
        #expect(ReasoningEffort.options(for: "mlx-community/gemma-2-2b-it-4bit") == [.none])
        #expect(ReasoningEffort.options(for: "Qwen/Qwen3-4B-MLX-4bit") == [.none, .low, .medium, .high])
        #expect(ReasoningEffort.resolved(.high, for: "mlx-community/Llama-3.2-1B-Instruct-4bit") == .none)
        #expect(ReasoningEffort.resolved(.medium, for: "Qwen/Qwen3-4B-MLX-4bit") == .medium)
        #expect(ReasoningEffort.none.promptInstruction(for: "Qwen/Qwen3-4B-MLX-4bit").contains("/no_think"))
        #expect(ReasoningEffort.low.promptInstruction(for: "Qwen/Qwen3-4B-MLX-4bit").contains("/think"))
        #expect(!ReasoningEffort.none.promptInstruction(for: "mlx-community/gemma-2-2b-it-4bit").contains("/no_think"))
        #expect(ResourceBudget.smallRAM.maxTokens(for: .utility, reasoningEffort: .low) == 1_536)
        #expect(ResourceBudget.balanced.maxTokens(for: .utility, reasoningEffort: .medium) == 3_072)
        #expect(ResourceBudget.largeRAM.maxTokens(for: .orchestrator, reasoningEffort: .high) == 8_192)
    }

    @Test func reasoningOutputSanitizerRemovesThinkBlocksOnlyWhenReasoningIsDisabled() {
        let text = "<think>\nhidden\n</think>\n\nFinal answer"

        #expect(ReasoningOutputSanitizer.visibleText(text, reasoningEffort: ReasoningEffort.none) == "Final answer")
        #expect(ReasoningOutputSanitizer.visibleText("<think></think>\nAnswer", reasoningEffort: ReasoningEffort.none) == "Answer")
        #expect(ReasoningOutputSanitizer.visibleText("Before\n<think>hidden", reasoningEffort: ReasoningEffort.none) == "Before")
        #expect(ReasoningOutputSanitizer.visibleText(text, reasoningEffort: .low) == text)
        #expect(ReasoningOutputSanitizer.visibleText(text, reasoningEffort: nil) == text)
    }

    @Test func nativeToolCallValuesAreCodableAndEquatable() throws {
        let definition = ToolDefinition(
            name: "read_file",
            description: "Read a file",
            parameters: .object([
                "type": .string("object"),
                "properties": .object(["path": .object(["type": .string("string")])]),
                "required": .array([.string("path")]),
            ]))
        let call = ModelToolCall(name: "read_file", arguments: ["path": .string("README.md")])
        let encodedDefinition = try JSONEncoder().encode(definition)
        let encodedCall = try JSONEncoder().encode(call)

        #expect(try JSONDecoder().decode(ToolDefinition.self, from: encodedDefinition) == definition)
        #expect(try JSONDecoder().decode(ModelToolCall.self, from: encodedCall) == call)
        #expect(ModelToolCallFormat.allCases.contains(.llama3))
    }

    @Test func generationRequestCarriesToolDefinitions() {
        let definition = ToolDefinition(name: "git_status", description: "status", parameters: .object([:]))
        let request = GenerationRequest.prompt("status", role: .utility, tools: [definition])

        #expect(request.tools == [definition])
    }

    @Test func tokenChunkCarriesNativeToolCall() {
        let call = ModelToolCall(name: "git_status")
        let chunk = TokenChunk(text: "", index: 0, isFinal: false, toolCall: call)

        #expect(chunk.toolCall == call)
        #expect(!chunk.isFinal)
    }
}
