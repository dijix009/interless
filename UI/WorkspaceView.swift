import Shared
import SwiftUI

private enum SidebarMode {
    case chat
    case code
}

public struct WorkspaceViewActions {
    public var openWorkspace: @MainActor () -> Void
    public var reindex: @MainActor () -> Void
    public var selectFile: @MainActor (String) -> Void
    public var toggleFileTreeDirectory: @MainActor (String) -> Void
    public var selectSearchHit: @MainActor (SearchHit) -> Void
    public var search: @MainActor () -> Void
    public var refreshGit: @MainActor () -> Void
    public var startNewChat: @MainActor (_ isPlainChat: Bool) -> Void
    public var setPlainChatMode: @MainActor (_ isPlainChat: Bool) -> Void
    public var selectChatThread: @MainActor (UUID) -> Void
    public var renameChatThread: @MainActor (UUID, String) -> Void
    public var sendChat: @MainActor () -> Void
    public var sendPlainChat: @MainActor () -> Void
    public var cancelChat: @MainActor () -> Void
    public var focusChat: @MainActor () -> Void
    public var focusSearch: @MainActor () -> Void
    public var openHealth: @MainActor () -> Void
    public var addChatContextFiles: @MainActor () -> Void
    public var deleteChatThread: @MainActor (UUID) -> Void
    public var dismissNotice: @MainActor (UUID) -> Void
    public var setPatchHunkAccepted: @MainActor (_ fileID: String, _ hunkID: Int, _ isAccepted: Bool) -> Void
    public var loadCurrentDiffForReview: @MainActor () -> Void
    public var applyAcceptedPatch: @MainActor () -> Void
    public var discardPatchProposal: @MainActor () -> Void
    public var dismissModelOnboarding: @MainActor () -> Void
    public var applyRecommendedModels: @MainActor () -> Void
    public var loadModels: @MainActor () -> Void
    public var unloadModels: @MainActor () -> Void
    public var cancelModelLoad: @MainActor () -> Void
    public var saveHuggingFaceToken: @MainActor (String) -> Void
    public var deleteHuggingFaceToken: @MainActor () -> Void
    public var retryRecoveryAction: @MainActor (UUID) -> Void
    public var dismissRecoveryItem: @MainActor (UUID) -> Void
    public var clearRecoveryJournal: @MainActor () -> Void
    public var exportDiagnostics: @MainActor () -> Void
    public var resolvePermissionPrompt: @MainActor (UUID, PermissionPromptAction) -> Void
    public var answerQuestionPrompt: @MainActor (UUID, String) -> Void
    public var cancelQuestionPrompt: @MainActor (UUID) -> Void
    public var cancelBackgroundJob: @MainActor (UUID) -> Void
    public var setReasoningEffort: @MainActor (ReasoningEffort) -> Void
    public var setModelContextSettings: @MainActor (ModelContextSettingsViewState) -> Void

