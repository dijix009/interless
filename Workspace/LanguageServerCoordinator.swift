import Foundation

public struct LanguageServerDefinition: Sendable, Equatable, Codable, Identifiable {
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

public struct LanguageDiagnostic: Sendable, Equatable, Codable, Identifiable {
    public enum Severity: String, Sendable, Equatable, Codable, CaseIterable {
        case error
        case warning
        case information
    }

    public var id: UUID
    public var path: String
    public var line: Int
    public var column: Int
    public var severity: Severity
    public var message: String
    public var source: String

    public init(
        id: UUID = UUID(),
        path: String,
        line: Int,
        column: Int,
        severity: Severity,
        message: String,
        source: String
    ) {
        self.id = id
        self.path = path
        self.line = line
        self.column = column
        self.severity = severity
        self.message = message
        self.source = source
    }
}

public actor LanguageServerCoordinator {
    private var servers: [LanguageServerDefinition]
    private var diagnosticsByPath: [String: [LanguageDiagnostic]] = [:]
    private var failures: [String: String] = [:]

    public init(servers: [LanguageServerDefinition] = []) {
        self.servers = servers
    }

    public func configuredServers() -> [LanguageServerDefinition] {
        servers.sorted { $0.id < $1.id }
    }

    public func server(for relativePath: String) -> LanguageServerDefinition? {
        let ext = URL(fileURLWithPath: relativePath).pathExtension.lowercased()
        guard !ext.isEmpty else { return nil }
        return servers.first { server in
            server.isEnabled && server.extensions.contains(ext)
        }
    }

    public func replaceDiagnostics(_ diagnostics: [LanguageDiagnostic], for relativePath: String) {
        diagnosticsByPath[relativePath] = diagnostics
    }

    public func diagnostics(for relativePath: String) -> [LanguageDiagnostic] {
        diagnosticsByPath[relativePath] ?? []
    }

    public func recordFailure(serverID: String, message: String) {
        failures[serverID] = message
    }

    public func failure(serverID: String) -> String? {
        failures[serverID]
    }
}
