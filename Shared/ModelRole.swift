/// The role a loaded model plays in the workspace (ARCHITECTURE.md §6, §8).
///
/// Roles — not model identities — drive memory policy and KV-cache lifetime:
/// the orchestrator keeps a persistent cache and a single active stream, the
/// utility model's context is ephemeral, and embeddings have no autoregressive
/// cache at all.
public enum ModelRole: String, Sendable, Hashable, CaseIterable, Codable {
    case orchestrator
    case utility
    case embeddings
}
