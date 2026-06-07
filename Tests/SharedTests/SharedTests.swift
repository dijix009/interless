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
