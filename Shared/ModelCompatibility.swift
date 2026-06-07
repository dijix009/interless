import Foundation

/// Compatibility checks for model IDs that can be loaded through the current
/// native Swift MLX runtime.
public enum ModelCompatibility {
    public static func unsupportedReason(for modelID: String) -> String? {
        let normalized = modelID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }

        if normalized.contains("optiq") {
            return "OptiQ MLX checkpoints are not supported by the current Swift MLX runtime. Use a regular MLX q4/q6/q8 model."
        }

        return nil
    }

    public static func isSupported(_ modelID: String) -> Bool {
        unsupportedReason(for: modelID) == nil
    }

    public static func supportedModelIDs(_ modelIDs: [String]) -> [String] {
        modelIDs.filter(isSupported)
    }
}
