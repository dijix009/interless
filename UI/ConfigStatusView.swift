import SwiftUI

public struct ConfigDiagnosticViewState: Identifiable, Sendable, Equatable, Codable {
    public var id: UUID
    public var severity: ConfigDiagnosticViewSeverity
    public var message: String
    public var sourcePath: String?

    public init(
        id: UUID = UUID(),
        severity: ConfigDiagnosticViewSeverity,
        message: String,
        sourcePath: String? = nil
    ) {
        self.id = id
        self.severity = severity
        self.message = message
        self.sourcePath = sourcePath
    }
}

public enum ConfigDiagnosticViewSeverity: String, Sendable, Equatable, Codable, CaseIterable {
    case info
    case warning
    case error

    public var symbolName: String {
        switch self {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.octagon"
        }
    }
}

public struct ConfigStatusViewState: Sendable, Equatable, Codable {
    public var loadedAt: Date?
    public var loadedSourceCount: Int
    public var candidateSourceCount: Int
    public var diagnostics: [ConfigDiagnosticViewState]
    public var policyCount: Int
    public var agentCount: Int
    public var providerCount: Int
    public var formatterCount: Int
    public var languageServerCount: Int
    public var mcpServerCount: Int
    public var extensionCount: Int

    public init(
        loadedAt: Date? = nil,
        loadedSourceCount: Int = 0,
        candidateSourceCount: Int = 0,
        diagnostics: [ConfigDiagnosticViewState] = [],
        policyCount: Int = 0,
        agentCount: Int = 0,
        providerCount: Int = 0,
        formatterCount: Int = 0,
        languageServerCount: Int = 0,
        mcpServerCount: Int = 0,
        extensionCount: Int = 0
    ) {
        self.loadedAt = loadedAt
        self.loadedSourceCount = loadedSourceCount
        self.candidateSourceCount = candidateSourceCount
        self.diagnostics = diagnostics
        self.policyCount = policyCount
        self.agentCount = agentCount
        self.providerCount = providerCount
        self.formatterCount = formatterCount
        self.languageServerCount = languageServerCount
        self.mcpServerCount = mcpServerCount
        self.extensionCount = extensionCount
    }

    public var hasLoadedConfig: Bool {
        loadedSourceCount > 0
            || !diagnostics.isEmpty
            || policyCount > 0
            || agentCount > 0
            || providerCount > 0
            || formatterCount > 0
            || languageServerCount > 0
            || mcpServerCount > 0
            || extensionCount > 0
    }

    public var errorCount: Int {
        diagnostics.filter { $0.severity == .error }.count
    }

    public var warningCount: Int {
        diagnostics.filter { $0.severity == .warning }.count
    }

    public var summary: String {
        guard hasLoadedConfig else { return "No config loaded" }
        var parts = ["\(loadedSourceCount)/\(candidateSourceCount) files"]
        if policyCount > 0 { parts.append("\(policyCount) policies") }
        if agentCount > 0 { parts.append("\(agentCount) agents") }
        if providerCount > 0 { parts.append("\(providerCount) providers") }
        if formatterCount > 0 { parts.append("\(formatterCount) formatters") }
        if languageServerCount > 0 { parts.append("\(languageServerCount) LSP servers") }
        if mcpServerCount > 0 { parts.append("\(mcpServerCount) MCP servers") }
        if extensionCount > 0 { parts.append("\(extensionCount) extensions") }
        if warningCount > 0 { parts.append("\(warningCount) warnings") }
        if errorCount > 0 { parts.append("\(errorCount) errors") }
        return parts.joined(separator: " · ")
    }
}

public struct ConfigStatusView: View {
    private let state: ConfigStatusViewState

    public init(state: ConfigStatusViewState) {
        self.state = state
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: .space2) {
            HStack {
                Label("Config", systemImage: "doc.badge.gearshape")
                    .font(.titleS)
                Spacer()
                Text(state.summary)
                    .font(.metaMono)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if !state.diagnostics.isEmpty {
                VStack(alignment: .leading, spacing: .space1) {
                    ForEach(state.diagnostics.prefix(4)) { diagnostic in
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(diagnostic.message)
                                if let sourcePath = diagnostic.sourcePath {
                                    Text(sourcePath)
                                        .font(.metaMono)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                        } icon: {
                            Image(systemName: diagnostic.severity.symbolName)
                        }
                        .foregroundStyle(color(for: diagnostic.severity))
                        .font(.caption)
                    }
                }
            }
        }
        .padding(.space3)
        .background(Theme.C.surface2, in: RoundedRectangle(cornerRadius: .radiusSm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: .radiusSm, style: .continuous)
                .stroke(Theme.C.border))
    }

    private func color(for severity: ConfigDiagnosticViewSeverity) -> Color {
        switch severity {
        case .info: return Theme.C.textSecondary
        case .warning: return Theme.C.caution
        case .error: return Theme.C.danger
        }
    }
}