    public init(
        openWorkspace: @escaping @MainActor () -> Void,
        reindex: @escaping @MainActor () -> Void,
        selectFile: @escaping @MainActor (String) -> Void,
        toggleFileTreeDirectory: @escaping @MainActor (String) -> Void,
        selectSearchHit: @escaping @MainActor (SearchHit) -> Void,
        search: @escaping @MainActor () -> Void,
        refreshGit: @escaping @MainActor () -> Void,
        startNewChat: @escaping @MainActor (_ isPlainChat: Bool) -> Void = { _ in },
        setPlainChatMode: @escaping @MainActor (_ isPlainChat: Bool) -> Void = { _ in },
        selectChatThread: @escaping @MainActor (UUID) -> Void = { _ in },
        renameChatThread: @escaping @MainActor (UUID, String) -> Void = { _, _ in },
        sendChat: @escaping @MainActor () -> Void,
        sendPlainChat: @escaping @MainActor () -> Void = {},
        cancelChat: @escaping @MainActor () -> Void,
        focusChat: @escaping @MainActor () -> Void = {},
        focusSearch: @escaping @MainActor () -> Void = {},
        openHealth: @escaping @MainActor () -> Void = {},
        addChatContextFiles: @escaping @MainActor () -> Void = {},
        deleteChatThread: @escaping @MainActor (UUID) -> Void = { _ in },
        dismissNotice: @escaping @MainActor (UUID) -> Void,
        setPatchHunkAccepted: @escaping @MainActor (_ fileID: String, _ hunkID: Int, _ isAccepted: Bool) -> Void,
        loadCurrentDiffForReview: @escaping @MainActor () -> Void,
        applyAcceptedPatch: @escaping @MainActor () -> Void,
        discardPatchProposal: @escaping @MainActor () -> Void,
        dismissModelOnboarding: @escaping @MainActor () -> Void,
        applyRecommendedModels: @escaping @MainActor () -> Void,
        loadModels: @escaping @MainActor () -> Void,
        unloadModels: @escaping @MainActor () -> Void,
        cancelModelLoad: @escaping @MainActor () -> Void,
        saveHuggingFaceToken: @escaping @MainActor (String) -> Void = { _ in },
        deleteHuggingFaceToken: @escaping @MainActor () -> Void = {},
        retryRecoveryAction: @escaping @MainActor (UUID) -> Void,
        dismissRecoveryItem: @escaping @MainActor (UUID) -> Void,
        clearRecoveryJournal: @escaping @MainActor () -> Void,
        exportDiagnostics: @escaping @MainActor () -> Void = {},
        resolvePermissionPrompt: @escaping @MainActor (UUID, PermissionPromptAction) -> Void = { _, _ in },
        answerQuestionPrompt: @escaping @MainActor (UUID, String) -> Void = { _, _ in },
        cancelQuestionPrompt: @escaping @MainActor (UUID) -> Void = { _ in },
        cancelBackgroundJob: @escaping @MainActor (UUID) -> Void = { _ in },
        setReasoningEffort: @escaping @MainActor (ReasoningEffort) -> Void = { _ in },
        setModelContextSettings: @escaping @MainActor (ModelContextSettingsViewState) -> Void = { _ in }
    ) {
        self.openWorkspace = openWorkspace
        self.reindex = reindex
        self.selectFile = selectFile
        self.toggleFileTreeDirectory = toggleFileTreeDirectory
        self.selectSearchHit = selectSearchHit
        self.search = search
        self.refreshGit = refreshGit
        self.startNewChat = startNewChat
        self.setPlainChatMode = setPlainChatMode
        self.selectChatThread = selectChatThread
        self.renameChatThread = renameChatThread
        self.sendChat = sendChat
        self.sendPlainChat = sendPlainChat
        self.cancelChat = cancelChat
        self.focusChat = focusChat
        self.focusSearch = focusSearch
        self.openHealth = openHealth
        self.addChatContextFiles = addChatContextFiles
        self.deleteChatThread = deleteChatThread
        self.dismissNotice = dismissNotice
        self.setPatchHunkAccepted = setPatchHunkAccepted
        self.loadCurrentDiffForReview = loadCurrentDiffForReview
        self.applyAcceptedPatch = applyAcceptedPatch
        self.discardPatchProposal = discardPatchProposal
        self.dismissModelOnboarding = dismissModelOnboarding
        self.applyRecommendedModels = applyRecommendedModels
        self.loadModels = loadModels
        self.unloadModels = unloadModels
        self.cancelModelLoad = cancelModelLoad
        self.saveHuggingFaceToken = saveHuggingFaceToken
        self.deleteHuggingFaceToken = deleteHuggingFaceToken
        self.retryRecoveryAction = retryRecoveryAction
        self.dismissRecoveryItem = dismissRecoveryItem
        self.clearRecoveryJournal = clearRecoveryJournal
        self.exportDiagnostics = exportDiagnostics
        self.resolvePermissionPrompt = resolvePermissionPrompt
        self.answerQuestionPrompt = answerQuestionPrompt
        self.cancelQuestionPrompt = cancelQuestionPrompt
        self.cancelBackgroundJob = cancelBackgroundJob
        self.setReasoningEffort = setReasoningEffort
        self.setModelContextSettings = setModelContextSettings
    }
}

public struct WorkspaceView: View {
    public var state: WorkspaceViewState
    @Binding private var chatDraft: String
    @Binding private var searchQuery: String
    @Binding private var fileTreeFilter: String
    @Binding private var settings: ModelSettingsViewState
    @Binding private var isSettingsPresented: Bool
    @Binding private var isHealthPresented: Bool
    public var actions: WorkspaceViewActions
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedSidebarMode: SidebarMode = .chat
    @State private var selectedInspectorTab: WorkspaceInspectorTab = .git
    // Persisted pane state — survives relaunch (like Xcode / Linear / VS Code).
    @AppStorage("workspace.inspectorVisible") private var isInspectorVisible = false
    @AppStorage("workspace.sidebarHidden") private var sidebarHidden = false
    @AppStorage("workspace.sidebarWidth") private var sidebarWidthRaw: Double = 260
    // Live chat-surface prefs (shared by key with SettingsHubView toggles).
    @AppStorage("chat.showReasoningTraces") private var showReasoningTraces = true
    @AppStorage("chat.wideChatLayout") private var wideChatLayout = false
    @AppStorage("chat.userMessageRendering") private var userMessageRenderingRaw = UserMessageRenderingMode.plainText.rawValue
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var isCommandPalettePresented = false
    @State private var sessionNavigatorQuery = ""
    @State private var isWindowFullscreen = false
    @State private var didSyncInitialSidebarMode = false
    private let minSidebarWidth: Double = 200
    private let maxSidebarWidth: Double = 420
    private var sidebarWidth: CGFloat { CGFloat(sidebarWidthRaw) }
    private let collapsedLeadingControlsWidth: CGFloat = 146
    private let trafficLightClearance: CGFloat = 78
    private let fullscreenLeadingClearance: CGFloat = 14
    private let trafficLightHorizontalOffset: CGFloat = 10
    private let trafficLightVerticalOffset: CGFloat = 7
    private let topBarHeight: CGFloat = 42
    private let topBarTopPadding: CGFloat = 0
    private let sidebarContentTopPadding: CGFloat = 48

    public init(
        state: WorkspaceViewState,
        chatDraft: Binding<String>,
        searchQuery: Binding<String>,
        fileTreeFilter: Binding<String>,
        settings: Binding<ModelSettingsViewState>,
        isSettingsPresented: Binding<Bool>,
        isHealthPresented: Binding<Bool>,
        actions: WorkspaceViewActions
    ) {
        self.state = state
        self._chatDraft = chatDraft
        self._searchQuery = searchQuery
        self._fileTreeFilter = fileTreeFilter
        self._settings = settings
        self._isSettingsPresented = isSettingsPresented
        self._isHealthPresented = isHealthPresented
        self.actions = actions
    }

