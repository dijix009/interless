/// Quantization bit-width for a loaded model (ARCHITECTURE.md §8).
public enum QuantizationLevel: Int, Sendable, Hashable, Codable, CaseIterable {
    case q4 = 4
    case q6 = 6
    case q8 = 8

    /// Bit-width as an integer (4, 6, or 8).
    public var bitWidth: Int { rawValue }

    /// The spec's §8 per-role quantization defaults.
    ///
    /// Note: §8 lists the *utility* model default as **6-bit** (and forbids
    /// 8-bit for the orchestrator). The recommended `Qwen3.5-2B-4bit` from §19
    /// is therefore an *explicit per-model override* expressed at its config
    /// site — it does not change this role default, which acts as the policy
    /// ceiling.
    public static func defaultFor(_ role: ModelRole) -> QuantizationLevel {
        switch role {
        case .orchestrator: return .q4
        case .utility:      return .q6
        case .embeddings:   return .q8
        }
    }

    /// Best-effort detection of a quantization bit-width advertised in a Hugging
    /// Face repo id (e.g. `…-4bit`, `…-8bit`, `…-q4`, `…-int8`). Returns `nil`
    /// when the id does not advertise one, in which case validation is skipped.
    public static func advertisedBits(inRepoID id: String) -> Int? {
        let lower = id.lowercased()
        for bits in [3, 4, 5, 6, 8] {
            if lower.contains("\(bits)bit") || lower.contains("\(bits)-bit")
                || lower.contains("q\(bits)") || lower.contains("int\(bits)") {
                return bits
            }
        }
        return nil
    }
}
