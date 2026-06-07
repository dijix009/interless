import SwiftUI

public struct ShareExportViewState: Sendable, Equatable, Codable {
    public var title: String
    public var includesMessages: Bool
    public var includesToolOutputs: Bool
    public var redactionSummary: String

    public init(
        title: String = "Export Session",
        includesMessages: Bool = true,
        includesToolOutputs: Bool = false,
        redactionSummary: String = "Secrets and absolute paths are redacted."
    ) {
        self.title = title
        self.includesMessages = includesMessages
        self.includesToolOutputs = includesToolOutputs
        self.redactionSummary = redactionSummary
    }
}

public struct ShareExportView: View {
    public var state: ShareExportViewState
    public var onExport: @MainActor () -> Void

    public init(state: ShareExportViewState, onExport: @escaping @MainActor () -> Void) {
        self.state = state
        self.onExport = onExport
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: .space3) {
            Text(state.title)
                .font(.titleS)
            Toggle("Messages", isOn: .constant(state.includesMessages))
            Toggle("Tool outputs", isOn: .constant(state.includesToolOutputs))
            Text(state.redactionSummary)
                .font(.metaMono)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Export", action: onExport)
            }
        }
        .padding(.space4)
    }
}