    // NOTE: `body` is split into staged computed properties below. The full
    // modifier chain in a single expression exceeds the Swift type-checker's
    // time budget ("unable to type-check in reasonable time"); applying the
    // overlays, lifecycle handlers, and sheet in stages is behavior-preserving
    // (modifier order is the same) and compiles quickly.
    public var body: some View {
        decoratedContent
            .sheet(isPresented: Binding(
                get: { state.isPatchReviewPresented },
                set: { if !$0 { actions.discardPatchProposal() } }
            )) {
                PatchReviewView(
                    proposal: state.patchProposal,
                    writesAllowed: settings.allowWrites,
                    onSetHunkAccepted: actions.setPatchHunkAccepted,
                    onApply: actions.applyAcceptedPatch,
                    onDiscard: actions.discardPatchProposal)
            }
    }

    private var layeredContent: some View {
        ZStack(alignment: .top) {
            mainContent
            edgeShadowOverlay
            topBar
            noticeOverlay
        }
        .overlay(alignment: .bottom) {
            bottomChrome
                .ignoresSafeArea(.container, edges: .bottom)
        }
        .safeAreaInset(edge: .bottom) {
            activityStrip
        }
        .overlay { settingsOverlay }
        .overlay { healthOverlay }
        .overlay { commandPaletteOverlay }
        .background { commandPaletteHotkey }
        .background {
            ZStack {
                TrafficLightAlignmentProbe(
                    horizontalOffset: trafficLightHorizontalOffset,
                    verticalOffset: trafficLightVerticalOffset)
                WindowFullscreenObserver(isFullscreen: $isWindowFullscreen)
            }
            .frame(width: 0, height: 0)
        }
    }

    private var decoratedContent: some View {
        layeredContent
            .onExitCommand {
                if isSettingsPresented {
                    isSettingsPresented = false
                } else if isHealthPresented {
                    isHealthPresented = false
                }
            }
            .onAppear {
                // Restore persisted sidebar visibility.
                columnVisibility = sidebarHidden ? .detailOnly : .all
                guard !didSyncInitialSidebarMode else { return }
                didSyncInitialSidebarMode = true
                actions.setPlainChatMode(true)
            }
            .onChange(of: columnVisibility) { _, newValue in
                sidebarHidden = (newValue == .detailOnly)
            }
            .onChange(of: state.focusTarget) { _, newValue in
                if newValue == .search {
                    if selectedSidebarMode == .code {
                        selectedInspectorTab = .files
                        isInspectorVisible = true
                    }
                }
            }
    }

