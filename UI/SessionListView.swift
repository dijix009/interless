import SwiftUI

public struct SessionListItemViewState: Identifiable, Sendable, Equatable, Codable {
    public var id: UUID
    public var title: String
    public var workspaceName: String?
    public var updatedAt: Date
    public var isSelected: Bool
    public var isInterrupted: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        workspaceName: String? = nil,
        updatedAt: Date = Date(),
        isSelected: Bool = false,
        isInterrupted: Bool = false
    ) {
        self.id = id
        self.title = title
        self.workspaceName = workspaceName
        self.updatedAt = updatedAt
        self.isSelected = isSelected
        self.isInterrupted = isInterrupted
    }
}

public struct SessionListView: View {
    private let sessions: [SessionListItemViewState]
    private let onSelect: @MainActor (UUID) -> Void

    public init(
        sessions: [SessionListItemViewState],
        onSelect: @escaping @MainActor (UUID) -> Void
    ) {
        self.sessions = sessions
        self.onSelect = onSelect
    }

    public var body: some View {
        List(sessions) { session in
            Button {
                onSelect(session.id)
            } label: {
                HStack(spacing: .space2) {
                    Image(systemName: session.isInterrupted ? "pause.circle" : "bubble.left.and.bubble.right")
                        .foregroundStyle(session.isInterrupted ? Theme.C.danger : Theme.C.textSecondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.title)
                            .font(.body)
                            .lineLimit(1)
                        if let workspaceName = session.workspaceName {
                            Text(workspaceName)
                                .font(.metaMono)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowBackground(session.isSelected ? Theme.C.accentGlow : Color.clear)
        }
    }
}
