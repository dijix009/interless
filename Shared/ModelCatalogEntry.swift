import Foundation

public struct ModelCatalogEntry: Sendable, Equatable, Codable, Hashable, Identifiable {
    public var id: String
    public var displayName: String
    public var supportedRoles: [ModelRole]
    public var defaultQuantization: QuantizationLevel
    public var toolCallFormats: [ModelToolCallFormat]
    public var contextTokenLimit: Int?
    public var isAvailableLocally: Bool
    public var compatibilityNotes: [String]

    public init(
        id: String,
        displayName: String? = nil,
        supportedRoles: [ModelRole],
        defaultQuantization: QuantizationLevel,
        toolCallFormats: [ModelToolCallFormat] = [],
        contextTokenLimit: Int? = nil,
        isAvailableLocally: Bool = false,
        compatibilityNotes: [String] = []
    ) {
        self.id = id
        self.displayName = displayName ?? id
        self.supportedRoles = supportedRoles
        self.defaultQuantization = defaultQuantization
        self.toolCallFormats = toolCallFormats
        self.contextTokenLimit = contextTokenLimit
        self.isAvailableLocally = isAvailableLocally
        self.compatibilityNotes = compatibilityNotes
    }

    public func supports(role: ModelRole) -> Bool {
        supportedRoles.contains(role)
    }

    public func supports(toolCallFormat: ModelToolCallFormat) -> Bool {
        toolCallFormats.contains(toolCallFormat)
    }
}
