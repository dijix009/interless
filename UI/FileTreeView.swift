import SwiftUI

public struct FileTreeView: View {
    public var rows: [FileTreeVisibleRow]
    public var selectedPath: String?
    public var onSelect: @MainActor (String) -> Void
    public var onToggleDirectory: @MainActor (String) -> Void
    public var onOpen: @MainActor () -> Void

    public init(
        rows: [FileTreeVisibleRow],
        selectedPath: String?,
        onSelect: @escaping @MainActor (String) -> Void,
        onToggleDirectory: @escaping @MainActor (String) -> Void,
        onOpen: @escaping @MainActor () -> Void = {}
    ) {
        self.rows = rows
        self.selectedPath = selectedPath
        self.onSelect = onSelect
        self.onToggleDirectory = onToggleDirectory
        self.onOpen = onOpen
    }

    public var body: some View {
        List(rows) { row in
            HStack(spacing: 6) {
                Color.clear
                    .frame(width: CGFloat(row.depth) * 14)
                if row.node.isDirectory {
                    Image(systemName: row.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Color.clear.frame(width: 12)
                }
                Image(systemName: row.node.isDirectory ? "folder" : "doc.text")
                    .foregroundStyle(Theme.C.textTertiary)
                Text(row.node.name)
                    .font(.bodyS)
                    .lineLimit(1)
                Spacer()
            }
            .frame(minHeight: 28)
            .contentShape(Rectangle())
            .listRowBackground(
                ZStack(alignment: .leading) {
                    if row.path == selectedPath {
                        Theme.C.accentGlow
                        Rectangle().fill(Theme.C.accent).frame(width: 2)
                    }
                })
            .accessibilityLabel(row.accessibilityLabel)
            .accessibilityValue(row.node.isDirectory ? (row.isExpanded ? "Expanded" : "Collapsed") : row.path)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(row.node.isDirectory ? "Expands or collapses this folder" : "Opens this file")
            .accessibilityAction { selectRow(row) }
            .onTapGesture { selectRow(row) }
        }
        .overlay {
            if rows.isEmpty {
                ContentUnavailableView {
                    Label("No Workspace", systemImage: "folder.badge.questionmark")
                } description: {
                    Text("Open a folder to start working with the agent.")
                } actions: {
                    Button("Open Workspace", action: onOpen)
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.C.accent)
                }
            }
        }
    }

    private func selectRow(_ row: FileTreeVisibleRow) {
        if row.node.isDirectory {
            onToggleDirectory(row.path)
        } else {
            onSelect(row.path)
        }
    }
}
