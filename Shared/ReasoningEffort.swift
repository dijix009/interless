import Foundation

public enum ReasoningEffort: String, Sendable, Equatable, Codable, CaseIterable, Identifiable {
    case none
    case low
    case medium
    case high

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .none: return "None"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }

    public var menuDetail: String {
        switch self {
        case .none:
            return "Answer directly without reasoning traces."
        case .low:
            return "Use concise internal reasoning."
        case .medium:
            return "Use more deliberate internal reasoning."
        case .high:
            return "Use the strongest available internal reasoning."
        }
    }

    public func promptInstruction(for modelID: String) -> String {
        let effective = Self.resolved(self, for: modelID)
        switch effective {
        case .none:
            if Self.usesQwenThinkingControl(modelID) {
                return "/no_think\nReasoning preference: none. Answer directly and do not emit hidden reasoning traces or <think> blocks."
            }
            return "Reasoning preference: none. Answer directly and do not emit hidden reasoning traces or <think> blocks."
        case .low:
            if Self.usesQwenThinkingControl(modelID) {
                return "/think\nReasoning preference: low. Keep any <think> reasoning concise, close the think block, then provide the final answer."
            }
            return "Reasoning preference: low. Use concise internal reasoning if the selected model supports it, and return only the final answer."
        case .medium:
            if Self.usesQwenThinkingControl(modelID) {
                return "/think\nReasoning preference: medium. Use deliberate but bounded <think> reasoning, close the think block, then provide the final answer."
            }
            return "Reasoning preference: medium. Use deliberate internal reasoning if the selected model supports it, and return only the final answer."
        case .high:
            if Self.usesQwenThinkingControl(modelID) {
                return "/think\nReasoning preference: high. Use the strongest useful <think> reasoning, but keep enough output budget for the final answer."
            }
            return "Reasoning preference: high. Use the strongest available internal reasoning if the selected model supports it, and return only the final answer."
        }
    }

    public static func options(for modelID: String) -> [ReasoningEffort] {
        supportsReasoning(modelID) ? Self.allCases : [.none]
    }

    public static func resolved(_ effort: ReasoningEffort, for modelID: String) -> ReasoningEffort {
        options(for: modelID).contains(effort) ? effort : .none
    }

    public static func supportsReasoning(_ modelID: String) -> Bool {
        let normalized = modelID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        return normalized.contains("qwen3")
            || normalized.contains("qwq")
            || normalized.contains("thinking")
            || normalized.contains("reasoning")
            || normalized.contains("deepseek-r")
            || normalized.contains("deepseek-r1")
    }

    public static func usesQwenThinkingControl(_ modelID: String) -> Bool {
        modelID.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .contains("qwen3")
    }
}
