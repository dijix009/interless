import Foundation
import Shared

public enum MLXModelCatalog {
    public static let defaultEntries: [ModelCatalogEntry] = [
        ModelCatalogEntry(
            id: "Qwen3.6-35B-A3B",
            displayName: "Qwen 3.6 35B A3B",
            supportedRoles: [.orchestrator],
            defaultQuantization: .q4,
            toolCallFormats: [.json, .llama3],
            contextTokenLimit: 32_000,
            compatibilityNotes: ["High-memory planning and architecture model."]),
        ModelCatalogEntry(
            id: "Qwen3.5-2B",
            displayName: "Qwen 3.5 2B",
            supportedRoles: [.utility],
            defaultQuantization: .q4,
            toolCallFormats: [.json, .llama3],
            contextTokenLimit: 16_000,
            compatibilityNotes: ["Small utility model for local tool use."]),
        ModelCatalogEntry(
            id: "nomic-ai/nomic-embed-text-v1.5",
            displayName: "Nomic Embed Text v1.5",
            supportedRoles: [.embeddings],
            defaultQuantization: .q8,
            toolCallFormats: [],
            contextTokenLimit: 8_192,
            compatibilityNotes: ["Embedding-only semantic search model."]),
    ]

    public static func entry(id: String) -> ModelCatalogEntry? {
        defaultEntries.first { $0.id == id }
    }

    public static func entries(supporting role: ModelRole) -> [ModelCatalogEntry] {
        defaultEntries.filter { $0.supports(role: role) }
    }

    public static func markedAvailable(localModelIDs: [String]) -> [ModelCatalogEntry] {
        let local = Set(localModelIDs)
        return defaultEntries.map { entry in
            var copy = entry
            copy.isAvailableLocally = local.contains(entry.id)
            return copy
        }
    }
}
