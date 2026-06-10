import SwiftUI
import Shared

public struct WorkspaceInspectorView: View {
    @Binding private var selectedTab: WorkspaceInspectorTab
    @Binding private var searchQuery: String
    @Binding private var fileTreeFilter: String
    public var state: WorkspaceViewState
    public var onSelectFile: @MainActor (String) -> Void
    public var onToggleDirectory: @MainActor (String) -> Void
    public var onOpenWorkspace: @MainActor () -> Void
    public var onSelectSearchHit: @MainActor (SearchHit) -> Void
    public var onSearch: @MainActor () -> Void
    public var onRefreshGit: @MainActor () -> Void
    public var onReviewDiff: @MainActor () -> Void
    public var onCancelJob: @MainActor (UUID) -> Void
    public var onOpenHealth: @MainActor () -> Void
    public var onExportDiagnostics: @MainActor () -> Void
    // Shared by key with the Settings "Diff layout" control.
    @AppStorage("chat.diffLayout") private var diffLayoutRaw = ChatDiffLayoutMode.inline.rawValue

    public init(
        selectedTab: Binding<WorkspaceInspectorTab>,
        searchQuery: Binding<String>,
        fileTreeFilter: Binding<String>,
        state: WorkspaceViewState,
        onSelectFile: @escaping @MainActor (String) -> Void,
        onToggleDirectory: @escaping @MainActor (String) -> Void,
        onOpenWorkspace: @escaping @MainActor () -> Void,
        onSelectSearchHit: @escaping @MainActor (SearchHit) -> Void,
        onSearch: @escaping @MainActor () -> Void,
        onRefreshGit: @escaping @MainActor () -> Void,
        onReviewDiff: @escaping @MainActor () -> Void,
        onCancelJob: @escaping @MainActor (UUID) -> Void,
        onOpenHealth: @escaping @MainActor () -> Void,
        onExportDiagnostics: @escaping @MainActor () -> Void
    ) {
        self._selectedTab = selectedTab
        self._searchQuery = searchQuery
        self._fileTreeFilter = fileTreeFilter
        self.state = state
        self.onSelectFile = onSelectFile
        self.onToggleDirectory = onToggleDirectory
        self.onOpenWorkspace = onOpenWorkspace
        self.onSelectSearchHit = onSelectSearchHit
        self.onSearch = onSearch
        self.onRefreshGit = onRefreshGit
        self.onReviewDiff = onReviewDiff
        self.onCancelJob = onCancelJob
        self.onOpenHealth = onOpenHealth
        self.onExportDiagnostics = onExportDiagnostics
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.C.surface)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: .space2) {
            HStack(spacing: .space2) {
                HStack(spacing: 2) {
                    ForEach(primaryTabs) { tab in
                        inspectorTextTab(tab)
                    }
                }
                .padding(2)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: .radiusSm, style: .continuous))
                Spacer(minLength: .space2)
            }
            HStack(spacing: .space2) {
                if selectedTab == .git {
                    Text(state.inspectorGit.branchLabel)
                        .font(.bodyS.weight(.semibold))
                        .foregroundStyle(Theme.C.textPrimary)
                        .lineLimit(1)
                } else {
                    Text(selectedTab.title)
                        .font(.bodyS.weight(.semibold))
                        .foregroundStyle(Theme.C.textPrimary)
                }
                Spacer(minLength: .space2)
                ForEach(secondaryTabs) { tab in
                    inspectorIconTab(tab)
                }
            }
        }
        .padding(.horizontal, .space3)
        .padding(.top, .space4 + 2)
        .padding(.bottom, .space2)
    }

    private var primaryTabs: [WorkspaceInspectorTab] {
        [.git, .files, .context, .diff]
    }

    private var secondaryTabs: [WorkspaceInspectorTab] {
        [.todos, .jobs, .timeline, .history]
    }

    private func inspectorTextTab(_ tab: WorkspaceInspectorTab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            Label(tab.title.lowercased(), systemImage: tab.symbolName)
                .labelStyle(.titleAndIcon)
                .font(.bodyS.weight(.semibold))
                .padding(.horizontal, .space3)
                .frame(height: 28)
                .background(
                    selectedTab == tab ? Theme.C.surface3 : Color.clear,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(selectedTab == tab ? Theme.C.textPrimary : Theme.C.textSecondary)
        .help(tab.title)
    }

    private func inspectorIconTab(_ tab: WorkspaceInspectorTab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            Image(systemName: tab.symbolName)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 24, height: 24)
                .background(
                    selectedTab == tab ? Theme.C.surface3 : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(selectedTab == tab ? Theme.C.textPrimary : Theme.C.textSecondary)
        .help(tab.title)
    }

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .context:
            inspectorScroll { contextContent }
        case .diff:
            diffContent
        case .files:
            filesContent
        case .git:
            inspectorScroll { gitContent }
        case .todos:
            inspectorScroll { todosContent }
        case .jobs:
            inspectorScroll { jobsContent }
        case .timeline:
            inspectorScroll { timelineContent }
        case .history:
            inspectorScroll { historyContent }
        }
    }

    private func inspectorScroll<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: .space3) {
                content()
            }
            .padding(.space3)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var contextContent: some View {
        VStack(alignment: .leading, spacing: .space3) {
            inspectorSection("Workspace", symbolName: "folder") {
                metadataRow("Path", state.workspacePath ?? "No workspace")
                metadataRow("Index", state.indexingSummary)
                metadataRow("Git", state.gitSummary)
            }
            inspectorSection("Selection", symbolName: "doc.text") {
                metadataRow("File", state.selectedFilePath ?? "No file selected")
                metadataRow("Preview", state.selectedFilePreview.kind.rawValue)
                if state.selectedFilePreview.byteCount > 0 {
                    metadataRow("Size", ByteCountFormatter.string(fromByteCount: Int64(state.selectedFilePreview.byteCount), countStyle: .file))
                }
            }
            if state.configStatus.hasLoadedConfig {
                ConfigStatusView(state: state.configStatus)
            }
        }
    }

    private var filesContent: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: .space2) {
                HStack {
                    Label("Files", systemImage: "doc.text")
                        .font(.titleS)
                    Spacer()
                    Button(action: onSearch) {
                        Image(systemName: "magnifyingglass")
                            .accessibilityLabel("Search")
                    }
                    .buttonStyle(.borderless)
                    .disabled(searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                inspectorTextField(
                    "Search workspace",
                    systemImage: "magnifyingglass",
                    text: $searchQuery,
                    onSubmit: onSearch)
                inspectorTextField(
                    "Filter files",
                    systemImage: "line.3.horizontal.decrease.circle",
                    text: $fileTreeFilter)
            }
            .padding(.space3)

            FileTreeView(
                rows: state.fileTreeRows,
                selectedPath: state.selectedFilePath,
                onSelect: onSelectFile,
                onToggleDirectory: onToggleDirectory,
                onOpen: onOpenWorkspace)
                .frame(minHeight: 260)

            if !state.searchHits.isEmpty {
                Divider()
                searchHits
                    .frame(maxHeight: 220)
            }
        }
    }

    private var searchHits: some View {
        List(state.searchHits, id: \.relativePath) { hit in
            Button {
                onSelectSearchHit(hit)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(hit.relativePath)
                        .font(.metaMono)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let snippet = hit.snippet, !snippet.isEmpty {
                        Text(snippet)
                            .font(.metaMono)
                            .foregroundStyle(Theme.C.textSecondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .scrollContentBackground(.hidden)
    }

    private var gitContent: some View {
        VStack(alignment: .leading, spacing: .space3) {
            HStack(spacing: .space2) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .foregroundStyle(Theme.C.accent)
                Text(state.inspectorGit.branchLabel)
                    .font(.titleS)
                    .foregroundStyle(Theme.C.textPrimary)
                    .lineLimit(1)
                Spacer()
                Button(action: onRefreshGit) {
                    Label("sync", systemImage: "arrow.clockwise")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderless)
            }

            HStack(spacing: 2) {
                gitModeChip("commit", isSelected: true)
                gitModeChip("update", isSelected: false)
                gitModeChip("pr", isSelected: false)
            }
            .padding(2)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: .radiusSm, style: .continuous))

            changedFilesSection("Staged", rows: state.inspectorGit.stagedFiles, emptyTitle: "No staged files")
            changedFilesSection("Changes", rows: state.inspectorGit.changedFiles, emptyTitle: "No workspace changes")
            commitCard
        }
    }

    private func gitModeChip(_ title: String, isSelected: Bool) -> some View {
        Text(title)
            .font(.bodyS.weight(.semibold))
            .foregroundStyle(isSelected ? Theme.C.textPrimary : Theme.C.textTertiary)
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .background(isSelected ? Theme.C.surface3 : Color.clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func changedFilesSection(_ title: String, rows: [ChangedFileRowViewState], emptyTitle: String) -> some View {
        VStack(alignment: .leading, spacing: .space2) {
            HStack {
                Text(title)
                    .font(.titleS)
                    .foregroundStyle(Theme.C.textPrimary)
                Text("\(rows.count)")
                    .font(.metaMono)
                    .foregroundStyle(Theme.C.textTertiary)
                Spacer()
            }
            if rows.isEmpty {
                emptyState(emptyTitle)
            } else {
                VStack(spacing: 0) {
                    ForEach(rows.prefix(24)) { row in
                        changedFileRow(row)
                    }
                }
                .background(Theme.C.surface2, in: RoundedRectangle(cornerRadius: .radiusSm, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: .radiusSm, style: .continuous)
                        .stroke(Theme.C.border, lineWidth: 1)
                }
            }
        }
    }

    private func changedFileRow(_ row: ChangedFileRowViewState) -> some View {
        HStack(spacing: .space2) {
            Text(row.isStaged ? "-" : "+")
                .font(.bodyS.weight(.semibold))
                .foregroundStyle(Theme.C.textTertiary)
                .frame(width: 10)
            Text(row.status)
                .font(.metaMono.weight(.semibold))
                .foregroundStyle(row.status == "D" ? Theme.C.diffDel : Theme.C.accent)
                .frame(width: 18)
            Image(systemName: "doc.text")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.C.textTertiary)
            Text(row.path)
                .font(.metaMono)
                .foregroundStyle(Theme.C.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: .space2)
            Text("+\(row.additions) / -\(row.deletions)")
                .font(.metaMono)
                .foregroundStyle(Theme.C.textTertiary)
            if row.canRevert {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.C.textTertiary)
            }
        }
        .padding(.horizontal, .space2)
        .frame(height: 32)
        .contentShape(Rectangle())
    }

    private var commitCard: some View {
        VStack(alignment: .leading, spacing: .space2) {
            Text("Commit")
                .font(.titleS)
                .foregroundStyle(Theme.C.textPrimary)
            VStack(alignment: .leading, spacing: .space2) {
                Text("Highlights")
                    .font(.metaMono)
                    .foregroundStyle(Theme.C.textTertiary)
                Text(state.inspectorGit.changedFiles.isEmpty ? "No changed files selected" : "Review changed files before committing")
                    .font(.bodyS)
                    .foregroundStyle(Theme.C.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.space3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.C.surface2, in: RoundedRectangle(cornerRadius: .radiusSm, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: .radiusSm, style: .continuous)
                    .stroke(Theme.C.border, lineWidth: 1)
            }
            HStack {
                Button("generate") {}
                    .disabled(true)
                Spacer()
                Button("commit") {}
                    .disabled(true)
                Button("commit & sync") {}
                    .disabled(true)
            }
            .font(.bodyS.weight(.semibold))
        }
    }

    private var diffContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: .space2) {
                Label("\(state.inspectorDiff.fileCount) files changed", systemImage: "plus.forwardslash.minus")
                    .font(.titleS)
                    .foregroundStyle(Theme.C.textPrimary)
                Spacer()
                Picker("Diff view", selection: .constant(state.inspectorDiff.viewMode)) {
                    Text("All files").tag(ChatDiffViewMode.allFiles)
                    Text("Single file").tag(ChatDiffViewMode.singleFile)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                Button(action: onReviewDiff) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(state.inspectorDiff.files.isEmpty && state.inspectorDiff.fallbackLines.isEmpty)
            }
            .padding(.space3)
            Divider()
            DiffViewer(
                files: state.inspectorDiff.files,
                fallbackLines: state.inspectorDiff.fallbackLines,
                layout: ChatDiffLayoutMode(rawValue: diffLayoutRaw) ?? .inline)
        }
    }

    private var todosContent: some View {
        VStack(alignment: .leading, spacing: .space3) {
            inspectorSection("Todos", symbolName: "checklist") {
                if state.todoPanel.items.isEmpty {
                    emptyState("No todos")
                } else {
                    TodoPanelView(state: state.todoPanel)
                }
            }
        }
    }

    private var jobsContent: some View {
        VStack(alignment: .leading, spacing: .space3) {
            inspectorSection("Jobs", symbolName: "bolt.horizontal") {
                if state.backgroundToolJobs.isEmpty {
                    emptyState("No background jobs")
                } else {
                    BackgroundJobsView(jobs: state.backgroundToolJobs, onCancel: onCancelJob)
                }
            }
        }
    }

    private var timelineContent: some View {
        VStack(alignment: .leading, spacing: .space3) {
            inspectorSection("Timeline", symbolName: "clock") {
                if state.sessionTimelineItems.isEmpty {
                    emptyState("No session events")
                } else {
                    SessionTimelineView(items: state.sessionTimelineItems)
                }
            }
        }
    }

    private var historyContent: some View {
        VStack(alignment: .leading, spacing: .space3) {
            inspectorSection("Workspace History", symbolName: "arrow.counterclockwise") {
                if state.workspaceHistory.isEmpty {
                    if let path = state.workspacePath {
                        metadataRow(URL(fileURLWithPath: path).lastPathComponent, path)
                    } else {
                        emptyState("No workspace history")
                    }
                } else {
                    ForEach(state.workspaceHistory) { item in
                        metadataRow(item.displayName, item.path)
                    }
                }
            }
            inspectorSection("Diagnostics", symbolName: "waveform.path.ecg") {
                HStack {
                    Button("Open Health", action: onOpenHealth)
                    Button("Export", action: onExportDiagnostics)
                }
            }
        }
    }

    private func inspectorSection<Content: View>(
        _ title: String,
        symbolName: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: .space2) {
            Label(title, systemImage: symbolName)
                .font(.titleS)
                .foregroundStyle(Theme.C.textPrimary)
            content()
        }
        .padding(.space3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(radius: .radiusSm)
    }

    private func inspectorTextField(
        _ placeholder: String,
        systemImage: String,
        text: Binding<String>,
        onSubmit: (@MainActor () -> Void)? = nil
    ) -> some View {
        HStack(spacing: .space2) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(Theme.C.textTertiary)
                .frame(width: 14)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.bodyS)
                .onSubmit {
                    onSubmit?()
                }
        }
        .padding(.horizontal, .space2)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: .radiusSm, style: .continuous))
    }

    private func metadataRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.labelMono)
                .foregroundStyle(Theme.C.textTertiary)
            Text(value)
                .font(.metaMono)
                .foregroundStyle(Theme.C.textSecondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func emptyState(_ title: String) -> some View {
        Text(title)
            .font(.metaMono)
            .foregroundStyle(Theme.C.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, .space1)
    }
}
