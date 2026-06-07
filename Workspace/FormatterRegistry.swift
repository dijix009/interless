import Foundation

public struct FormatterDefinition: Sendable, Equatable, Codable, Identifiable {
    public var id: String
    public var extensions: [String]
    public var command: [String]
    public var isEnabled: Bool

    public init(id: String, extensions: [String], command: [String], isEnabled: Bool = true) {
        self.id = id
        self.extensions = extensions.map { $0.lowercased() }
        self.command = command
        self.isEnabled = isEnabled
    }
}

public struct FormatterRegistry: Sendable, Equatable, Codable {
    public var formatters: [FormatterDefinition]

    public init(formatters: [FormatterDefinition] = []) {
        self.formatters = formatters
    }

    public func formatter(for relativePath: String) -> FormatterDefinition? {
        let ext = URL(fileURLWithPath: relativePath).pathExtension.lowercased()
        guard !ext.isEmpty else { return nil }
        return formatters.first { formatter in
            formatter.isEnabled && formatter.extensions.contains(ext)
        }
    }

    public func command(for relativePath: String) -> [String]? {
        formatter(for: relativePath)?.command
    }

    public func allowedFormatterIDs() -> [String] {
        formatters.filter(\.isEnabled).map(\.id).sorted()
    }
}
