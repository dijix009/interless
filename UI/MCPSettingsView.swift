import SwiftUI

public enum MCPServerTransportView: String, Sendable, Equatable, Codable, CaseIterable {
    case local
    case remote

    public var label: String {
        switch self {
        case .local: return "Local"
        case .remote: return "Remote"
        }
    }
}

public struct MCPServerViewState: Identifiable, Sendable, Equatable, Codable {
    public var id: String
    public var name: String
    public var transport: MCPServerTransportView
    public var command: [String]
    public var url: String?
    public var timeoutSeconds: Int?
    public var isEnabled: Bool
    public var isTrusted: Bool

    public init(
        id: String,
        name: String,
        transport: MCPServerTransportView,
        command: [String] = [],
        url: String? = nil,
        timeoutSeconds: Int? = nil,
        isEnabled: Bool = true,
        isTrusted: Bool = false
    ) {
        self.id = id
        self.name = name
        self.transport = transport
        self.command = command
        self.url = url
        self.timeoutSeconds = timeoutSeconds
        self.isEnabled = isEnabled
        self.isTrusted = isTrusted
    }

    public var endpointSummary: String {
        if let url, !url.isEmpty {
            return url
        }
        if !command.isEmpty {
            return command.joined(separator: " ")
        }
        return "No endpoint configured"
    }
}

public struct MCPSettingsViewState: Sendable, Equatable, Codable {
    public var defaultTimeoutSeconds: Int?
    public var trustedNetworkEnabled: Bool
    public var servers: [MCPServerViewState]

    public init(
        defaultTimeoutSeconds: Int? = nil,
        trustedNetworkEnabled: Bool = false,
        servers: [MCPServerViewState] = []
    ) {
        self.defaultTimeoutSeconds = defaultTimeoutSeconds
        self.trustedNetworkEnabled = trustedNetworkEnabled
        self.servers = servers
    }

    public var enabledCount: Int {
        servers.filter(\.isEnabled).count
    }

    public var activeCount: Int {
        servers.filter { $0.isEnabled && $0.isTrusted }.count
    }

    public var untrustedRemoteCount: Int {
        servers.filter { $0.transport == .remote && $0.isEnabled && !$0.isTrusted }.count
    }
}

public struct MCPSettingsView: View {
    private let state: MCPSettingsViewState

    public init(state: MCPSettingsViewState) {
        self.state = state
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: .space2) {
            HStack {
                Label("MCP", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.titleS)
                Spacer()
                Text("\(state.activeCount)/\(state.enabledCount) active")
                    .font(.metaMono)
                    .foregroundStyle(.secondary)
            }
            ForEach(state.servers) { server in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(server.name)
                            .font(.body.weight(.semibold))
                        Spacer()
                        Text(server.transport.label)
                            .font(.metaMono)
                            .foregroundStyle(.secondary)
                    }
                    Text(server.endpointSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if !server.isEnabled {
                        Label("Disabled", systemImage: "pause.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if !server.isTrusted {
                        Label("Trust required", systemImage: "lock.shield")
                            .font(.caption)
                            .foregroundStyle(Theme.C.danger)
                    }
                }
                .padding(.space2)
                .background(Theme.C.surface2, in: RoundedRectangle(cornerRadius: .radiusSm, style: .continuous))
            }
        }
    }
}
