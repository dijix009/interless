import SwiftUI

public struct SessionNavigatorView: View {
    @Binding private var query: String
    public var workspaceTitle: String
    public var showsWorkspaceActions: Bool
    public var sections: [SessionNavigatorSectionViewState]
    public var onSelect: @MainActor (SessionNavigatorItemViewState) -> Void
    public var onNewProjectChat: @MainActor () -> Void
    public var onNewPlainChat: @MainActor () -> Void
    public var onOpenWorkspace: @MainActor () -> Void
    public var onFocusSearch: @MainActor () -> Void
    public var onOpenSettings: @MainActor () -> Void
    public var onOpenHealth: @MainActor () -> Void
    public var onRenameSession: @MainActor (UUID, String) -> Void
    public var onDeleteSession: @MainActor (UUID) -> Void
    @State private var expandedSectionIDs: Set<String> = []
    @State private var renameTarget: SessionNavigatorItemViewState?
    @State private var renameTitle = ""
    @State private var isRenamePresented = false

    public init(
        query: Binding<String>,
        workspaceTitle: String,
        showsWorkspaceActions: Bool = true,
        sections: [SessionNavigatorSectionViewState],
        onSelect: @escaping @MainActor (SessionNavigatorItemViewState) -> Void,
        onNewProjectChat: @escaping @MainActor () -> Void,
        onNewPlainChat: @escaping @MainActor () -> Void,
        onOpenWorkspace: @escaping @MainActor () -> Void,
        onFocusSearch: @escaping @MainActor () -> Void,
        onOpenSettings: @escaping @MainActor () -> Void,
        onOpenHealth: @escaping @MainActor () -> Void,
        onRenameSession: @escaping @MainActor (UUID, String) -> Void,
        onDeleteSession: @escaping @MainActor (UUID) -> Void
    ) {
        self._query = query
        self.workspaceTitle = workspaceTitle
        self.showsWorkspaceActions = showsWorkspaceActions
        self.sections = sections
        self.onSelect = onSelect
        self.onNewProjectChat = onNewProjectChat
        self.onNewPlainChat = onNewPlainChat
        self.onOpenWorkspace = onOpenWorkspace
        self.onFocusSearch = onFocusSearch
        self.onOpenSettings = onOpenSettings
        self.onOpenHealth = onOpenHealth
        self.onRenameSession = onRenameSession
        self.onDeleteSession = onDeleteSession
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            actionStrip
            searchField
            sessionSections
        }
        .onAppear(perform: initializeExpandedSections)
        .onChange(of: sections.map(\.id)) { _, _ in
            initializeExpandedSections()
        }
        .alert("Rename Session", isPresented: $isRenamePresented) {
            TextField("Session name", text: $renameTitle)
            Button("Rename") {
                guard let sessionID = renameTarget?.sessionID else { return }
                onRenameSession(sessionID, renameTitle)
                renameTarget = nil
                renameTitle = ""
            }
            Button("Cancel", role: .cancel) {
                renameTarget = nil
                renameTitle = ""
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: .space2) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(Theme.C.textTertiary)
            TextField("Find sessions", text: $query)
                .textFieldStyle(.plain)
                .font(.bodyS)
        }
        .padding(.horizontal, .space2)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: .radiusSm, style: .continuous))
    }

    private var actionStrip: some View {
        HStack(spacing: 6) {
            if showsWorkspaceActions {
                navigatorIconAction("New workspace chat", symbolName: "square.and.pencil", action: onNewProjectChat)
                navigatorIconAction("Open workspace", symbolName: "folder.badge.plus", action: onOpenWorkspace)
                navigatorIconAction("Files and search", symbolName: "magnifyingglass", action: onFocusSearch)
            } else {
                navigatorIconAction("New plain chat", symbolName: "square.and.pencil", action: onNewPlainChat)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, .space1)
    }

    private var sessionSections: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(filteredSections) { section in
                DisclosureGroup(isExpanded: expandedBinding(for: section.id)) {
                    if section.items.isEmpty {
                        emptyRow("No sessions")
                    } else {
                        VStack(alignment: .leading, spacing: 1) {
                            ForEach(section.items) { item in
                                itemRow(item)
                            }
                        }
                        .padding(.top, 2)
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: section.symbolName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.C.textTertiary)
                            .frame(width: 16, alignment: .center)
                        Text(section.title.lowercased())
                            .font(.bodyS.weight(.medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: .space2)
                        Text("\(section.items.count)")
                            .font(.metaMono)
                            .foregroundStyle(Theme.C.textTertiary)
                    }
                    .foregroundStyle(Theme.C.textSecondary)
                    .padding(.top, 2)
                }
                .font(.bodyS)
                .tint(Theme.C.textSecondary)
            }
        }
    }

    private var filteredSections: [SessionNavigatorSectionViewState] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return sections }
        return sections.compactMap { section in
            let matchingItems = section.items.filter {
                $0.title.localizedCaseInsensitiveContains(trimmed)
                    || ($0.subtitle?.localizedCaseInsensitiveContains(trimmed) ?? false)
            }
            guard !matchingItems.isEmpty || section.title.localizedCaseInsensitiveContains(trimmed) else { return nil }
            var copy = section
            copy.items = matchingItems
            return copy
        }
    }

    private func navigatorIconAction(_ title: String, symbolName: String, action: @escaping @MainActor () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbolName)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(SidebarNavigatorIconButtonStyle())
        .help(title)
    }

    private func itemRow(_ item: SessionNavigatorItemViewState) -> some View {
        Button {
            guard item.isEnabled else { return }
            onSelect(item)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: item.symbolName)
                    .font(.system(size: 13))
                    .foregroundStyle(iconColor(for: item))
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(item.title)
                            .font(.bodyS.weight(item.isSelected ? .semibold : .regular))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .foregroundStyle(item.isMuted ? Theme.C.textTertiary : Theme.C.textPrimary)
                        if item.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.caption2)
                                .foregroundStyle(Theme.C.textTertiary)
                        }
                    }
                    HStack(spacing: 5) {
                        if let branchLabel = item.branchLabel, !branchLabel.isEmpty {
                            Text(branchLabel)
                                .font(.metaMono)
                                .foregroundStyle(Theme.C.accent2)
                                .lineLimit(1)
                        }
                        if let subtitle = item.subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.metaMono)
                                .foregroundStyle(Theme.C.textTertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        if let changeSummary = item.changeSummary, !changeSummary.isEmpty {
                            Text(changeSummary)
                                .font(.metaMono)
                                .foregroundStyle(Theme.C.diffAdd)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: .space2)
                VStack(alignment: .trailing, spacing: 3) {
                    if let relativeTime = item.relativeTime, !relativeTime.isEmpty {
                        Text(relativeTime)
                            .font(.metaMono)
                            .foregroundStyle(Theme.C.textTertiary)
                            .lineLimit(1)
                    }
                    rowBadges(item)
                }
            }
            .foregroundStyle(item.isEnabled ? Theme.C.textPrimary : Theme.C.textTertiary)
            .padding(.horizontal, .space2)
            .padding(.vertical, 5)
            .background(item.isSelected ? Theme.C.accentGlow : Color.clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!item.isEnabled)
        .contextMenu {
            if item.kind == .session, !item.isDraft, let sessionID = item.sessionID {
                Button {
                    renameTarget = item
                    renameTitle = item.title
                    isRenamePresented = true
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    onDeleteSession(sessionID)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    @ViewBuilder
    private func rowBadges(_ item: SessionNavigatorItemViewState) -> some View {
        if item.isActiveNow {
            Circle()
                .fill(Theme.C.diffAdd)
                .frame(width: 7, height: 7)
                .help("Active now")
        }
        if item.isInterrupted {
            Image(systemName: "pause.circle")
                .font(.caption)
                .foregroundStyle(.orange)
                .help("Interrupted")
        }
        if item.unreadCount > 0 {
            Text("\(item.unreadCount)")
                .font(.metaMono)
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Theme.C.accent, in: Capsule())
        }
    }

    private func emptyRow(_ title: String) -> some View {
        Text(title)
            .font(.metaMono)
            .foregroundStyle(Theme.C.textTertiary)
            .padding(.horizontal, .space2)
            .padding(.vertical, 6)
    }

    private func iconColor(for item: SessionNavigatorItemViewState) -> Color {
        if item.isInterrupted { return .orange }
        if item.isActiveNow { return Theme.C.diffAdd }
        return Theme.C.textTertiary
    }

    private func initializeExpandedSections() {
        if expandedSectionIDs.isEmpty {
            expandedSectionIDs = Set(sections.filter { !$0.isCollapsedByDefault }.map(\.id))
        } else {
            let validIDs = Set(sections.map(\.id))
            expandedSectionIDs.formIntersection(validIDs)
            for section in sections where !section.isCollapsedByDefault {
                expandedSectionIDs.insert(section.id)
            }
        }
    }

    private func expandedBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { expandedSectionIDs.contains(id) },
            set: { isExpanded in
                if isExpanded {
                    expandedSectionIDs.insert(id)
                } else {
                    expandedSectionIDs.remove(id)
                }
            })
    }
}

private struct SidebarNavigatorIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.C.textSecondary)
            .frame(width: 24, height: 24)
            .background(configuration.isPressed ? Color.primary.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
    }
}
