import SwiftUI

public enum PermissionPromptAction: String, Sendable, Equatable, Codable, CaseIterable {
    case allowOnce
    case deny
}

public struct PermissionPromptViewState: Sendable, Equatable, Codable, Identifiable {
    public var id: UUID
    public var title: String
    public var message: String
    public var toolName: String
    public var risk: String

    public init(
        id: UUID = UUID(),
        title: String,
        message: String,
        toolName: String,
        risk: String
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.toolName = toolName
        self.risk = risk
    }
}

public struct PermissionPromptView: View {
    public var state: PermissionPromptViewState
    public var onDecision: @MainActor (PermissionPromptAction) -> Void

    public init(
        state: PermissionPromptViewState,
        onDecision: @escaping @MainActor (PermissionPromptAction) -> Void
    ) {
        self.state = state
        self.onDecision = onDecision
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: .space3) {
            HStack(spacing: .space2) {
                Image(systemName: "lock.shield")
                Text(state.title)
                    .font(.titleS)
                Spacer()
            }
            Text(state.message)
                .font(.body)
                .foregroundStyle(Theme.C.textSecondary)
            HStack {
                Label(state.toolName, systemImage: "wrench.and.screwdriver")
                Spacer()
                Text(state.risk)
                    .foregroundStyle(Theme.C.danger)
            }
            .font(.metaMono)
            HStack {
                Spacer()
                Button("Deny") { onDecision(.deny) }
                Button("Allow Once") { onDecision(.allowOnce) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.space4)
        .overlaySurface()
    }
}