    private var mainContent: some View {
        HStack(spacing: 0) {
            if columnVisibility != .detailOnly {
                sidebar
                    .frame(width: sidebarWidth)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                ResizableDivider(
                    width: $sidebarWidthRaw,
                    minWidth: minSidebarWidth,
                    maxWidth: maxSidebarWidth)
            }
            ZStack(alignment: .trailing) {
                HSplitView {
                    ChatPaneView(
                        messages: state.chatMessages,
                        draft: $chatDraft,
                        focusTarget: state.focusTarget,
                        modelName: selectedChatModelName,
                        modelStatus: state.modelStatus,
                        modelDownloadProgress: state.modelDownloadProgress,
                        availableModels: availableModels,
                        agentName: selectedAgentTitle,
                        agentItems: agentSwitcherItems,
                        selectedAgentID: state.selectedAgentID ?? agentSwitcherItems.first?.id,
                        preferences: effectiveChatPreferences,
                        showsWorkspaceComposerControls: selectedSidebarMode == .code,
                        contextUsageLabel: effectiveChrome.contextUsageLabel,
                        contextUsageFraction: effectiveChrome.contextUsageFraction,
                        reasoningEffort: state.selectedReasoningEffort,
                        reasoningOptions: state.reasoningOptions,
                        changedFileSummary: selectedSidebarMode == .code ? changedFileSummary : nil,
                        permissionPrompt: state.permissionPrompt,
                        questionPrompt: state.questionPrompt,
                        attachments: [],
                        promptSuggestions: promptSuggestions,
                        queuedPrompts: state.queuedPrompts,
                        onSend: selectedSidebarMode == .chat ? actions.sendPlainChat : actions.sendChat,
                        onCancel: actions.cancelChat,
                        onSelectModel: { isSettingsPresented = true },
                        onSelectModelID: selectAndLoadChatModel,
                        onSelectAgent: { _ in },
                        onSelectReasoningEffort: actions.setReasoningEffort,
                        onPlus: actions.addChatContextFiles,
                        onResolvePermission: { action in
                            guard let prompt = state.permissionPrompt else { return }
                            actions.resolvePermissionPrompt(prompt.id, action)
                        },
                        onAnswerQuestion: { answer in
                            guard let prompt = state.questionPrompt else { return }
                            actions.answerQuestionPrompt(prompt.id, answer)
                        },
                        onCancelQuestion: {
                            guard let prompt = state.questionPrompt else { return }
                            actions.cancelQuestionPrompt(prompt.id)
                        })
                        .frame(minWidth: 380, idealWidth: 560, maxWidth: .infinity)
                    if isInspectorVisible, selectedSidebarMode == .code {
                        WorkspaceInspectorView(
                            selectedTab: $selectedInspectorTab,
                            searchQuery: $searchQuery,
                            fileTreeFilter: $fileTreeFilter,
                            state: state,
                            onSelectFile: actions.selectFile,
                            onToggleDirectory: actions.toggleFileTreeDirectory,
                            onOpenWorkspace: actions.openWorkspace,
                            onSelectSearchHit: actions.selectSearchHit,
                            onSearch: actions.search,
                            onRefreshGit: actions.refreshGit,
                            onReviewDiff: actions.loadCurrentDiffForReview,
                            onCancelJob: actions.cancelBackgroundJob,
                            onOpenHealth: actions.openHealth,
                            onExportDiagnostics: actions.exportDiagnostics)
                            .frame(minWidth: 300, idealWidth: 360, maxWidth: 480)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // Custom in-content top bar (replaces the system toolbar + title-bar accessory).
    // The whole bar is a window-drag region; the buttons sit on top of it.
    private var topBar: some View {
        GeometryReader { geometry in
            HStack(spacing: 10) {
                HStack(spacing: .space2) {
                    Color.clear.frame(width: leadingControlClearance, height: 1)
                    sidebarToggleButton
                    if columnVisibility == .detailOnly {
                        collapsedNewChatButton
                    }
                }
                .frame(width: leadingControlsFrameWidth, alignment: .leading)

                topBarTitleBlock
                .frame(maxWidth: 480, alignment: .leading)

                Spacer(minLength: .space4)

                if selectedSidebarMode == .code {
                    topBarInspectorButton
                        .padding(.trailing, .space3)
                }
            }
            .frame(width: geometry.size.width, height: topBarHeight, alignment: .center)
        }
        .padding(.top, topBarTopPadding)
        .frame(height: topBarHeight, alignment: .top)
        .background {
            WindowDragHandle()
        }
    }

    private var topBarTitleBlock: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(effectiveChrome.title)
                .font(.bodyS.weight(.semibold))
                .foregroundStyle(Theme.C.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .shadow(color: titleShadowColor, radius: 4, x: 0, y: 1)
            if selectedSidebarMode == .code {
                HStack(spacing: 5) {
                    Text(effectiveChrome.subtitle)
                    if let branch = effectiveChrome.branchLabel, !branch.isEmpty {
                        Text(branch)
                    }
                    if let changes = effectiveChrome.changeSummary, !changes.isEmpty {
                        Text(changes)
                            .foregroundStyle(Theme.C.diffAdd)
                    }
                }
                .font(.metaMono)
                .foregroundStyle(Theme.C.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .shadow(color: titleShadowColor, radius: 4, x: 0, y: 1)
            }
        }
    }

    // Dark-first: a subtle dark halo only deepens the floating title over content
    // in dark mode. In light mode the adaptive top scrim handles legibility, so we
    // drop the shadow entirely (a black halo on cream reads muddy and un-native).
    private var titleShadowColor: Color {
        colorScheme == .dark ? .black.opacity(0.55) : .clear
    }

    // Floating top bar needs a legible backing. Dark-first: in dark we keep a
    // black vignette for depth; in light we use a clean scrim of the window
    // background colour (cream) fading to clear — no black halos on light.
    private var edgeShadowOverlay: some View {
        let isDark = colorScheme == .dark
        return ZStack {
            VStack(spacing: 0) {
                // Top scrim: legibility backing for the title block.
                LinearGradient(
                    colors: isDark
                        ? [.black.opacity(0.42), .black.opacity(0.16), .clear]
                        : [Theme.C.bg.opacity(0.96), Theme.C.bg.opacity(0.65), .clear],
                    startPoint: .top,
                    endPoint: .bottom)
                    .frame(height: 82)
                Spacer(minLength: 0)
                // Bottom vignette: dark-mode depth only.
                if isDark {
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.16), .black.opacity(0.32)],
                        startPoint: .top,
                        endPoint: .bottom)
                        .frame(height: 64)
                }
            }
            // Side vignettes: dark-mode depth only.
            if isDark {
                HStack(spacing: 0) {
                    LinearGradient(
                        colors: [.black.opacity(0.28), .clear],
                        startPoint: .leading,
                        endPoint: .trailing)
                        .frame(width: 22)
                    Spacer(minLength: 0)
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.28)],
                        startPoint: .leading,
                        endPoint: .trailing)
                        .frame(width: 22)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private var leadingControlClearance: CGFloat {
        isWindowFullscreen ? fullscreenLeadingClearance : trafficLightClearance
    }

    private var leadingControlsFrameWidth: CGFloat {
        guard columnVisibility == .detailOnly else { return sidebarWidth }
        guard isWindowFullscreen else { return collapsedLeadingControlsWidth }
        let reclaimedTrafficSpace = trafficLightClearance - fullscreenLeadingClearance
        return max(86, collapsedLeadingControlsWidth - reclaimedTrafficSpace)
    }

    // Overlay the user's live toggle choices onto the base chat-surface prefs.
    private var effectiveChatPreferences: ChatSurfacePreferences {
        var prefs = state.chatSurfacePreferences
        prefs.showReasoningTraces = showReasoningTraces
        prefs.wideChatLayout = wideChatLayout
        prefs.userMessageRendering = UserMessageRenderingMode(rawValue: userMessageRenderingRaw) ?? .plainText
        return prefs
    }

    private var effectiveChrome: WorkspaceChromeViewState {
        let title = state.chrome.title == "New Chat" ? currentChatTitle : state.chrome.title
        let workspace = projectFolderName
        let subtitle = state.workspacePath == nil ? "No workspace" : workspace
        let additions = state.diffFiles.reduce(0) { $0 + $1.additions }
        let deletions = state.diffFiles.reduce(0) { $0 + $1.deletions }
        let changeSummary = additions + deletions > 0 ? "+\(additions) -\(deletions)" : nil
        let modelLabel = selectedChatModelName.isEmpty ? state.modelStatus.label : URL(fileURLWithPath: selectedChatModelName).lastPathComponent
        return WorkspaceChromeViewState(
            title: title,
            subtitle: state.chrome.subtitle == "No workspace" ? subtitle : state.chrome.subtitle,
            branchLabel: state.chrome.branchLabel,
            changeSummary: state.chrome.changeSummary ?? changeSummary,
            contextUsageLabel: state.chrome.contextUsageLabel,
            contextUsageFraction: state.chrome.contextUsageFraction,
            runtimeLabel: state.chrome.runtimeLabel,
            modelLabel: state.chrome.modelLabel == "No model" ? modelLabel : state.chrome.modelLabel,
            isIndexing: state.isIndexing)
    }

    private var sidebarToggleButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.22)) {
                columnVisibility = (columnVisibility == .detailOnly) ? .all : .detailOnly
            }
        } label: { Image(systemName: "sidebar.left") }
        .buttonStyle(IconButtonStyle(active: columnVisibility != .detailOnly))
        .help("Toggle Sidebar (⌃⌘S)")
        .keyboardShortcut("s", modifiers: [.control, .command])
    }

    private var sidebarModeToggle: some View {
        SegmentedToggle(selection: $selectedSidebarMode, options: [
            (SidebarMode.chat, "Chat"),
            (SidebarMode.code, "Code"),
        ])
        .frame(maxWidth: .infinity)
        .frame(height: 28)
        .onChange(of: selectedSidebarMode) { _, mode in
            actions.setPlainChatMode(mode == .chat)
            if mode == .chat {
                isInspectorVisible = false
            }
        }
    }

    private var collapsedNewChatButton: some View {
        Button { actions.startNewChat(selectedSidebarMode == .chat) } label: {
            Image(systemName: "square.and.pencil")
                .accessibilityLabel("New chat")
        }
        .buttonStyle(IconButtonStyle())
        .offset(y: -1)
        .help("New Chat")
    }

    private var topBarInspectorButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { isInspectorVisible.toggle() }
        } label: {
            Image(systemName: "sidebar.right")
                .accessibilityLabel(isInspectorVisible ? "Hide inspector" : "Show inspector")
        }
        .buttonStyle(IconButtonStyle(active: isInspectorVisible))
        .help(isInspectorVisible ? "Hide Inspector" : "Show Inspector")
    }

    private var settingsButton: some View {
        Button { isSettingsPresented = true } label: { Image(systemName: "gearshape") }
            .buttonStyle(IconButtonStyle())
            .help("Settings (⌘,)")
    }

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                sidebarModeToggle
                SessionNavigatorView(
                    query: $sessionNavigatorQuery,
                    workspaceTitle: projectFolderName,
                    showsWorkspaceActions: selectedSidebarMode == .code,
                    sections: sessionNavigatorSections,
                    onSelect: selectNavigatorItem,
                    onNewProjectChat: {
                        selectedSidebarMode = .code
                        actions.startNewChat(false)
                    },
                    onNewPlainChat: {
                        selectedSidebarMode = .chat
                        actions.startNewChat(true)
                    },
                    onOpenWorkspace: actions.openWorkspace,
                    onFocusSearch: {
                        selectedSidebarMode = .code
                        selectedInspectorTab = .files
                        isInspectorVisible = true
                        actions.focusSearch()
                    },
                    onOpenSettings: { isSettingsPresented = true },
                    onOpenHealth: actions.openHealth,
                    onRenameSession: actions.renameChatThread,
                    onDeleteSession: actions.deleteChatThread)
            }
            .padding(.horizontal, .space3)
            .padding(.top, sidebarContentTopPadding)
            .padding(.bottom, 76)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            Theme.C.sidebar
                .ignoresSafeArea()
        }
    }

    // Selectable models: only explicitly configured chat models. Onboarding
    // recommendations stay in Settings so placeholder IDs do not leak here.
    private var availableModels: [String] {
        ChatComposerModel.availableModelIDs(
            settings: settings,
            localModelIDs: state.availableChatModelIDs)
    }

    private var selectedChatModelName: String {
        let configured = settings.orchestratorModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        return availableModels.contains(configured) ? configured : ""
    }

    @MainActor
    private func selectAndLoadChatModel(_ id: String) {
        let selected = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selected.isEmpty else { return }
        let shouldLoad = ChatComposerModel.shouldLoadSelectedModel(
            currentModelID: settings.orchestratorModelID,
            selectedModelID: selected,
            status: state.modelStatus)
        settings.orchestratorModelID = selected
        guard shouldLoad else { return }
        Task { @MainActor in
            await Task.yield()
            actions.loadModels()
        }
    }

    private var currentChatTitle: String {
        let userMessage = state.chatMessages.first { $0.role == .user }?.text
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let userMessage, !userMessage.isEmpty else { return "New Chat" }
        let firstLine = userMessage.split(whereSeparator: \.isNewline).first.map(String.init) ?? userMessage
        if firstLine.count <= 42 { return firstLine }
        return String(firstLine.prefix(39)) + "..."
    }

    private var projectChatThreads: [ChatThreadViewState] {
        if !state.chatThreads.isEmpty {
            return state.chatThreads
        }
        return [.init(title: currentChatTitle, isSelected: true, isDraft: true, shortcut: "⌘1")]
    }

    private var globalChatThreads: [ChatThreadViewState] {
        if !state.globalChatThreads.isEmpty {
            return state.globalChatThreads
        }
        return [.init(title: currentChatTitle, isSelected: true, isDraft: true, shortcut: "⌘1")]
    }

    private var sessionNavigatorSections: [SessionNavigatorSectionViewState] {
        let sections = SessionNavigatorModel.sections(
            workspaceName: projectFolderName,
            workspacePath: state.workspacePath,
            projectThreads: projectChatThreads,
            plainThreads: globalChatThreads,
            jobs: state.backgroundToolJobs)
        return sections.compactMap(filterNavigatorSectionForSelectedMode)
    }

    private func filterNavigatorSectionForSelectedMode(_ section: SessionNavigatorSectionViewState) -> SessionNavigatorSectionViewState? {
        switch selectedSidebarMode {
        case .chat:
            switch section.id {
            case "workspace", "active-jobs":
                return nil
            case "plain":
                return section.items.isEmpty ? nil : section
            case "recent", "pinned", "interrupted", "archived":
                return filteredNavigatorSection(section, includePlainSessions: true)
            default:
                return section
            }
        case .code:
            switch section.id {
            case "plain":
                return nil
            case "recent", "pinned", "interrupted", "archived":
                return filteredNavigatorSection(section, includePlainSessions: false)
            default:
                return section
            }
        }
    }

    private func filteredNavigatorSection(
        _ section: SessionNavigatorSectionViewState,
        includePlainSessions: Bool
    ) -> SessionNavigatorSectionViewState? {
        var copy = section
        copy.items = section.items.filter { item in
            guard item.kind == .session else { return true }
            let isPlain = item.id.hasPrefix("plain-")
            return includePlainSessions ? isPlain : !isPlain
        }
        return copy.items.isEmpty ? nil : copy
    }

    private var promptSuggestions: [PromptSuggestionViewState] {
        var suggestions = PromptSuggestionModel.defaults
        if let selectedFilePath = state.selectedFilePath, !selectedFilePath.isEmpty {
            suggestions.insert(
                .init(
                    id: "selected-file",
                    kind: .file,
                    title: "@file:\(URL(fileURLWithPath: selectedFilePath).lastPathComponent)",
                    insertionText: "@file:\(selectedFilePath)",
                    detail: "Selected file"),
                at: 0)
        }
        for agent in agentSwitcherItems where agent.isEnabled {
            suggestions.append(.init(
                id: "agent-\(agent.id)",
                kind: .agent,
                title: "@agent:\(agent.title)",
                insertionText: "@agent:\(agent.id)",
                detail: agent.subtitle.isEmpty ? nil : agent.subtitle))
        }
        return suggestions
    }

    private var agentSwitcherItems: [AgentSwitcherItemViewState] {
        if !state.agentSwitcherItems.isEmpty {
            return state.agentSwitcherItems
        }
        return [
            AgentSwitcherItemViewState(id: "general", title: "General", subtitle: "Default local agent"),
            AgentSwitcherItemViewState(id: "plan", title: "Plan", subtitle: "Configured agent required", isEnabled: false),
            AgentSwitcherItemViewState(id: "build", title: "Build", subtitle: "Configured agent required", isEnabled: false),
        ]
    }

    private var selectedAgentTitle: String {
        let selectedID = state.selectedAgentID ?? agentSwitcherItems.first?.id
        return agentSwitcherItems.first { $0.id == selectedID }?.title ?? "General"
    }

    private var changedFileSummary: String? {
        guard !state.diffFiles.isEmpty else { return nil }
        let additions = state.diffFiles.reduce(0) { $0 + $1.additions }
        let deletions = state.diffFiles.reduce(0) { $0 + $1.deletions }
        return "\(state.diffFiles.count) files changed in workspace +\(additions) -\(deletions)"
    }

    @MainActor
    private func selectNavigatorItem(_ item: SessionNavigatorItemViewState) {
        switch item.kind {
        case .session:
            if item.id.hasPrefix("plain-") {
                selectedSidebarMode = .chat
            } else {
                selectedSidebarMode = .code
            }
            if item.isDraft {
                actions.startNewChat(selectedSidebarMode == .chat)
            } else if let sessionID = item.sessionID {
                actions.selectChatThread(sessionID)
            }
            actions.focusChat()
        case .job:
            selectedInspectorTab = .jobs
            isInspectorVisible = true
        case .project:
            actions.openWorkspace()
        case .placeholder:
            break
        }
    }

    private var projectFolderName: String {
        guard let workspacePath = state.workspacePath, !workspacePath.isEmpty else { return "No workspace" }
        let name = URL(fileURLWithPath: workspacePath).lastPathComponent
        return name.isEmpty ? workspacePath : name
    }

    private var bottomChrome: some View {
        HStack(alignment: .bottom) {
            HStack(spacing: .space2) {
                settingsButton
            }
            .padding(.horizontal, .space2)
            .padding(.vertical, .space1)
            .background(Color.primary.opacity(0.04), in: Capsule())

            Spacer(minLength: .space4)
        }
        .padding(.leading, 20)
        .padding(.trailing, .space3)
        .padding(.bottom, .space3)
        .allowsHitTesting(true)
    }

    @ViewBuilder
    private var noticeOverlay: some View {
        if !state.notices.isEmpty {
            noticeStack
                .padding(.top, topBarHeight + .space2)
        }
    }

    @ViewBuilder
    private var settingsOverlay: some View {
        if isSettingsPresented {
            GeometryReader { geometry in
                ZStack {
                    Color.black.opacity(0.42)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { isSettingsPresented = false }

                    VStack(spacing: 0) {
                        HStack {
                            Text("Settings")
                                .font(.titleS)
                                .foregroundStyle(Theme.C.textPrimary)
                            Spacer()
                            Button {
                                isSettingsPresented = false
                            } label: {
                                Image(systemName: "xmark")
                            }
                            .buttonStyle(.plain)
                            .keyboardShortcut(.cancelAction)
                            .help("Close Settings")
                        }
                        .padding(.horizontal, .space4)
                        .padding(.vertical, .space3)
                        Divider()
                        SettingsHubView(
                            settings: $settings,
                            state: state,
                            onLoadModels: actions.loadModels,
                            onUnloadModels: actions.unloadModels,
                            onCancelModelLoad: actions.cancelModelLoad,
                            onDismissOnboarding: actions.dismissModelOnboarding,
                            onApplyRecommendations: actions.applyRecommendedModels,
                            onSaveHuggingFaceToken: actions.saveHuggingFaceToken,
                            onDeleteHuggingFaceToken: actions.deleteHuggingFaceToken,
                            onOpenHealth: actions.openHealth,
                            onExportDiagnostics: actions.exportDiagnostics,
                            onUpdateModelContextSettings: actions.setModelContextSettings)
                    }
                    .frame(
                        width: min(1180, max(680, geometry.size.width - 96)),
                        height: min(720, max(520, geometry.size.height - 96)))
                    .background(Theme.C.surface, in: RoundedRectangle(cornerRadius: .radius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: .radius, style: .continuous)
                            .stroke(Theme.C.border, lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.30), radius: 32, y: 12)
                    .transition(.scale(scale: 0.98).combined(with: .opacity))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
    }

    @ViewBuilder
    private var healthOverlay: some View {
        if isHealthPresented {
            GeometryReader { geometry in
                ZStack {
                    Color.black.opacity(0.42)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { isHealthPresented = false }

                    VStack(spacing: 0) {
                        HStack {
                            Text("Health")
                                .font(.titleS)
                                .foregroundStyle(Theme.C.textPrimary)
                            Spacer()
                            Button {
                                isHealthPresented = false
                            } label: {
                                Image(systemName: "xmark")
                            }
                            .buttonStyle(.plain)
                            .keyboardShortcut(.cancelAction)
                            .help("Close Health")
                        }
                        .padding(.horizontal, .space4)
                        .padding(.vertical, .space3)
                        Divider()
                        HealthStatusView(
                            state: state.health,
                            onRetryRecovery: actions.retryRecoveryAction,
                            onDismissRecovery: actions.dismissRecoveryItem,
                            onClearRecovery: actions.clearRecoveryJournal,
                            onExportDiagnostics: actions.exportDiagnostics)
                    }
                    .frame(
                        width: min(980, max(680, geometry.size.width - 96)),
                        height: min(720, max(520, geometry.size.height - 96)))
                    .background(Theme.C.surface, in: RoundedRectangle(cornerRadius: .radius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: .radius, style: .continuous)
                            .stroke(Theme.C.border, lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.30), radius: 32, y: 12)
                    .transition(.scale(scale: 0.98).combined(with: .opacity))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
    }

    // ⌘K: a hidden button hosts the shortcut so it works whenever the workspace
    // is on screen, without adding a global menu item.
    private var commandPaletteHotkey: some View {
        Button("Command Palette") {
            isCommandPalettePresented.toggle()
        }
        .keyboardShortcut("k", modifiers: [.command])
        .opacity(0)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var commandPaletteOverlay: some View {
        if isCommandPalettePresented {
            CommandPaletteView(isPresented: $isCommandPalettePresented, items: commandPaletteItems)
                .transition(.opacity)
        }
    }

    private var commandPaletteItems: [CommandPaletteItem] {
        paletteActionItems + paletteSessionItems + paletteFileItems + paletteModelItems
    }

    private var paletteActionItems: [CommandPaletteItem] {
        [
            CommandPaletteItem(id: "act.newPlainChat", group: .action, title: "New chat", symbol: "square.and.pencil") {
                selectedSidebarMode = .chat
                actions.startNewChat(true)
            },
            CommandPaletteItem(id: "act.newWorkspaceChat", group: .action, title: "New workspace chat", symbol: "square.and.pencil") {
                selectedSidebarMode = .code
                actions.startNewChat(false)
            },
            CommandPaletteItem(id: "act.toggleSidebar", group: .action, title: "Toggle sidebar", subtitle: "⌃⌘S", symbol: "sidebar.left") {
                columnVisibility = (columnVisibility == .detailOnly) ? .all : .detailOnly
            },
            CommandPaletteItem(id: "act.toggleInspector", group: .action, title: "Toggle inspector", symbol: "sidebar.right") {
                selectedSidebarMode = .code
                isInspectorVisible.toggle()
            },
            CommandPaletteItem(id: "act.chatMode", group: .action, title: "Switch to Chat mode", symbol: "bubble.left", isActive: selectedSidebarMode == .chat) {
                selectedSidebarMode = .chat
                actions.setPlainChatMode(true)
            },
            CommandPaletteItem(id: "act.codeMode", group: .action, title: "Switch to Code mode", symbol: "chevron.left.forwardslash.chevron.right", isActive: selectedSidebarMode == .code) {
                selectedSidebarMode = .code
                actions.setPlainChatMode(false)
            },
            CommandPaletteItem(id: "act.focusSearch", group: .action, title: "Search files", symbol: "magnifyingglass") {
                selectedSidebarMode = .code
                selectedInspectorTab = .files
                isInspectorVisible = true
                actions.focusSearch()
            },
            CommandPaletteItem(id: "act.openWorkspace", group: .action, title: "Open workspace…", subtitle: "⌘O", symbol: "folder.badge.plus", run: actions.openWorkspace),
            CommandPaletteItem(id: "act.reindex", group: .action, title: "Reindex workspace", symbol: "arrow.clockwise", run: actions.reindex),
            CommandPaletteItem(id: "act.refreshGit", group: .action, title: "Refresh Git", symbol: "arrow.triangle.2.circlepath", run: actions.refreshGit),
            CommandPaletteItem(id: "act.reviewDiff", group: .action, title: "Review current diff", symbol: "plus.forwardslash.minus", run: actions.loadCurrentDiffForReview),
            CommandPaletteItem(id: "act.cancelChat", group: .action, title: "Cancel active chat", subtitle: "⌘.", symbol: "stop.fill", run: actions.cancelChat),
            CommandPaletteItem(id: "act.settings", group: .action, title: "Open settings", subtitle: "⌘,", symbol: "gearshape") {
                isSettingsPresented = true
            },
            CommandPaletteItem(id: "act.health", group: .action, title: "Open health", symbol: "waveform.path.ecg", run: actions.openHealth),
        ]
    }

    private var paletteSessionItems: [CommandPaletteItem] {
        sessionNavigatorSections
            .flatMap(\.items)
            .filter { $0.kind == .session && !$0.isDraft }
            .compactMap { item in
                guard let sessionID = item.sessionID else { return nil }
                return CommandPaletteItem(
                    id: "session.\(item.id)",
                    group: .session,
                    title: item.title,
                    subtitle: item.subtitle,
                    symbol: "bubble.left.and.bubble.right",
                    isActive: item.isSelected) {
                        if item.id.hasPrefix("plain-") {
                            selectedSidebarMode = .chat
                        } else {
                            selectedSidebarMode = .code
                        }
                        actions.selectChatThread(sessionID)
                        actions.focusChat()
                    }
            }
    }

    private var paletteFileItems: [CommandPaletteItem] {
        WorkspaceView.flattenFiles(state.fileTree)
            .prefix(2000)
            .map { path in
                CommandPaletteItem(
                    id: "file.\(path)",
                    group: .file,
                    title: URL(fileURLWithPath: path).lastPathComponent,
                    subtitle: path,
                    symbol: "doc.text") {
                        selectedSidebarMode = .code
                        actions.selectFile(path)
                    }
            }
    }

    private var paletteModelItems: [CommandPaletteItem] {
        availableModels.map { id in
            CommandPaletteItem(
                id: "model.\(id)",
                group: .model,
                title: URL(fileURLWithPath: id).lastPathComponent,
                subtitle: id,
                symbol: "cpu",
                isActive: id == selectedChatModelName) {
                    selectAndLoadChatModel(id)
                }
        }
    }

    /// Depth-first flatten of the file tree to leaf file paths (directories skipped).
    private static func flattenFiles(_ nodes: [FileTreeNode]) -> [String] {
        var out: [String] = []
        for node in nodes {
            if node.isDirectory {
                out.append(contentsOf: flattenFiles(node.children))
            } else {
                out.append(node.path)
            }
        }
        return out
    }

    private var noticeStack: some View {
        VStack(spacing: 6) {
            ForEach(state.notices.prefix(2)) { notice in
                HStack(spacing: .space2) {
                    Image(systemName: symbol(for: notice.severity))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(notice.title)
                            .font(.bodyS.weight(.semibold))
                        Text(notice.message)
                            .font(.metaMono)
                            .foregroundStyle(Theme.C.textSecondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Button {
                        actions.dismissNotice(notice.id)
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, .space3)
                .padding(.vertical, .space2)
                .overlaySurface(radius: .radiusSm)
                .padding(.horizontal)
            }
            if state.notices.count > 2 {
                Text("+\(state.notices.count - 2) more")
                    .font(.metaMono)
                    .foregroundStyle(Theme.C.textSecondary)
            }
        }
        .padding(.top, 6)
    }

    // Background jobs only (indexing / model load). Chat progress is shown in the
    // chat stream, so the strip no longer duplicates a "thinking" spinner.
    private var backgroundActivities: [WorkspaceActivity] {
        state.activities.filter { activity in
            activity.kind != .chat && activity.kind != .modelLoading
        }
    }

    private var activityStrip: some View {
        HStack(spacing: 10) {
            ForEach(backgroundActivities) { activity in
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(activity.title)
                        .font(.metaMono)
                    if activity.canCancel {
                        Button("Cancel") {
                            switch activity.kind {
                            case .modelLoading:
                                actions.cancelModelLoad()
                            default:
                                actions.reindex()
                            }
                        }
                        .font(.metaMono)
                    }
                }
                .padding(.horizontal, .space2)
                .padding(.vertical, .space1)
                .background(Theme.C.surface3, in: Capsule())
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, backgroundActivities.isEmpty ? 0 : 6)
    }

    private func symbol(for severity: AppNoticeSeverity) -> String {
        switch severity {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.octagon"
        }
    }
}
