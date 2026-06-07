import Testing
import MLXEngine
import Shared

struct MLXModelCatalogTests {
    @Test func modelCatalogDescribesRolesToolFormatsAndLocalAvailability() {
        let orchestrator = MLXModelCatalog.entry(id: "Qwen3.6-35B-A3B")

        #expect(orchestrator?.supports(role: .orchestrator) == true)
        #expect(orchestrator?.supports(role: .utility) == false)
        #expect(orchestrator?.supports(toolCallFormat: .llama3) == true)

        let available = MLXModelCatalog.markedAvailable(localModelIDs: ["Qwen3.5-2B"])
        #expect(available.first { $0.id == "Qwen3.5-2B" }?.isAvailableLocally == true)
        #expect(MLXModelCatalog.entries(supporting: .embeddings).map(\.id) == ["nomic-ai/nomic-embed-text-v1.5"])
    }
}
