public enum ConversationContextMode: String, Sendable, Equatable, Codable, CaseIterable, Identifiable {
    case simple
    case smart

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .simple: return "Simple"
        case .smart: return "Smart"
        }
    }
}

public enum EffectiveConversationContextMode: String, Sendable, Equatable, Codable, CaseIterable, Identifiable {
    case simple
    case smart
    case smartDegraded

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .simple: return "Simple"
        case .smart: return "Smart"
        case .smartDegraded: return "Smart degraded"
        }
    }
}
