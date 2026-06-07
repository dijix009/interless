import SwiftUI

public struct WorkspaceHistoryItemViewState: Sendable, Equatable, Codable, Identifiable {
    public var id: String { path }
    public var path: String
    public var lastOpenedAt: Date?

    public init(path: String, lastOpenedAt: Date? = nil) {
        self.path = path
        self.lastOpenedAt = lastOpenedAt
    }

    public var displayName: String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}

public struct WorkspaceHistoryView: View {
    public var items: [WorkspaceHistoryItemViewState]
    public var onOpen: @MainActor (String) -> Void

    public init(
        items: [WorkspaceHistoryItemViewState],
        onOpen: @escaping @MainActor (String) -> Void
    ) {
        self.items = items
        self.onOpen = onOpen
    }

    public var body: some View {
        List(items) { item in
            Button {
                onOpen(item.path)
            } label: {
                HStack {
                    Image(systemName: "folder")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.displayName)
                            .lineLimit(1)
                        Text(item.path)
                            .font(.metaMono)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)
        }
    }
}
