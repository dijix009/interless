import Foundation
import Observation
import Agents
import Core
import InterlessSecurity
import Persistence
import Shared
import Tooling
import UI
import Workspace

private struct MessageGenerationStats {
    var startedAt = Date()
    var streamedTokenCount = 0
}

@MainActor
@Observable
public final class WorkspaceSessionModel {
    public private(set) var workspaceURL: URL?
    public private(set) var indexingProgress: IndexingProgress?
    public private(set) var fileTree: [FileTreeNode] = []
    public private(set) var selectedFilePath: String?
    public private(set) var selectedFileText = ""
    public private(set) var selectedFilePreview: FilePreviewViewState = .empty
    public var fileTreeFilter = ""
    public private(set) var expandedFileTreePaths: Set<String>
    public var searchQuery = ""
    public private(set) var searchHits: [SearchHit] = []
    public private(set) var gitStatus: GitStatus = .notARepository
    public private(set) var diffLines: [DiffLine] = []
    public private(set) var diffFiles: [DiffFile] = []
    public private(set) var chatMessages: [ChatMessageViewState] = []
    public private(set) var chatThreads: [ChatThreadViewState] = []
    public private(set) var globalChatThreads: [ChatThreadViewState] = []
    public private(set) var modelStatus: ModelLoadStatus = .idle
    public private(set) var modelDownloadProgress: ModelDownloadProgressViewState?
    public private(set) var availableChatModelIDs: [String]
    public private(set) var notices: [AppNotice] = []
    public private(set) var activities: [WorkspaceActivity] = []
    public private(set) var focusTarget: WorkspaceFocusTarget = .none
    public private(set) var patchProposal: PatchProposal?
    public var isPatchReviewPresented = false
    public private(set) var modelOnboarding: ModelOnboardingViewState
    public var layout: WorkspaceLayoutPreferences {
        didSet { preferences.layoutPreferences = layout }
    }
    public var chatDraft = ""
    public var isSettingsPresented = false
    public var isHealthPresented = false
    public private(set) var healthState = HealthStatusViewState()
    public private(set) var lastDiagnosticsExport: DiagnosticsExportViewState?
    public private(set) var configStatus = ConfigStatusViewState()
    public private(set) var permissionPrompt: PermissionPromptViewState?
    public private(set) var questionPrompt: QuestionPromptViewState?
    public private(set) var todoPanel = TodoPanelViewState()
    public private(set) var backgroundToolJobs: [BackgroundToolJobViewState] = []
    public private(set) var sessionTimelineItems: [SessionTimelineItemViewState] = []
    public private(set) var selectedReasoningEffort: ReasoningEffort = .none
    public private(set) var modelContextSettings: ModelContextSettingsViewState {
        didSet { preferences.modelContextSettings = modelContextSettings.normalized() }
    }
    public var settings: ModelSettingsViewState {
        didSet {
            preferences.modelSettings = settings
            clampReasoningEffortForCurrentModel()
        }
    }

    private let preferences: AppPreferences
    private let factory: any AppDependencyFactory
    private let eventBus: EventBus
    private let taskScheduler: TaskScheduler
    private let metricsRecorder: MetricsRecorder
    private let metricKitBridge: MetricKitBridge
    private let recoveryJournal: RecoveryJournal
    private let appStore: (any AppStore)?
    private let sessionStore: (any SessionRuntimeStore)?
    private let secretStore: any SecretStore
    private let configCoordinator: ConfigCoordinator
    private let contextEpochStore = ContextEpochStore()
    private var environment: WorkspaceEnvironment?
    private var chatOnlyEnvironment: WorkspaceEnvironment?
    private var loadedWorkspaceConfig: LoadedInterlessConfig?
    private var currentConversationID: UUID?
    private var currentConversationMode: ConversationMode?
    private var currentConversationWorkspacePath: String?
    private var visibleConversationMode: ConversationMode = .code
    @ObservationIgnored private var reindexTask: Task<Void, Never>?
    @ObservationIgnored private var watchTask: Task<Void, Never>?
    @ObservationIgnored private var configWatchTask: Task<Void, Never>?
    @ObservationIgnored private var chatTask: Task<Void, Never>?
    @ObservationIgnored private var modelLoadTask: Task<Void, Error>?
    @ObservationIgnored private var activeModelLoadID: UUID?
    @ObservationIgnored private var cancelledModelLoadIDs: Set<UUID> = []
    @ObservationIgnored private var generationStats: [UUID: MessageGenerationStats] = [:]
    @ObservationIgnored private var codeRunFileChanges: [UUID: [ToolFileChange]] = [:]
    @ObservationIgnored private var codeRunPrompts: [UUID: String] = [:]
    /// Per-assistant buffered streamed text, applied to the transcript in coalesced
    /// flushes (~every `tokenFlushThresholdCharacters`) instead of once per token,
    /// to cut MainActor publishes / viewState rebuilds during streaming.
    @ObservationIgnored private var pendingStreamedText: [UUID: String] = [:]
    /// Memoized context-usage meter. Stable during token streaming (the streaming
    /// message is excluded from the estimate), so this avoids the O(transcript)
    /// scan on every streamed chunk; recomputed only when the signature changes.
    @ObservationIgnored private var contextUsageCache: (signature: Int, value: (label: String, fraction: Double))?
    /// Memoized file-tree derivations: `viewState` previously re-walked the whole
    /// tree twice (filter + visible rows, up to ~20k nodes) on every rebuild —
    /// i.e. on every coalesced token flush. Invalidated by tree version/filter/
    /// expansion changes only.
    @ObservationIgnored private var fileTreeVersion = 0
    @ObservationIgnored private var treeDerivationCache:
        (version: Int, filter: String, expanded: Set<String>, filtered: [FileTreeNode], rows: [FileTreeVisibleRow])?
    private static let tokenFlushThresholdCharacters = 32
    @ObservationIgnored private var permissionContinuations: [UUID: CheckedContinuation<ToolPermissionResolution, Never>] = [:]
    @ObservationIgnored private var questionContinuations: [UUID: CheckedContinuation<ToolQuestionResponse, Error>] = [:]
    @ObservationIgnored private var didAttemptRestore = false

    public init(
        preferences: AppPreferences = AppPreferences(),
        factory: any AppDependencyFactory = LiveAppDependencyFactory(),
        eventBus: EventBus = EventBus(),
        taskScheduler: TaskScheduler = TaskScheduler(),
        metricsRecorder: MetricsRecorder = MetricsRecorder(),
        recoveryJournal: RecoveryJournal = RecoveryJournal.live(),
        appStore: (any AppStore)? = nil,
        sessionStore: (any SessionRuntimeStore)? = nil,
        configStore: (any ConfigStore)? = nil,
        secretStore: any SecretStore = KeychainSecretStore()
    ) {
        self.preferences = preferences
        self.factory = factory
        self.eventBus = eventBus
        self.taskScheduler = taskScheduler
        self.metricsRecorder = metricsRecorder
        self.metricKitBridge = MetricKitBridge(recorder: metricsRecorder)
        self.recoveryJournal = recoveryJournal
        self.appStore = appStore
        self.sessionStore = sessionStore
        self.secretStore = secretStore
        self.configCoordinator = ConfigCoordinator(configStore: configStore, secretStore: secretStore)
        let initialSettings = preferences.modelSettings
        self.settings = initialSettings
        self.modelContextSettings = preferences.modelContextSettings
        self.selectedReasoningEffort = ReasoningEffort.resolved(
            preferences.reasoningEffort,
            for: initialSettings.orchestratorModelID)
        self.searchQuery = preferences.lastSearchQuery
        self.layout = preferences.layoutPreferences
        self.expandedFileTreePaths = preferences.expandedFileTreePaths
        self.modelOnboarding = ModelOnboardingViewState(isDismissed: preferences.isModelOnboardingDismissed)
        self.availableChatModelIDs = Self.discoverLocalModelIDs()
        if let path = preferences.lastWorkspacePath {
            self.workspaceURL = URL(fileURLWithPath: path)
        }
        metricKitBridge.start()
    }

    deinit {
        reindexTask?.cancel()
        watchTask?.cancel()
        configWatchTask?.cancel()
        chatTask?.cancel()
        modelLoadTask?.cancel()
        metricKitBridge.stop()
    }

    public var viewState: WorkspaceViewState {
        WorkspaceViewState(
            chrome: workspaceChrome,
            workspacePath: workspaceURL?.path,
            indexingSummary: indexingSummary,
            fileTree: fileTreeDerivations().filtered,
            fileTreeFilter: fileTreeFilter,
            selectedFilePath: selectedFilePath,
            selectedFileText: selectedFileText,
            selectedFilePreview: selectedFilePreview,
            searchHits: searchHits,
            gitSummary: gitSummary,
            diffLines: diffLines,
            diffFiles: diffFiles,
            chatMessages: chatMessages,
            chatThreads: chatThreads,
            globalChatThreads: globalChatThreads,
            modelStatus: modelStatus,
            modelDownloadProgress: modelDownloadProgress,
            isIndexing: indexingProgress.map { ![.completed, .cancelled, .failed].contains($0.phase) } ?? false,
            notices: notices,
            activities: activities,
            focusTarget: focusTarget,
            layout: layout,
            patchProposal: patchProposal,
            isPatchReviewPresented: isPatchReviewPresented,
            fileTreeRows: fileTreeDerivations().rows,
            expandedFileTreePaths: expandedFileTreePaths,
            modelOnboarding: modelOnboarding,
            availableChatModelIDs: availableChatModelIDs,
            health: healthState,
            configStatus: configStatus,
            effectiveSettings: effectiveRuntimeSettings,
            isHealthPresented: isHealthPresented,
            permissionPrompt: permissionPrompt,
            questionPrompt: questionPrompt,
            todoPanel: todoPanel,
            backgroundToolJobs: backgroundToolJobs,
            sessionTimelineItems: sessionTimelineItems,
            selectedReasoningEffort: selectedReasoningEffort,
            reasoningOptions: reasoningOptionsForCurrentModel,
            modelContextSettings: modelContextSettings)
    }

    private var workspaceChrome: WorkspaceChromeViewState {
        let usage = estimatedContextWindowUsage()
        return WorkspaceChromeViewState(
            contextUsageLabel: usage.label,
            contextUsageFraction: usage.fraction)
    }

    private var reasoningOptionsForCurrentModel: [ReasoningOptionViewState] {
        ReasoningOptionViewState.options(
            for: settings.orchestratorModelID,
            selected: selectedReasoningEffort)
    }

    public func setReasoningEffort(_ effort: ReasoningEffort) {
        let resolved = ReasoningEffort.resolved(effort, for: settings.orchestratorModelID)
        selectedReasoningEffort = resolved
        preferences.reasoningEffort = resolved
    }

    public func setModelContextSettings(_ newValue: ModelContextSettingsViewState) {
        modelContextSettings = newValue.normalized()
    }

    private func clampReasoningEffortForCurrentModel() {
        let resolved = ReasoningEffort.resolved(selectedReasoningEffort, for: settings.orchestratorModelID)
        guard resolved != selectedReasoningEffort else { return }
        selectedReasoningEffort = resolved
        preferences.reasoningEffort = resolved
    }

    public func openWorkspace(_ url: URL) async {
        await publish(.init(kind: .workspace, message: "Opening workspace", metadata: ["path": url.path]))
        let recovery = await beginRecovery(.workspaceOpen, title: "Open workspace", metadata: ["workspacePath": url.path])
        let start = ContinuousClock.now
        let opened = await openWorkspace(url, restoreSavedState: false)
        await recordDuration(.indexingDuration, start: start, metadata: ["operation": "openWorkspace"])
        await finishRecovery(
            recovery,
            status: opened ? .completed : .failed,
            message: opened ? nil : "Failed to open workspace")
    }

    public func restoreLastWorkspaceIfNeeded() async {
        guard !didAttemptRestore else { return }
        didAttemptRestore = true
        guard preferences.restoreLastWorkspaceOnLaunch, let path = preferences.lastWorkspacePath else { return }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            appendNotice(
                severity: .warning,
                title: "Workspace not restored",
                message: "The last workspace no longer exists: \(path)")
            return
        }
        await publish(.init(kind: .workspace, message: "Restoring workspace", metadata: ["path": path]))
        _ = await openWorkspace(URL(fileURLWithPath: path), restoreSavedState: true)
    }

    public func loadRecoveryJournalOnLaunch() async {
        do {
            let items = try await recoveryJournal.recoverUnfinishedOperations()
            let snapshot = try await recoveryJournal.snapshot(limit: 80)
            if !items.isEmpty {
                appendNotice(
                    severity: .warning,
                    title: "Recovery available",
                    message: "\(items.count) unfinished operations from a previous run are available in Health.")
            }
            if let archive = snapshot.corruptionArchiveURL {
                appendNotice(
                    severity: .warning,
                    title: "Recovery journal reset",
                    message: "A corrupted recovery journal was archived at \(archive.lastPathComponent).")
                await recordFailure(kind: .failure, message: "Recovery journal was corrupted and reset.")
            }
            await refreshHealthStatus()
        } catch {
            appendNotice(severity: .warning, title: "Recovery unavailable", message: String(describing: error))
        }
    }

    public func loadPersistedHistoryOnLaunch() async {
        await restoreModelAssignmentsFromAppStore()
        guard settings.persistPromptHistory, chatMessages.isEmpty, let sessionStore else { return }
        do {
            let globalSessions = try await recentPlainSessions(limit: 12)
            refreshGlobalChatThreads(from: globalSessions)
            let sessions: [SessionRecord]
            if let workspacePath = workspaceURL?.path {
                sessions = try await sessionStore.recentSessions(limit: 12, workspacePath: workspacePath)
            } else {
                sessions = []
            }
            refreshChatThreads(from: sessions)
            guard let session = sessions.first else { return }
            await loadSession(session)
            refreshChatThreads(from: sessions)
            refreshGlobalChatThreads(from: globalSessions)
        } catch {
            appendNotice(severity: .warning, title: "History unavailable", message: String(describing: error))
            await recordFailure(kind: .failure, message: "Failed to restore local history.")
        }
    }

    public func saveHuggingFaceToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task {
            do {
                try await secretStore.save(
                    trimmed,
                    service: InterlessSecrets.service,
                    account: InterlessSecrets.huggingFaceTokenAccount)
                appendNotice(severity: .info, title: "Token saved", message: "Hugging Face token was saved in Keychain.")
                await publish(.init(kind: .model, message: "Saved model access token", metadata: ["store": "keychain"]))
            } catch {
                appendNotice(severity: .error, title: "Token save failed", message: String(describing: error))
                await recordFailure(kind: .model, message: "Failed to save model access token.")
            }
        }
    }

    public func deleteHuggingFaceToken() {
        Task {
            do {
                try await secretStore.delete(
                    service: InterlessSecrets.service,
                    account: InterlessSecrets.huggingFaceTokenAccount)
                appendNotice(severity: .info, title: "Token deleted", message: "Hugging Face token was removed from Keychain.")
                await publish(.init(kind: .model, message: "Deleted model access token", metadata: ["store": "keychain"]))
            } catch {
                appendNotice(severity: .error, title: "Token delete failed", message: String(describing: error))
                await recordFailure(kind: .model, message: "Failed to delete model access token.")
            }
        }
    }

    public func clearPersistedHistory() {
        Task {
            do {
                if let sessionStore {
                    let workspaceSessions: [SessionRecord]
                    if let workspacePath = workspaceURL?.path {
                        workspaceSessions = try await sessionStore.recentSessions(limit: 500, workspacePath: workspacePath)
                    } else {
                        workspaceSessions = []
                    }
                    let plainSessions = try await recentPlainSessions(limit: 500)
                    for session in workspaceSessions + plainSessions {
                        try await sessionStore.deleteSession(id: session.id)
                    }
                }
                currentConversationID = nil
                chatMessages.removeAll()
                chatThreads.removeAll()
                globalChatThreads.removeAll()
                todoPanel = TodoPanelViewState()
                sessionTimelineItems = []
                appendNotice(severity: .info, title: "History cleared", message: "Local chat and prompt history was cleared.")
                await publish(.init(kind: .chat, message: "Cleared local chat history"))
            } catch {
                appendNotice(severity: .error, title: "History clear failed", message: String(describing: error))
                await recordFailure(kind: .chat, message: "Failed to clear local history.")
            }
        }
    }

    public func dismissNotice(_ id: UUID) {
        notices.removeAll { $0.id == id }
    }

    public func selectSearchHit(_ hit: SearchHit) async {
        await selectFile(hit.relativePath)
    }

    public func clearFocusTarget() {
        focusTarget = .none
    }

    public func toggleFileTreeDirectory(_ path: String) {
        if expandedFileTreePaths.contains(path) {
            expandedFileTreePaths.remove(path)
        } else {
            expandedFileTreePaths.insert(path)
        }
        preferences.expandedFileTreePaths = expandedFileTreePaths
    }

    public func dismissModelOnboarding() {
        modelOnboarding.isDismissed = true
        preferences.isModelOnboardingDismissed = true
    }

    public func applyRecommendedModels() {
        if settings.usesSingleAgentMode() {
            let localModel = availableChatModelIDs.first
            let fallback = modelOnboarding.recommendations.first(where: { $0.role == .utility })
            let selected = localModel ?? fallback?.modelID ?? ""
            settings.orchestratorModelID = selected
            settings.orchestratorQuantization = Self.quantizationAdvertised(by: selected) ?? fallback?.quantization ?? .q4
            settings.utilityModelID = ""
            settings.embeddingsModelID = ""
            return
        }
        for recommendation in modelOnboarding.recommendations {
            switch recommendation.role {
            case .orchestrator:
                settings.orchestratorModelID = recommendation.modelID
                settings.orchestratorQuantization = recommendation.quantization
            case .utility:
                settings.utilityModelID = recommendation.modelID
                settings.utilityQuantization = recommendation.quantization
            case .embeddings:
                settings.embeddingsModelID = recommendation.modelID
                settings.embeddingsQuantization = recommendation.quantization
            }
        }
    }

    public func loadPatchProposal(_ diff: String, title: String = "Patch Proposal") {
        patchProposal = PatchReviewCoordinator.parseUnifiedDiff(diff, title: title)
        isPatchReviewPresented = true
        Task { await publish(.init(kind: .patch, message: "Loaded patch proposal", metadata: ["title": title])) }
    }

    public func loadCurrentDiffForReview() async {
        guard let environment else {
            appendNotice(severity: .warning, title: "No workspace", message: "Open a workspace before reviewing patches.")
            return
        }
        do {
            let diff = try await environment.gitDiff(nil)
            let trimmed = diff.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                appendNotice(severity: .info, title: "No diff", message: "There are no working tree changes to review.")
                return
            }
            loadPatchProposal(diff, title: "Working Tree Diff")
        } catch {
            appendNotice(severity: .error, title: "Patch review failed", message: String(describing: error))
        }
    }

    public func revertSnapshot(_ snapshotID: String) async {
        guard let environment else {
            appendNotice(severity: .warning, title: "No workspace", message: "Open a workspace before reverting changes.")
            return
        }
        do {
            let result = try await environment.revertSnapshot(snapshotID)
            await refreshGit()
            await reloadFileTree()
            appendNotice(
                severity: .info,
                title: "Changes reverted",
                message: "Restored \(result.restoredPaths.count) and removed \(result.removedPaths.count) path(s).")
            await publish(.init(kind: .patch, message: "Snapshot reverted", metadata: [
                "snapshotID": snapshotID,
                "restored": "\(result.restoredPaths.count)",
                "removed": "\(result.removedPaths.count)",
            ]))
        } catch {
            appendNotice(severity: .error, title: "Revert failed", message: String(describing: error))
            await recordFailure(kind: .patch, message: "Snapshot revert failed: \(error)")
        }
    }

    public func setPatchHunkAccepted(fileID: String, hunkID: Int, isAccepted: Bool) {
        patchProposal?.setHunkAccepted(fileID: fileID, hunkID: hunkID, isAccepted: isAccepted)
    }

    public func applyAcceptedPatch() async {
        guard let environment, let proposal = patchProposal, let root = workspaceURL else {
            appendNotice(severity: .warning, title: "No patch", message: "Load a patch proposal before applying.")
            return
        }
        if let reason = PatchReviewModel.disabledApplyReason(proposal: proposal, writesAllowed: settings.allowWrites) {
            appendNotice(severity: .warning, title: "Patch not applied", message: reason)
            await recordFailure(kind: .patch, message: reason)
            return
        }
        await publish(.init(kind: .patch, message: "Applying accepted patch"))
        let start = ContinuousClock.now
        let taskID = await taskScheduler.begin(kind: "patch", title: "Apply accepted patch", priority: .userInitiated)
        let recovery = await beginRecovery(.patchApply, title: "Apply accepted patch", metadata: workspaceRecoveryMetadata())
        setActivity(.init(kind: .patchApply, title: "Applying patch"))
        defer { removeActivity(.patchApply) }
        do {
            let budget = ResourceBudget.resolved(for: settings.resourceProfile)
            let coordinator = PatchReviewCoordinator(
                root: root,
                allowsWrites: settings.allowWrites,
                maxTargetFileBytes: budget.maxIndexedFileSizeBytes,
                snapshotStore: WorkspaceSnapshotStore(
                    root: root,
                    maxEntryBytes: budget.maxIndexedFileSizeBytes))
            let result = try await coordinator.apply(proposal)
            let snapshotSummary = result.snapshotID.map { " Snapshot \($0.uuidString.prefix(8)) was saved." } ?? ""
            appendNotice(
                severity: .info,
                title: "Patch applied",
                message: "\(result.hunksApplied) hunks applied across \(result.filesChanged) files.\(snapshotSummary)")
            patchProposal = nil
            isPatchReviewPresented = false
            await refreshGit()
            if let selectedFilePath {
                await selectFile(selectedFilePath)
            }
            await recordDuration(.patchApplyDuration, start: start)
            await taskScheduler.finish(id: taskID, status: .completed)
            await finishRecovery(recovery, status: .completed)
            var metadata = ["hunks": "\(result.hunksApplied)", "files": "\(result.filesChanged)"]
            if let snapshotID = result.snapshotID {
                metadata["snapshotID"] = snapshotID.uuidString
            }
            await publish(.init(kind: .patch, message: "Patch apply completed", metadata: metadata))
            _ = environment
        } catch {
            appendNotice(severity: .error, title: "Patch apply failed", message: String(describing: error))
            await taskScheduler.finish(id: taskID, status: .failed, message: String(describing: error))
            await finishRecovery(recovery, status: .failed, message: String(describing: error))
            await recordFailure(kind: .patch, message: String(describing: error))
        }
    }

    public func discardPatchProposal() {
        patchProposal = nil
        isPatchReviewPresented = false
    }

    public func dismissRecoveryItem(_ id: UUID) {
        Task {
            try? await recoveryJournal.acknowledge(id)
            await refreshHealthStatus()
        }
    }

    public func retryRecoveryAction(_ id: UUID) {
        guard let item = healthState.recoveryItems.first(where: { $0.id == id }) else { return }
        switch item.action.kind {
        case .retryWorkspaceOpen:
            guard let path = item.workspacePath else { return }
            Task { await openWorkspace(URL(fileURLWithPath: path)) }
        case .retryIndexing:
            Task { await startFullReindex() }
        case .retrySearch:
            Task { await search() }
        case .retryFilePreview:
            guard let path = item.relativePath else { return }
            Task { await selectFile(path) }
        case .retryGitRefresh:
            Task { await refreshGit() }
        case .retryModelLoad:
            Task { await loadModels() }
        case .reviewPatch:
            Task { await loadCurrentDiffForReview() }
        case .openHealth:
            isHealthPresented = true
        case .dismiss:
            dismissRecoveryItem(id)
        }
    }

    public func clearRecoveryJournal() {
        Task {
            try? await recoveryJournal.clearAcknowledged()
            await refreshHealthStatus()
        }
    }

    public func refreshHealthStatus() async {
        let events = await eventBus.recentEvents(limit: 60)
        let snapshot = await taskScheduler.snapshot()
        let summaries = await metricsRecorder.summaries()
        let recoverySnapshot = try? await recoveryJournal.snapshot(limit: 80)
        let memoryPolicy = await environment?.memoryPolicy()
        let memoryMetric = summaries.first { $0.kind == .memoryFootprint }
        let durableEventCursors = await durableEventCursorStates()
        healthState = HealthStatusViewState(
            activeTasks: snapshot.active.map(Self.healthTask),
            recentTasks: snapshot.recent.suffix(30).map(Self.healthTask),
            recentEvents: events.map(Self.healthEvent),
            metricSummaries: summaries.map(Self.healthMetric),
            memorySummary: memoryMetric.map { "Memory latest \(HealthFormatting.format($0.latest, unit: $0.unit.rawValue))" } ?? "No memory snapshots recorded",
            memoryPolicy: memoryPolicy.map(Self.memoryPolicy),
            recoveryItems: (recoverySnapshot?.recoveryItems ?? []).map(recoveryItem),
            recoveryWarning: recoverySnapshot?.corruptionArchiveURL.map { "Corrupted journal archived as \($0.lastPathComponent)" },
            diagnosticsExport: lastDiagnosticsExport,
            configStatus: configStatus,
            durableEventCursors: durableEventCursors)
    }

    @discardableResult
    private func openWorkspace(_ url: URL, restoreSavedState: Bool) async -> Bool {
        cancelWorkspaceTasks()
        if let chatOnlyEnvironment {
            await chatOnlyEnvironment.unloadModels()
            self.chatOnlyEnvironment = nil
            modelStatus = .idle
        }
        do {
            let configSnapshot = await loadWorkspaceConfig(root: url)
            let environment = try await factory.makeWorkspaceEnvironment(
                root: url,
                settings: settings,
                metricsRecorder: metricsRecorder,
                eventBus: eventBus,
                config: configSnapshot.loaded)
            self.environment = environment
            self.workspaceURL = url
            preferences.recordWorkspace(path: url.path)
            if currentConversationMode == .code, currentConversationWorkspacePath != url.path {
                currentConversationID = nil
                currentConversationMode = visibleConversationMode
                currentConversationWorkspacePath = visibleConversationMode == .code ? url.path : nil
                chatMessages.removeAll()
            }
            selectedFilePath = nil
            selectedFileText = ""
            selectedFilePreview = .empty
            diffLines = []
            diffFiles = []
            patchProposal = nil
            isPatchReviewPresented = false
            await reloadFileTree()
            await refreshGit()
            await refreshChatThreads()
            startWatcher()
            startConfigWatcher(root: url)
            reindexTask = Task { await startFullReindex() }
            if restoreSavedState {
                if let path = preferences.lastSelectedFilePath {
                    await selectFile(path)
                }
                if !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    await search(searchQuery)
                }
            }
            return true
        } catch {
            appendNotice(severity: .error, title: "Failed to open workspace", message: String(describing: error))
            await recordFailure(kind: .workspace, message: String(describing: error))
            return false
        }
    }

    @discardableResult
    private func loadWorkspaceConfig(root: URL) async -> ConfigCoordinatorSnapshot {
        let snapshot = await configCoordinator.load(workspaceRoot: root)
        loadedWorkspaceConfig = snapshot.loaded
        configStatus = snapshot.presentation
        await publish(.init(
            kind: .workspace,
            severity: snapshot.loaded.hasErrors ? .error : .info,
            message: "Loaded workspace config",
            metadata: [
                "sources": "\(snapshot.presentation.loadedSourceCount)",
                "diagnostics": "\(snapshot.presentation.diagnostics.count)",
            ]))
        if snapshot.loaded.hasErrors {
            appendNotice(
                severity: .error,
                title: "Config has errors",
                message: snapshot.presentation.summary)
            await recordFailure(kind: .workspace, message: "Workspace config has errors.")
        }
        return snapshot
    }

    public func startFullReindex() async {
        guard let environment else {
            appendNotice(severity: .warning, title: "No workspace", message: "Open a workspace before indexing.")
            await recordFailure(kind: .indexing, message: "Open a workspace before indexing.")
            return
        }
        await publish(.init(kind: .indexing, message: "Started full reindex"))
        let start = ContinuousClock.now
        let taskID = await taskScheduler.begin(kind: "indexing", title: "Full reindex", priority: .userInitiated)
        let recovery = await beginRecovery(.indexing, title: "Full reindex", metadata: workspaceRecoveryMetadata())
        setActivity(.init(kind: .indexing, title: "Indexing workspace"))
        defer { removeActivity(.indexing) }
        let stream = await environment.reindex()
        for await progress in stream {
            if Task.isCancelled {
                indexingProgress = IndexingProgress(phase: .cancelled)
                await taskScheduler.finish(id: taskID, status: .cancelled, message: "Cancelled")
                await finishRecovery(recovery, status: .cancelled, message: "Cancelled")
                await recordCancellation(kind: .indexing, message: "Full reindex cancelled")
                return
            }
            indexingProgress = progress
        }
        await reloadFileTree()
        await refreshGit()
        await recordDuration(.indexingDuration, start: start)
        await taskScheduler.finish(id: taskID, status: .completed)
        await finishRecovery(recovery, status: .completed)
        await publish(.init(kind: .indexing, message: "Completed full reindex"))
    }

    public func search(_ query: String? = nil) async {
        guard let environment else {
            appendNotice(severity: .warning, title: "No workspace", message: "Open a workspace before searching.")
            await recordFailure(kind: .search, message: "Open a workspace before searching.")
            return
        }
        let effectiveQuery = query ?? searchQuery
        guard !effectiveQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchHits = []
            return
        }
        searchQuery = effectiveQuery
        preferences.lastSearchQuery = effectiveQuery
        await publish(.init(kind: .search, message: "Searching workspace", metadata: ["query": effectiveQuery]))
        let start = ContinuousClock.now
        let taskID = await taskScheduler.begin(kind: "search", title: "Workspace search")
        let recovery = await beginRecovery(.search, title: "Workspace search", metadata: workspaceRecoveryMetadata())
        setActivity(.init(kind: .search, title: "Searching workspace"))
        defer { removeActivity(.search) }
        do {
            searchHits = try await environment.search(effectiveQuery, 12)
            await recordDuration(.searchDuration, start: start)
            await taskScheduler.finish(id: taskID, status: .completed, message: "\(searchHits.count) hits")
            await finishRecovery(recovery, status: .completed, message: "\(searchHits.count) hits")
            await publish(.init(kind: .search, message: "Search completed", metadata: ["hits": "\(searchHits.count)"]))
        } catch {
            appendNotice(severity: .error, title: "Search failed", message: String(describing: error))
            await taskScheduler.finish(id: taskID, status: .failed, message: String(describing: error))
            await finishRecovery(recovery, status: .failed, message: String(describing: error))
            await recordFailure(kind: .search, message: String(describing: error))
        }
    }

    public func selectFile(_ relativePath: String) async {
        guard let environment else { return }
        await publish(.init(kind: .filePreview, message: "Previewing file", metadata: ["path": relativePath]))
        let start = ContinuousClock.now
        let recovery = await beginRecovery(.filePreview, title: "Preview file", metadata: workspaceRecoveryMetadata(["relativePath": relativePath]))
        do {
            selectedFilePath = relativePath
            preferences.lastSelectedFilePath = relativePath
            selectedFilePreview = try await environment.previewFile(relativePath)
            selectedFileText = selectedFilePreview.text
            await refreshDiff(path: relativePath)
            await recordDuration(.filePreviewDuration, start: start, metadata: ["path": relativePath])
            await finishRecovery(recovery, status: .completed)
        } catch {
            selectedFilePreview = FilePreviewViewState(
                path: relativePath,
                kind: .error,
                message: String(describing: error))
            selectedFileText = ""
            appendNotice(severity: .error, title: "Preview failed", message: "Failed to preview \(relativePath): \(error)")
            await finishRecovery(recovery, status: .failed, message: String(describing: error))
            await recordFailure(kind: .filePreview, message: String(describing: error))
        }
    }

    public func refreshGit() async {
        guard let environment else { return }
        await publish(.init(kind: .git, message: "Refreshing git status"))
        let start = ContinuousClock.now
        let taskID = await taskScheduler.begin(kind: "git", title: "Refresh git status")
        let recovery = await beginRecovery(.gitRefresh, title: "Refresh git status", metadata: workspaceRecoveryMetadata())
        setActivity(.init(kind: .git, title: "Refreshing git status"))
        defer { removeActivity(.git) }
        gitStatus = await environment.gitStatus()
        await refreshDiff(path: selectedFilePath)
        await recordDuration(.gitDuration, start: start)
        await taskScheduler.finish(id: taskID, status: .completed)
        await finishRecovery(recovery, status: .completed)
    }

    public func runChatPrompt(_ prompt: String? = nil) async {
        guard let environment else {
            appendNotice(severity: .warning, title: "No workspace", message: "Open a workspace before chatting.")
            await recordFailure(kind: .chat, message: "Open a workspace before chatting.")
            return
        }
        let promptText = (prompt ?? chatDraft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !promptText.isEmpty else { return }
        chatDraft = ""
        if chatTask != nil {
            let interruptedSessionID = currentConversationID
            chatTask?.cancel()
            await interruptSession(interruptedSessionID, reason: "superseded")
        }
        let session = await prepareSessionForPrompt(promptText, workspacePath: workspaceURL?.path, mode: .code)
        let sessionID = session?.id
        await publish(.init(kind: .chat, message: "Starting agent chat"))
        let start = ContinuousClock.now
        let taskID = await taskScheduler.begin(kind: "chat", title: "Agent chat", priority: .userInitiated)
        let recovery = await beginRecovery(.chat, title: "Agent chat", metadata: workspaceRecoveryMetadata())
        setActivity(.init(kind: .chat, title: "Agent running", canCancel: true))
        let userID = UUID()
        let assistantID = UUID()
        let runSettings = settings
        let responseModelID = runSettings.orchestratorModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let responseReasoningEffort = ReasoningEffort.resolved(selectedReasoningEffort, for: responseModelID)
        chatMessages.append(.init(id: userID, role: .user, text: promptText))
        chatMessages.append(.init(
            id: assistantID,
            role: .assistant,
            text: "",
            isStreaming: true,
            modelID: responseModelID,
            reasoningEffort: responseReasoningEffort))
        generationStats[assistantID] = MessageGenerationStats()
        codeRunFileChanges[assistantID] = []
        codeRunPrompts[assistantID] = promptText
        await persistSessionUserPrompt(sessionID: sessionID, promptText: promptText, messageID: userID)
        let conversationContext = await conversationContextBundle(
            prompt: promptText,
            sessionID: sessionID,
            isPlainChat: false,
            environment: environment)
        var observations = conversationContext.observations
        observations.append(contentsOf: await workspaceChatObservations(environment: environment, prompt: promptText))
        observations.append(Self.codeModeToolFirstObservation(selectedFilePath: selectedFilePath))
        // Re-inject the agent's own open plan each turn (Claude Code-style):
        // without this, todos persist to storage but the model forgets them.
        if let todoObservation = await openTodosObservation(sessionID: sessionID) {
            observations.append(todoObservation)
        }
        observations.append(responseReasoningEffort.promptInstruction(for: responseModelID))
        let contextEpoch = await contextEpochStore.replace(
            sessionID: sessionID ?? assistantID,
            reason: .promptExpansion,
            context: ([promptText] + observations).joined(separator: "\n"))
        observations.append("Context epoch: revision \(contextEpoch.revision), hash \(contextEpoch.contextHash)")
        chatTask = Task {
            defer {
                removeActivity(.chat)
                chatTask = nil
            }
            do {
                let stream = await environment.runAgent(
                    AgentTask(
                        prompt: promptText,
                        observations: observations,
                        maxTokens: modelContextSettings.maxAnswerTokens(isPlainChat: false),
                        contextTokenBudget: modelContextSettings.contextTokenBudgetOverride(isPlainChat: false),
                        reasoningEffort: responseReasoningEffort),
                    runSettings,
                    toolRuntimeHooks(sessionID: sessionID))
                for try await event in stream {
                    await handleAgentEvent(event, assistantID: assistantID, sessionID: sessionID)
                }
                finishStreamingMessage(id: assistantID)
                await persistSessionAssistantMessage(sessionID: sessionID, id: assistantID)
                await compactConversationIfNeeded(sessionID: sessionID, isPlainChat: false, environment: environment)
                await recordDuration(.inferenceLatency, start: start)
                await taskScheduler.finish(id: taskID, status: .completed)
                await finishRecovery(recovery, status: .completed)
                await publish(.init(kind: .chat, message: "Agent chat completed"))
                await refreshChatThreads()
                codeRunFileChanges[assistantID] = nil
                codeRunPrompts[assistantID] = nil
            } catch is CancellationError {
                finishStreamingMessage(id: assistantID)
                let toolID = appendTool("Chat cancelled")
                await persistSessionMessagePart(sessionID: sessionID, messageID: toolID, role: .tool, kind: "cancelled", text: "Chat cancelled")
                await persistSessionAssistantMessage(sessionID: sessionID, id: assistantID, fallbackText: "Chat cancelled", role: .assistant, kind: "cancelled")
                await interruptSession(sessionID, reason: "cancelled")
                await taskScheduler.finish(id: taskID, status: .cancelled, message: "Cancelled")
                await finishRecovery(recovery, status: .cancelled, message: "Cancelled")
                await recordCancellation(kind: .chat, message: "Agent chat cancelled")
                await refreshChatThreads()
                codeRunFileChanges[assistantID] = nil
                codeRunPrompts[assistantID] = nil
            } catch {
                finishStreamingMessage(id: assistantID)
                let errorID = appendTranscriptError("Agent failed: \(error)")
                await persistSessionMessagePart(sessionID: sessionID, messageID: errorID, role: .assistant, kind: "error", text: "Agent failed: \(error)")
                await persistSessionAssistantMessage(sessionID: sessionID, id: assistantID, fallbackText: "Agent failed: \(error)", role: .assistant, kind: "error")
                await recordSessionEvent(sessionID: sessionID, kind: .failed, messageID: assistantID, payload: ["error": String(describing: error)])
                appendNotice(severity: .error, title: "Agent failed", message: String(describing: error))
                await taskScheduler.finish(id: taskID, status: .failed, message: String(describing: error))
                await finishRecovery(recovery, status: .failed, message: String(describing: error))
                await recordFailure(kind: .chat, message: String(describing: error))
                await refreshChatThreads()
                codeRunFileChanges[assistantID] = nil
                codeRunPrompts[assistantID] = nil
            }
        }
    }

    public func runPlainChatPrompt(_ prompt: String? = nil) async {
        let promptText = (prompt ?? chatDraft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !promptText.isEmpty else { return }
        chatDraft = ""
        if chatTask != nil {
            let interruptedSessionID = currentConversationID
            chatTask?.cancel()
            await interruptSession(interruptedSessionID, reason: "superseded")
        }
        let session = await prepareSessionForPrompt(promptText, workspacePath: nil, mode: .chat)
        let sessionID = session?.id
        await publish(.init(kind: .chat, message: "Starting plain chat"))
        let start = ContinuousClock.now
        let taskID = await taskScheduler.begin(kind: "chat", title: "Plain chat", priority: .userInitiated)
        let recovery = await beginRecovery(.chat, title: "Plain chat")
        setActivity(.init(kind: .chat, title: "Chat running", canCancel: true))
        let userID = UUID()
        let assistantID = UUID()
        let runSettings = settings
        let responseModelID = runSettings.orchestratorModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let responseReasoningEffort = ReasoningEffort.resolved(selectedReasoningEffort, for: responseModelID)
        chatMessages.append(.init(id: userID, role: .user, text: promptText))
        chatMessages.append(.init(
            id: assistantID,
            role: .assistant,
            text: "",
            isStreaming: true,
            modelID: responseModelID,
            reasoningEffort: responseReasoningEffort))
        generationStats[assistantID] = MessageGenerationStats()
        await persistSessionUserPrompt(sessionID: sessionID, promptText: promptText, messageID: userID)
        let runtimeEnvironment = try? await modelRuntimeEnvironment()
        var observations = await conversationContextBundle(
            prompt: promptText,
            sessionID: sessionID,
            isPlainChat: true,
            environment: runtimeEnvironment).observations
        observations.append("interless.mode=plainChat")
        observations.append(responseReasoningEffort.promptInstruction(for: responseModelID))
        chatTask = Task {
            defer {
                removeActivity(.chat)
                chatTask = nil
            }
            do {
                let environment = try await modelRuntimeEnvironment()
                let task = AgentTask(
                    prompt: promptText,
                    kind: .simpleQuestion,
                    observations: observations,
                    maxTokens: modelContextSettings.maxAnswerTokens(isPlainChat: true),
                    contextTokenBudget: modelContextSettings.contextTokenBudgetOverride(isPlainChat: true),
                    reasoningEffort: responseReasoningEffort)
                let stream = await environment.runAgent(task, runSettings, toolRuntimeHooks(sessionID: sessionID))
                for try await event in stream {
                    handlePlainChatEvent(event, assistantID: assistantID, sessionID: sessionID)
                }
                finishStreamingMessage(id: assistantID)
                await persistSessionAssistantMessage(sessionID: sessionID, id: assistantID)
                await compactConversationIfNeeded(sessionID: sessionID, isPlainChat: true, environment: environment)
                await recordDuration(.inferenceLatency, start: start)
                await taskScheduler.finish(id: taskID, status: .completed)
                await finishRecovery(recovery, status: .completed)
                await publish(.init(kind: .chat, message: "Plain chat completed"))
                await refreshChatThreads()
            } catch is CancellationError {
                finishStreamingMessage(id: assistantID)
                await persistSessionAssistantMessage(sessionID: sessionID, id: assistantID, fallbackText: "Chat cancelled", role: .assistant, kind: "cancelled")
                await interruptSession(sessionID, reason: "cancelled")
                await taskScheduler.finish(id: taskID, status: .cancelled, message: "Cancelled")
                await finishRecovery(recovery, status: .cancelled, message: "Cancelled")
                await recordCancellation(kind: .chat, message: "Plain chat cancelled")
                await refreshChatThreads()
            } catch {
                finishStreamingMessage(id: assistantID)
                let errorID = appendTranscriptError("Chat failed: \(error)")
                await persistSessionMessagePart(sessionID: sessionID, messageID: errorID, role: .assistant, kind: "error", text: "Chat failed: \(error)")
                await persistSessionAssistantMessage(sessionID: sessionID, id: assistantID, fallbackText: "Chat failed: \(error)", role: .assistant, kind: "error")
                await recordSessionEvent(sessionID: sessionID, kind: .failed, messageID: assistantID, payload: ["error": String(describing: error)])
                appendNotice(severity: .error, title: "Chat failed", message: String(describing: error))
                await taskScheduler.finish(id: taskID, status: .failed, message: String(describing: error))
                await finishRecovery(recovery, status: .failed, message: String(describing: error))
                await recordFailure(kind: .chat, message: String(describing: error))
                await refreshChatThreads()
            }
        }
    }

    public func loadModels() async {
        let environment: WorkspaceEnvironment
        do {
            environment = try await modelRuntimeEnvironment()
        } catch {
            modelStatus = .failed(String(describing: error))
            modelDownloadProgress = nil
            appendNotice(severity: .error, title: "Model runtime unavailable", message: String(describing: error))
            await recordFailure(kind: .model, message: String(describing: error))
            return
        }
        let errors = settings.validationErrors()
        guard errors.isEmpty else {
            modelStatus = .failed(errors.joined(separator: " "))
            modelDownloadProgress = nil
            await recordFailure(kind: .model, message: errors.joined(separator: " "))
            return
        }
        preferences.modelSettings = settings
        let loadID = UUID()
        if let activeModelLoadID {
            cancelledModelLoadIDs.insert(activeModelLoadID)
        }
        modelLoadTask?.cancel()
        activeModelLoadID = loadID
        cancelledModelLoadIDs.remove(loadID)
        modelLoadTask = nil
        modelStatus = .loading
        modelDownloadProgress = nil
        setActivity(.init(kind: .modelLoading, title: "Loading models", canCancel: true))
        await publish(.init(kind: .model, message: "Loading models"))
        let start = ContinuousClock.now
        let taskID = await taskScheduler.begin(kind: "model", title: "Load models", priority: .userInitiated)
        let recovery = await beginRecovery(.modelLoad, title: "Load models", metadata: modelRecoveryMetadata())
        if isModelLoadCancellationRequested(loadID) {
            await completeCancelledModelLoad(loadID, taskID: taskID, recovery: recovery)
            return
        }
        let task = Task {
            try await environment.loadModels(settings) { [weak self] modelID, role, fractionCompleted in
                Task { @MainActor [weak self] in
                    self?.updateModelDownloadProgress(
                        loadID: loadID,
                        modelID: modelID,
                        role: role,
                        fractionCompleted: fractionCompleted)
                }
            }
        }
        if isModelLoadCancellationRequested(loadID) {
            task.cancel()
            await completeCancelledModelLoad(loadID, taskID: taskID, recovery: recovery)
            return
        }
        modelLoadTask = task
        do {
            try await task.value
            if isModelLoadCancellationRequested(loadID) {
                if activeModelLoadID == loadID {
                    await environment.unloadModels()
                }
                await completeCancelledModelLoad(loadID, taskID: taskID, recovery: recovery)
                return
            }
            guard activeModelLoadID == loadID else {
                cancelledModelLoadIDs.remove(loadID)
                return
            }
            modelStatus = .loaded
            modelDownloadProgress = nil
            refreshAvailableChatModels(includeConfigured: true)
            await persistModelAssignments()
            await recordDuration(.modelLoadDuration, start: start)
            await taskScheduler.finish(id: taskID, status: .completed)
            await finishRecovery(recovery, status: .completed)
            await publish(.init(kind: .model, message: "Models loaded"))
            finishModelLoadRun(loadID)
        } catch is CancellationError {
            if activeModelLoadID == loadID {
                await environment.unloadModels()
            }
            await completeCancelledModelLoad(loadID, taskID: taskID, recovery: recovery)
        } catch {
            if isModelLoadCancellationRequested(loadID) {
                if activeModelLoadID == loadID {
                    await environment.unloadModels()
                }
                await completeCancelledModelLoad(loadID, taskID: taskID, recovery: recovery)
                return
            }
            guard activeModelLoadID == loadID else {
                await taskScheduler.finish(id: taskID, status: .cancelled, message: "Superseded")
                await finishRecovery(recovery, status: .cancelled, message: "Superseded")
                await recordCancellation(kind: .model, message: "Model loading superseded")
                cancelledModelLoadIDs.remove(loadID)
                return
            }
            modelStatus = .failed(String(describing: error))
            modelDownloadProgress = nil
            appendNotice(severity: .error, title: "Model loading failed", message: String(describing: error))
            await taskScheduler.finish(id: taskID, status: .failed, message: String(describing: error))
            await finishRecovery(recovery, status: .failed, message: String(describing: error))
            await recordFailure(kind: .model, message: String(describing: error))
            finishModelLoadRun(loadID)
        }
    }

    public func unloadModels() async {
        cancelModelLoad()
        let loadedEnvironments = [environment, chatOnlyEnvironment].compactMap { $0 }
        let recovery = await beginRecovery(.modelUnload, title: "Unload models", metadata: modelRecoveryMetadata())
        for environment in loadedEnvironments {
            await environment.unloadModels()
        }
        modelStatus = .idle
        modelDownloadProgress = nil
        refreshAvailableChatModels(includeConfigured: false)
        await finishRecovery(recovery, status: .completed)
        await publish(.init(kind: .model, message: "Models unloaded"))
    }

    public func cancelActiveChat() {
        let interruptedSessionID = currentConversationID
        chatTask?.cancel()
        chatTask = nil
        removeActivity(.chat)
        Task {
            await interruptSession(interruptedSessionID, reason: "user")
            await recordCancellation(kind: .chat, message: "Chat cancellation requested")
        }
    }

    public func resolvePermissionPrompt(_ id: UUID, action: PermissionPromptAction) {
        guard let continuation = permissionContinuations.removeValue(forKey: id) else { return }
        if permissionPrompt?.id == id {
            permissionPrompt = nil
        }
        switch action {
        case .allowOnce:
            continuation.resume(returning: .allowOnce)
        case .deny:
            continuation.resume(returning: .deny)
        }
    }

    public func answerQuestionPrompt(_ id: UUID, answer: String) {
        guard let continuation = questionContinuations.removeValue(forKey: id) else { return }
        if questionPrompt?.id == id {
            questionPrompt = nil
        }
        continuation.resume(returning: ToolQuestionResponse(
            answer: answer.trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    public func cancelQuestionPrompt(_ id: UUID) {
        guard let continuation = questionContinuations.removeValue(forKey: id) else { return }
        if questionPrompt?.id == id {
            questionPrompt = nil
        }
        continuation.resume(throwing: CancellationError())
    }

    public func cancelBackgroundJob(_ id: UUID) {
        guard let index = backgroundToolJobs.firstIndex(where: { $0.id == id }) else { return }
        backgroundToolJobs[index].status = .cancelled
        backgroundToolJobs[index].canCancel = false
        Task {
            await recordSessionEvent(
                sessionID: currentConversationID,
                kind: .interrupted,
                payload: ["jobID": id.uuidString, "reason": "cancelled"])
        }
    }

    public func cancelModelLoad() {
        guard modelLoadTask != nil || activeModelLoadID != nil else { return }
        if let activeModelLoadID {
            cancelledModelLoadIDs.insert(activeModelLoadID)
        }
        modelStatus = .cancelling
        modelDownloadProgress = nil
        modelLoadTask?.cancel()
        removeActivity(.modelLoading)
    }

    public func clearChat(plain: Bool? = nil) {
        let mode = plain.map { $0 ? ConversationMode.chat : .code } ?? visibleConversationMode
        visibleConversationMode = mode
        chatMessages.removeAll()
        todoPanel = TodoPanelViewState()
        sessionTimelineItems = []
        currentConversationID = nil
        currentConversationMode = mode
        currentConversationWorkspacePath = mode == .code ? workspaceURL?.path : nil
        if mode == .chat {
            insertDraftGlobalChatThread()
        } else {
            insertDraftChatThread()
        }
        scheduleChatThreadsRefresh(includeDraft: true)
        focusTarget = .chat
    }

    public func selectConversation(_ id: UUID) async {
        guard settings.persistPromptHistory, let sessionStore else { return }
        do {
            guard let session = try await sessionStore.session(id: id),
                  sessionCanBeShown(session) else {
                appendNotice(severity: .warning, title: "Chat unavailable", message: "This chat belongs to a different mode or workspace.")
                return
            }
            await loadSession(session)
            await refreshChatThreads()
            focusTarget = .chat
        } catch {
            appendNotice(severity: .warning, title: "Chat unavailable", message: String(describing: error))
            await recordFailure(kind: .failure, message: "Failed to restore selected local chat.")
        }
    }

    public func deleteConversation(_ id: UUID) async {
        guard settings.persistPromptHistory, let sessionStore else { return }
        do {
            try await sessionStore.deleteSession(id: id)
            if currentConversationID == id {
                currentConversationID = nil
                currentConversationMode = visibleConversationMode
                currentConversationWorkspacePath = visibleConversationMode == .code ? workspaceURL?.path : nil
                chatMessages.removeAll()
                todoPanel = TodoPanelViewState()
                sessionTimelineItems = []
            }
            await refreshChatThreads(includeDraft: currentConversationID == nil)
        } catch {
            appendNotice(severity: .error, title: "Chat delete failed", message: String(describing: error))
            await recordFailure(kind: .chat, message: "Failed to delete local chat.")
        }
    }

    public func renameConversation(_ id: UUID, title: String) async {
        guard settings.persistPromptHistory, let sessionStore else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try await sessionStore.renameSession(id: id, title: trimmed)
            await refreshChatThreads(includeDraft: currentConversationID == nil)
        } catch {
            appendNotice(severity: .error, title: "Chat rename failed", message: String(describing: error))
            await recordFailure(kind: .chat, message: "Failed to rename local chat.")
        }
    }

    public func setConversationMode(isPlainChat: Bool) async {
        let mode: ConversationMode = isPlainChat ? .chat : .code
        guard visibleConversationMode != mode else { return }
        visibleConversationMode = mode
        guard settings.persistPromptHistory, let sessionStore else {
            currentConversationID = nil
            currentConversationMode = mode
            currentConversationWorkspacePath = mode == .code ? workspaceURL?.path : nil
            chatMessages.removeAll()
            todoPanel = TodoPanelViewState()
            sessionTimelineItems = []
            await refreshChatThreads(includeDraft: true)
            return
        }
        do {
            let sessions: [SessionRecord]
            if mode == .chat {
                sessions = try await recentPlainSessions(limit: 1)
            } else if let workspacePath = workspaceURL?.path {
                sessions = try await sessionStore.recentSessions(limit: 1, workspacePath: workspacePath)
            } else {
                sessions = []
            }
            guard let session = sessions.first else {
                currentConversationID = nil
                currentConversationMode = mode
                currentConversationWorkspacePath = mode == .code ? workspaceURL?.path : nil
                chatMessages.removeAll()
                todoPanel = TodoPanelViewState()
                sessionTimelineItems = []
                await refreshChatThreads(includeDraft: true)
                return
            }
            await loadSession(session)
            await refreshChatThreads()
        } catch {
            appendNotice(severity: .warning, title: "Chat unavailable", message: String(describing: error))
            await recordFailure(kind: .failure, message: "Failed to switch local chat mode.")
        }
    }

    public func focusChat() {
        focusTarget = .chat
    }

    public func focusSearch() {
        focusTarget = .search
    }

    public func openHealth() {
        isHealthPresented = true
        Task { await refreshHealthStatus() }
    }

    public func exportDiagnostics(to url: URL, includeFullPaths: Bool = false) async {
        await publish(.init(kind: .diagnostics, message: "Exporting diagnostics"))
        let taskID = await taskScheduler.begin(kind: "diagnostics", title: "Export diagnostics", priority: .userInitiated)
        do {
            let exporter = DiagnosticsExporter()
            let recoverySnapshot = try? await recoveryJournal.snapshot(limit: 100)
            let sessionObservability = await diagnosticsSessionObservability(limit: 100)
            let request = DiagnosticsExportRequest(
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "development",
                buildIdentifier: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "local",
                workspacePath: workspaceURL?.path,
                includeFullPaths: includeFullPaths,
                maxRecords: 100,
                maxMessageLength: 240,
                settings: diagnosticsSettings(),
                events: await eventBus.recentEvents(limit: 100),
                taskSnapshot: await taskScheduler.snapshot(),
                metricSummaries: await metricsRecorder.summaries(),
                metricSamples: await metricsRecorder.recentSamples(limit: 100),
                memoryPolicyState: await environment?.memoryPolicy(),
                recoverySnapshot: recoverySnapshot,
                durableEventCursors: sessionObservability.cursors,
                sessionEvents: sessionObservability.events)
            let bundle = try await exporter.export(request: request)
            try await exporter.write(bundle: bundle, to: url)
            lastDiagnosticsExport = DiagnosticsExportViewState(
                path: url.path,
                includeFullPaths: includeFullPaths)
            appendNotice(
                severity: .info,
                title: "Diagnostics exported",
                message: url.path)
            await taskScheduler.finish(id: taskID, status: .completed, message: url.lastPathComponent)
            await publish(.init(kind: .diagnostics, message: "Diagnostics exported", metadata: ["path": url.path]))
        } catch {
            appendNotice(severity: .error, title: "Diagnostics export failed", message: String(describing: error))
            await taskScheduler.finish(id: taskID, status: .failed, message: String(describing: error))
            await recordFailure(kind: .diagnostics, message: String(describing: error))
        }
    }

    private var indexingSummary: String {
        guard let progress = indexingProgress else { return workspaceURL == nil ? "No workspace" : "Ready" }
        return "\(progress.phase.rawValue) · scanned \(progress.scanned) · indexed \(progress.indexed) · skipped \(progress.skipped) · removed \(progress.removed)"
    }

    private var gitSummary: String {
        guard gitStatus.isRepository else { return "Not a git repository" }
        let branch = gitStatus.branch ?? "detached"
        return "\(branch) · \(gitStatus.entries.count) changed"
    }

    private func startWatcher() {
        guard let environment else { return }
        watchTask = Task {
            let stream = await environment.watch()
            for await progress in stream {
                indexingProgress = progress
            }
        }
    }

    private func startConfigWatcher(root: URL) {
        configWatchTask?.cancel()
        configWatchTask = Task {
            let stream = await configCoordinator.watch(workspaceRoot: root)
            for await snapshot in stream {
                if Task.isCancelled { return }
                await applyConfigReload(snapshot, root: root)
            }
        }
    }

    private func applyConfigReload(_ snapshot: ConfigCoordinatorSnapshot, root: URL) async {
        guard workspaceURL?.standardizedFileURL.path == root.standardizedFileURL.path else { return }
        loadedWorkspaceConfig = snapshot.loaded
        configStatus = snapshot.presentation
        do {
            if let environment, modelStatus == .loaded {
                await environment.unloadModels()
                modelStatus = .idle
            }
            let environment = try await factory.makeWorkspaceEnvironment(
                root: root,
                settings: settings,
                metricsRecorder: metricsRecorder,
                eventBus: eventBus,
                config: snapshot.loaded)
            self.environment = environment
            watchTask?.cancel()
            startWatcher()
            await publish(.init(
                kind: .workspace,
                message: "Reloaded workspace config",
                metadata: [
                    "sources": "\(snapshot.presentation.loadedSourceCount)",
                    "diagnostics": "\(snapshot.presentation.diagnostics.count)",
                ]))
        } catch {
            appendNotice(severity: .error, title: "Config reload failed", message: String(describing: error))
            await recordFailure(kind: .workspace, message: "Config reload failed: \(error)")
        }
    }

    private func reloadFileTree() async {
        guard let environment else { return }
        do {
            fileTree = try await environment.fileTree()
            fileTreeVersion += 1
        } catch {
            appendNotice(severity: .error, title: "File tree failed", message: String(describing: error))
        }
    }

    private func refreshDiff(path: String?) async {
        guard let environment else { return }
        do {
            let diff = try await environment.gitDiff(path)
            diffLines = DiffFormatter.classify(diff)
            diffFiles = DiffFormatter.files(diff)
        } catch {
            diffLines = []
            diffFiles = []
        }
    }

    private func handleAgentEvent(_ event: AgentEvent, assistantID: UUID, sessionID: UUID?) async {
        // Flush buffered streamed text before any non-token event mutates the
        // transcript, so ordering with tool/route/completion events is preserved.
        if case .token = event {} else { flushPendingStreamedText(id: assistantID) }
        switch event {
        case .token(let chunk):
            updateGenerationStats(for: assistantID, chunk: chunk)
            if !chunk.text.isEmpty {
                bufferStreamedText(id: assistantID, text: chunk.text)
            }
        case .toolIterationStarted(let iteration):
            let id = appendTool("Tool iteration \(iteration)")
            Task { await persistSessionMessagePart(sessionID: sessionID, messageID: id, role: .tool, kind: "toolIteration", text: "Tool iteration \(iteration)") }
        case .toolCallRequested(let call):
            let id = appendTool("Requested \(call.name)")
            Task { await persistSessionMessagePart(sessionID: sessionID, messageID: id, role: .tool, kind: "toolRequested", text: "Requested \(call.name)") }
        case .toolCallRejected(let call, let reason):
            let text = "Rejected \(call.name): \(reason)"
            let id = appendTool(text)
            Task { await persistSessionMessagePart(sessionID: sessionID, messageID: id, role: .tool, kind: "toolRejected", text: text) }
        case .toolStarted(let request):
            let text = "Started \(request.displayName)"
            let id = appendTool(text)
            Task {
                await persistSessionMessagePart(sessionID: sessionID, messageID: id, role: .tool, kind: "toolStarted", text: text)
                await recordSessionEvent(sessionID: sessionID, kind: .toolCallStarted, messageID: id, payload: ["tool": request.displayName])
                await publish(.init(kind: .tool, message: "Tool started", metadata: ["tool": request.displayName]))
            }
        case .toolFinished(let result):
            if !result.fileChanges.isEmpty {
                codeRunFileChanges[assistantID, default: []].append(contentsOf: result.fileChanges)
                let id = appendFileChangeSummary(result.fileChanges, diffFiles: diffFiles)
                Task {
                    await recordSessionEvent(sessionID: sessionID, kind: .toolCallSettled, messageID: id, payload: [
                        "tool": result.request.displayName,
                        "exitCode": result.exitCode.map(String.init) ?? "n/a",
                        "fileChanges": result.fileChanges.map(\.path).joined(separator: ","),
                    ])
                    await recordRecoveryInstant(
                        .toolExecution,
                        title: "Tool \(result.request.displayName)",
                        status: result.exitCode == 0 || result.exitCode == nil ? .completed : .failed,
                        message: result.exitCode.map { "exit=\($0)" },
                        metadata: workspaceRecoveryMetadata([
                            "tool": result.request.displayName,
                            "exitCode": result.exitCode.map(String.init) ?? "n/a",
                            "files": result.fileChanges.map(\.path).joined(separator: ","),
                        ]))
                    await publish(.init(kind: .tool, message: "Tool changed files", metadata: [
                        "tool": result.request.displayName,
                        "files": "\(result.fileChanges.count)",
                    ]))
                    await refreshGit()
                    await updateFileChangeSummary(messageID: id, changes: result.fileChanges, sessionID: sessionID)
                }
                return
            }
            let text = "Finished \(result.request.displayName) exit=\(result.exitCode.map(String.init) ?? "n/a")"
            let id = appendTool(text)
            Task {
                await persistSessionMessagePart(sessionID: sessionID, messageID: id, role: .tool, kind: "toolFinished", text: text)
                await recordSessionEvent(sessionID: sessionID, kind: .toolCallSettled, messageID: id, payload: [
                    "tool": result.request.displayName,
                    "exitCode": result.exitCode.map(String.init) ?? "n/a",
                ])
                await recordRecoveryInstant(
                    .toolExecution,
                    title: "Tool \(result.request.displayName)",
                    status: result.exitCode == 0 || result.exitCode == nil ? .completed : .failed,
                    message: result.exitCode.map { "exit=\($0)" },
                    metadata: workspaceRecoveryMetadata([
                        "tool": result.request.displayName,
                        "exitCode": result.exitCode.map(String.init) ?? "n/a",
                    ]))
                await publish(.init(kind: .tool, message: "Tool finished", metadata: [
                    "tool": result.request.displayName,
                    "exitCode": result.exitCode.map(String.init) ?? "n/a",
                ]))
            }
        case .routeSelected(let route):
            let id = appendTool("Route \(route.rawValue)")
            Task { await persistSessionMessagePart(sessionID: sessionID, messageID: id, role: .system, kind: "route", text: "Route \(route.rawValue)") }
        case .contextBuilt:
            let id = appendTool("Context built")
            Task { await persistSessionMessagePart(sessionID: sessionID, messageID: id, role: .system, kind: "context", text: "Context built") }
        case .contextCompacted(let degraded, let dropped):
            let text = "Context compacted to fit the model window (\(degraded) tool output\(degraded == 1 ? "" : "s") trimmed, \(dropped) message\(dropped == 1 ? "" : "s") dropped)"
            let id = appendTool(text)
            Task { await persistSessionMessagePart(sessionID: sessionID, messageID: id, role: .system, kind: "context", text: text) }
        case .completed(let result):
            updateGenerationSpeed(for: assistantID, info: result.completionInfo)
            let sanitized = await finalizedCodeModeAssistantText(
                result.text,
                assistantID: assistantID,
                sessionID: sessionID)
            replaceMessage(id: assistantID, text: sanitized, isStreaming: false)
        case .failed(let reason):
            let id = appendTranscriptError(reason)
            Task {
                await persistSessionMessagePart(sessionID: sessionID, messageID: id, role: .assistant, kind: "error", text: reason)
                await recordSessionEvent(sessionID: sessionID, kind: .failed, messageID: id, payload: ["error": reason])
            }
            appendNotice(severity: .error, title: "Agent failed", message: reason)
        }
    }

    private func finalizedCodeModeAssistantText(
        _ text: String,
        assistantID: UUID,
        sessionID: UUID?
    ) async -> String {
        var didWriteGeneratedFallback = false
        // Auto-write only when writes are outright allowed. Under `.ask` the
        // fallback fires after the answer has already streamed, so a permission
        // modal would pop for a write the user didn't visibly request; under
        // `.deny` it would just throw. In both cases the model's code is still
        // shown (the sanitizer runs below) and the user can save it via a tool.
        if effectiveWritePermission == .allow,
           codeRunFileChanges[assistantID, default: []].isEmpty,
           let environment,
           let prompt = codeRunPrompts[assistantID],
           let candidate = CodeModeGeneratedFileFallback.candidate(
            prompt: prompt,
            assistantText: text,
            selectedPath: selectedFilePath,
            fileTreePaths: flattenFileTree(fileTree).filter { !$0.isDirectory }.map(\.path)
           ) {
            do {
                let result = try await environment.executeTool(
                    .writeFile(path: candidate.path, contents: candidate.contents),
                    settings,
                    toolRuntimeHooks(sessionID: sessionID))
                if !result.fileChanges.isEmpty {
                    codeRunFileChanges[assistantID, default: []].append(contentsOf: result.fileChanges)
                    let id = appendFileChangeSummary(result.fileChanges, diffFiles: diffFiles)
                    await recordSessionEvent(sessionID: sessionID, kind: .toolCallSettled, messageID: id, payload: [
                        "tool": result.request.displayName,
                        "exitCode": result.exitCode.map(String.init) ?? "n/a",
                        "fileChanges": result.fileChanges.map(\.path).joined(separator: ","),
                        "source": "code-mode-fallback",
                    ])
                    await publish(.init(kind: .tool, message: "Code mode wrote generated file", metadata: [
                        "files": "\(result.fileChanges.count)",
                    ]))
                    didWriteGeneratedFallback = true
                    await refreshGit()
                    await reloadFileTree()
                    await updateFileChangeSummary(messageID: id, changes: result.fileChanges, sessionID: sessionID)
                }
            } catch {
                let id = appendTool("Generated file was not written: \(error)")
                await persistSessionMessagePart(
                    sessionID: sessionID,
                    messageID: id,
                    role: .tool,
                    kind: "toolRejected",
                    text: "Generated file was not written: \(error)")
                appendNotice(severity: .warning, title: "File not written", message: String(describing: error))
            }
        }
        return CodeModeFinalAnswerSanitizer.sanitize(
            text,
            fileChanges: codeRunFileChanges[assistantID, default: []],
            minimumFenceCharacters: didWriteGeneratedFallback ? 0 : 600)
    }

    private func handlePlainChatEvent(_ event: AgentEvent, assistantID: UUID, sessionID: UUID?) {
        if case .token = event {} else { flushPendingStreamedText(id: assistantID) }
        switch event {
        case .token(let chunk):
            updateGenerationStats(for: assistantID, chunk: chunk)
            if !chunk.text.isEmpty {
                bufferStreamedText(id: assistantID, text: chunk.text)
            }
        case .completed(let result):
            updateGenerationSpeed(for: assistantID, info: result.completionInfo)
            replaceMessage(id: assistantID, text: result.text, isStreaming: false)
        case .failed(let reason):
            let id = appendTranscriptError(reason)
            Task {
                await persistSessionMessagePart(sessionID: sessionID, messageID: id, role: .assistant, kind: "error", text: reason)
                await recordSessionEvent(sessionID: sessionID, kind: .failed, messageID: id, payload: ["error": reason])
            }
        default:
            break
        }
    }

    private func appendToMessage(id: UUID, text: String) {
        guard let index = chatMessages.firstIndex(where: { $0.id == id }) else { return }
        chatMessages[index].text += text
        trimChatTranscript()
    }

    /// Buffer a streamed chunk; apply to the transcript only once enough text has
    /// accumulated, so most tokens cost a cheap dictionary append rather than a
    /// `@Published` mutation + transcript trim + viewState rebuild.
    private func bufferStreamedText(id: UUID, text: String) {
        pendingStreamedText[id, default: ""] += text
        if (pendingStreamedText[id]?.utf8.count ?? 0) >= Self.tokenFlushThresholdCharacters {
            flushPendingStreamedText(id: id)
        }
    }

    /// Apply any buffered streamed text for `id` to the transcript in one mutation.
    private func flushPendingStreamedText(id: UUID) {
        guard let pending = pendingStreamedText.removeValue(forKey: id), !pending.isEmpty else { return }
        guard let index = chatMessages.firstIndex(where: { $0.id == id }) else { return }
        chatMessages[index].text += pending
        trimChatTranscript()
    }

    private func updateGenerationStats(for id: UUID, chunk: TokenChunk) {
        if !chunk.text.isEmpty {
            generationStats[id, default: MessageGenerationStats()].streamedTokenCount += 1
        }
        updateGenerationSpeed(for: id, info: chunk.info)
    }

    private func updateGenerationSpeed(for id: UUID, info: TokenChunk.CompletionInfo?) {
        if info == nil,
           let index = chatMessages.firstIndex(where: { $0.id == id }),
           chatMessages[index].tokensPerSecond != nil {
            return
        }
        guard let index = chatMessages.firstIndex(where: { $0.id == id }) else { return }
        if let speed = resolvedTokensPerSecond(for: id, info: info) {
            chatMessages[index].tokensPerSecond = speed
        }
        if let reason = info?.stopReason.trimmingCharacters(in: .whitespacesAndNewlines),
           !reason.isEmpty {
            chatMessages[index].completionStopReason = reason
        }
    }

    private func resolvedTokensPerSecond(for id: UUID, info: TokenChunk.CompletionInfo?) -> Double? {
        if let provided = info?.tokensPerSecond, provided.isFinite, provided > 0 {
            return provided
        }
        if let info,
           info.generationTokenCount > 0,
           info.generateTime > 0 {
            return Double(info.generationTokenCount) / info.generateTime
        }
        guard let stats = generationStats[id], stats.streamedTokenCount > 0 else { return nil }
        let elapsed = Date().timeIntervalSince(stats.startedAt)
        guard elapsed > 0 else { return nil }
        return Double(stats.streamedTokenCount) / elapsed
    }

    private func replaceMessage(id: UUID, text: String, isStreaming: Bool) {
        guard let index = chatMessages.firstIndex(where: { $0.id == id }) else { return }
        chatMessages[index].text = Self.finalMessageText(
            text,
            reasoningEffort: chatMessages[index].reasoningEffort)
        chatMessages[index].isStreaming = isStreaming
        trimChatTranscript()
    }

    private func finishStreamingMessage(id: UUID) {
        flushPendingStreamedText(id: id)
        guard let index = chatMessages.firstIndex(where: { $0.id == id }) else { return }
        if chatMessages[index].tokensPerSecond == nil,
           let speed = resolvedTokensPerSecond(for: id, info: nil) {
            chatMessages[index].tokensPerSecond = speed
        }
        chatMessages[index].text = Self.finalMessageText(
            chatMessages[index].text,
            reasoningEffort: chatMessages[index].reasoningEffort)
        chatMessages[index].isStreaming = false
        generationStats[id] = nil
    }

    private static func finalMessageText(_ text: String, reasoningEffort: ReasoningEffort?) -> String {
        trimTrailingMessageWhitespace(
            ReasoningOutputSanitizer.visibleText(text, reasoningEffort: reasoningEffort))
    }

    private static func trimTrailingMessageWhitespace(_ text: String) -> String {
        var end = text.endIndex
        while end > text.startIndex {
            let previous = text.index(before: end)
            guard text[previous].isWhitespace else { break }
            end = previous
        }
        return String(text[..<end])
    }

    @discardableResult
    private func appendTool(_ text: String) -> UUID {
        let id = UUID()
        chatMessages.append(.init(id: id, role: .tool, text: text, isCollapsed: true))
        trimChatTranscript()
        return id
    }

    @discardableResult
    private func appendFileChangeSummary(_ changes: [ToolFileChange], diffFiles: [DiffFile]) -> UUID {
        let id = UUID()
        let summary = Self.fileChangeSummary(changes: changes, diffFiles: diffFiles)
        chatMessages.append(.init(
            id: id,
            role: .tool,
            kind: "fileChanges",
            text: Self.encodedToolSummary(summary),
            isCollapsed: false,
            toolSummary: summary))
        trimChatTranscript()
        return id
    }

    private func updateFileChangeSummary(
        messageID: UUID,
        changes: [ToolFileChange],
        sessionID: UUID?
    ) async {
        await refreshDiff(path: nil)
        let summary = Self.fileChangeSummary(changes: changes, diffFiles: diffFiles)
        if let index = chatMessages.firstIndex(where: { $0.id == messageID }) {
            chatMessages[index].toolSummary = summary
            chatMessages[index].text = Self.encodedToolSummary(summary)
            chatMessages[index].isCollapsed = false
        }
        await persistSessionMessagePart(
            sessionID: sessionID,
            messageID: messageID,
            role: .tool,
            kind: "fileChanges",
            text: Self.encodedToolSummary(summary))
    }

    private static func fileChangeSummary(
        changes: [ToolFileChange],
        diffFiles: [DiffFile]
    ) -> ChatToolSummaryViewState {
        let uniqueChanges = changes.reduce(into: [String: ToolFileChange]()) { partial, change in
            partial[change.path] = change
        }
        let files = uniqueChanges.values
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
            .map { change in
                let diff = diffFiles.first { file in
                    file.newPath == change.path || file.oldPath == change.path || file.id == change.path
                }
                return ChangedFileSummaryViewState(
                    path: change.path,
                    operation: change.operation.rawValue,
                    additions: diff?.additions,
                    deletions: diff?.deletions)
            }
        let operation = files.allSatisfy { $0.operation == ToolFileChange.Operation.created.rawValue }
            ? "Created"
            : "Edited"
        let fileLabel = files.count == 1 ? "file" : "files"
        let additions = files.compactMap(\.additions).reduce(0, +)
        let deletions = files.compactMap(\.deletions).reduce(0, +)
        let hasStats = files.contains { $0.additions != nil || $0.deletions != nil }
        let snapshotID = Self.summarySnapshotID(changes)
        return ChatToolSummaryViewState(
            title: "\(operation) \(files.count) \(fileLabel)",
            subtitle: hasStats ? "+\(additions) -\(deletions)" : nil,
            files: files,
            snapshotID: snapshotID,
            canReview: true,
            canUndo: snapshotID != nil)
    }

    private static func summarySnapshotID(_ changes: [ToolFileChange]) -> String? {
        let ids = Set(changes.compactMap(\.snapshotID).filter { !$0.isEmpty })
        return ids.count == 1 ? ids.first : nil
    }

    private static func encodedToolSummary(_ summary: ChatToolSummaryViewState) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(summary),
              let text = String(data: data, encoding: .utf8) else {
            return summary.title
        }
        return text
    }

    private static func decodedToolSummary(_ text: String) -> ChatToolSummaryViewState? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ChatToolSummaryViewState.self, from: data)
    }

    @discardableResult
    private func appendTranscriptError(_ text: String) -> UUID {
        let id = UUID()
        chatMessages.append(.init(id: id, role: .error, text: text))
        trimChatTranscript()
        return id
    }

    private func workspaceChatObservations(environment: WorkspaceEnvironment, prompt: String) async -> [String] {
        var observations: [String] = []
        let root = environment.root
        observations.append("Current workspace folder: \(root.lastPathComponent)")
        observations.append("Current workspace path: \(root.path)")
        observations.append("Git summary: \(gitSummary)")
        if let selectedFilePath {
            observations.append("Selected file: \(selectedFilePath)")
        }
        let topLevel = fileTree
            .prefix(24)
            .map { $0.isDirectory ? "\($0.name)/" : $0.name }
            .joined(separator: ", ")
        if !topLevel.isEmpty {
            observations.append("Top-level workspace entries: \(topLevel)")
        }

        let snippetLimit = max(600, min(ResourceBudget.resolved(for: settings.resourceProfile).maxSnippetCharacters, 1_200))
        let candidatePaths = workspaceSummaryCandidatePaths()
        var snippets: [String] = []
        for path in candidatePaths {
            guard snippets.count < 4 else { break }
            guard let preview = try? await environment.previewFile(path),
                  preview.kind == .text else { continue }
            let text = preview.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            snippets.append("""
            \(path):
            \(String(text.prefix(snippetLimit)))
            """)
        }
        if !snippets.isEmpty {
            observations.append("Project summary files:\n" + snippets.joined(separator: "\n\n"))
        }
        if let instructions = workspaceInstructionObservation(
            root: root,
            selectedPath: selectedFilePath,
            maxBytes: max(4_000, min(ResourceBudget.resolved(for: settings.resourceProfile).maxContextCharacters, 32_000))
        ) {
            observations.append(instructions)
        }
        observations.append(contentsOf: await promptExpansionObservations(
            prompt: prompt,
            environment: environment,
            flattenedFileTree: flattenFileTree(fileTree),
            snippetLimit: snippetLimit))
        return observations
    }

    private static func codeModeToolFirstObservation(selectedFilePath: String?) -> String {
        var lines = [
            "Code mode file-change contract:",
            "- For file creation or editing requests, use native write_file, edit_file, or apply_patch tools when available.",
            "- Use explicit paths from the latest request first.",
            "- Prefer mentioned @file/@dir context or the selected file/directory when it is relevant.",
            "- Inspect the workspace tree and conventional folders such as src, public, scripts, Tests, Sources, package roots, or app-specific directories before choosing a path.",
            "- For a simple standalone script with no better target, create a descriptive file at the workspace root, for example temperature-converter.html.",
            "- If multiple target folders are plausible, use the question tool instead of guessing.",
            "- After successful writes, answer concisely with changed files, what was done, validation status, and the next useful action. Do not paste full file contents unless explicitly asked.",
            "- If write tools are unavailable, denied, or unsupported by the selected model/tool-call format, do not claim anything was saved; explain the blocker.",
            "The latest request is authoritative."
        ]
        if let selectedFilePath {
            lines.insert("- Current selected path: \(selectedFilePath)", at: 4)
        }
        return lines.joined(separator: "\n")
    }

    private func workspaceInstructionObservation(
        root: URL,
        selectedPath: String?,
        maxBytes: Int
    ) -> String? {
        do {
            let instructions = try InstructionDiscovery(root: root, maxInstructionBytes: maxBytes)
                .discover(for: selectedPath)
                .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            guard !instructions.isEmpty else { return nil }
            let rendered = instructions.map { instruction in
                let suffix = instruction.isTruncated ? "\n[truncated]" : ""
                return """
                \(instruction.relativePath):
                \(instruction.text.trimmingCharacters(in: .whitespacesAndNewlines))\(suffix)
                """
            }
            return "Workspace instructions:\n" + rendered.joined(separator: "\n\n")
        } catch {
            return "Workspace instruction discovery failed: \(error)"
        }
    }

    private func promptExpansionObservations(
        prompt: String,
        environment: WorkspaceEnvironment,
        flattenedFileTree: [FileTreeNode],
        snippetLimit: Int
    ) async -> [String] {
        let resolver = PromptExpansionResolver(
            readFile: { path, maxCharacters in
                guard let preview = try? await environment.previewFile(path),
                      preview.kind == .text else {
                    return nil
                }
                return String(preview.text.prefix(maxCharacters))
            },
            listDirectory: { path, limit in
                let normalized = path.trimmingCharacters(in: .whitespacesAndNewlines)
                let prefix = normalized.isEmpty || normalized == "."
                    ? ""
                    : (normalized.hasSuffix("/") ? normalized : normalized + "/")
                return flattenedFileTree
                    .filter { node in
                        if prefix.isEmpty {
                            return !node.path.contains("/")
                        }
                        guard node.path.hasPrefix(prefix) else { return false }
                        let suffix = node.path.dropFirst(prefix.count)
                        return !suffix.isEmpty && !suffix.contains("/")
                    }
                    .prefix(max(0, limit))
                    .map { node in node.isDirectory ? "\(node.path)/" : node.path }
            })
        let expansion = await PromptExpander(
            resolver: resolver,
            options: PromptExpansionOptions(
                maxMentionCharacters: snippetLimit,
                maxDirectoryEntries: 64,
                maxContextCharacters: max(snippetLimit * 4, snippetLimit))
        ).expand(prompt: prompt)

        var observations: [String] = []
        if !expansion.renderedContext.isEmpty {
            observations.append("Prompt references:\n" + expansion.renderedContext)
        }
        if !expansion.diagnostics.isEmpty {
            observations.append("Prompt expansion diagnostics: " + expansion.diagnostics.joined(separator: "; "))
        }
        if expansion.isTruncated {
            observations.append("Prompt expansion was truncated to the active resource budget.")
        }
        return observations
    }

    private func workspaceSummaryCandidatePaths() -> [String] {
        let preferred = [
            "README.md",
            "Package.swift",
            "ARCHITECTURE.md",
            "DESIGN_HANDOFF.md",
            "pyproject.toml",
            "package.json",
            "Cargo.toml",
            "go.mod",
        ]
        let knownPaths = Set(flattenFileTree(fileTree).map(\.path))
        let existingPreferred = preferred.filter { knownPaths.contains($0) }
        if !existingPreferred.isEmpty {
            return existingPreferred
        }
        return flattenFileTree(fileTree)
            .filter { !$0.isDirectory }
            .prefix(4)
            .map(\.path)
    }

    private func flattenFileTree(_ nodes: [FileTreeNode]) -> [FileTreeNode] {
        var result: [FileTreeNode] = []
        func walk(_ node: FileTreeNode) {
            result.append(node)
            for child in node.children {
                walk(child)
            }
        }
        for node in nodes {
            walk(node)
        }
        return result
    }

    private func estimatedContextWindowUsage() -> (label: String, fraction: Double) {
        let signature = contextUsageSignature()
        if let cache = contextUsageCache, cache.signature == signature {
            return cache.value
        }
        let mode = visibleConversationMode
        let role: ModelRole = settings.usesSingleAgentMode() ? .orchestrator : (mode == .chat ? .utility : .orchestrator)
        let tokenBudget = effectiveContextTokenCap(isPlainChat: mode == .chat, role: role)
        let tokenEstimate = estimatedContextTokens(
            messages: chatMessages,
            draft: chatDraft)
        let fraction = min(max(Double(tokenEstimate) / Double(max(1, tokenBudget)), 0), 1)
        let value = (Self.formatContextUsageLabel(fraction), fraction)
        contextUsageCache = (signature, value)
        return value
    }

    /// Returns the filtered tree + visible rows, recomputing only when the tree
    /// version, filter, or expansion set changed — never on token flushes.
    private func fileTreeDerivations() -> (filtered: [FileTreeNode], rows: [FileTreeVisibleRow]) {
        if let cache = treeDerivationCache,
           cache.version == fileTreeVersion,
           cache.filter == fileTreeFilter,
           cache.expanded == expandedFileTreePaths {
            return (cache.filtered, cache.rows)
        }
        let filtered = FileTreeNode.filtered(nodes: fileTree, query: fileTreeFilter)
        let rows = FileTreeModel.visibleRows(
            nodes: fileTree,
            expandedPaths: expandedFileTreePaths,
            filter: fileTreeFilter)
        treeDerivationCache = (fileTreeVersion, fileTreeFilter, expandedFileTreePaths, filtered, rows)
        return (filtered, rows)
    }

    /// Cheap signature for the context-usage memo. O(messageCount) — `utf8.count`
    /// is O(1) — and excludes streaming messages, so it stays constant while a
    /// message streams (the estimate ignores in-flight messages anyway).
    private func contextUsageSignature() -> Int {
        var hasher = Hasher()
        hasher.combine(chatMessages.count)
        for message in chatMessages where !message.isStreaming {
            hasher.combine(message.id)
            hasher.combine(message.text.utf8.count)
        }
        let isPlainChat = visibleConversationMode == .chat
        hasher.combine(chatDraft)
        hasher.combine(isPlainChat)
        hasher.combine(effectiveContextTokenCap(isPlainChat: isPlainChat))
        hasher.combine(modelContextSettings.conversationContextMode(isPlainChat: isPlainChat))
        return hasher.finalize()
    }

    private func estimatedContextTokens(
        messages: [ChatMessageViewState],
        draft: String
    ) -> Int {
        let trimmedDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let transcriptCharacters = estimatedConversationContextCharacters(for: trimmedDraft)
        let draftCharacters = trimmedDraft.count
        let messageCount = (transcriptCharacters > 0 ? messages.filter { !$0.isToolEvent }.count : 0)
            + (trimmedDraft.isEmpty ? 0 : 1)
        let messageOverhead = max(0, messageCount) * 8
        // Conservative ~3.3 chars/token for code-heavy text. This meter is a UI
        // estimate only; the enforced budget is the tokenizer-true fitting in the
        // agent loop (AgentContextFitter).
        return Int(ceil(Double(transcriptCharacters + draftCharacters) / 3.3)) + messageOverhead
    }

    private func estimatedConversationContextCharacters(for promptText: String) -> Int {
        let isPlainChat = visibleConversationMode == .chat
        let mode = modelContextSettings.conversationContextMode(isPlainChat: isPlainChat)
        guard ConversationContextBuilder.isLikelyContextDependent(promptText) || mode == .smart else { return 0 }
        let cap = effectiveContextTokenCap(isPlainChat: isPlainChat)
        let tokenLimit: Int
        switch mode {
        case .simple:
            tokenLimit = min(1_600, max(128, cap / 5))
        case .smart:
            tokenLimit = isPlainChat
                ? min(2_000, max(256, cap / 4))
                : min(4_000, max(512, Int(Double(cap) * 0.35)))
        }
        return min(estimatedVisibleTranscriptCharacters(), tokenLimit * 4)
    }

    private func estimatedVisibleTranscriptCharacters() -> Int {
        chatMessages.compactMap { message -> String? in
            guard !message.isStreaming else { return nil }
            let trimmed = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            switch message.role {
            case .user:
                return "User: \(trimmed)"
            case .assistant:
                return "Assistant: \(trimmed)"
            default:
                return nil
            }
        }
        .joined(separator: "\n\n")
        .count
    }

    private func effectiveContextTokenCap(
        isPlainChat: Bool,
        role explicitRole: ModelRole? = nil
    ) -> Int {
        let budget = ResourceBudget.resolved(for: settings.resourceProfile)
        let role = explicitRole ?? (settings.usesSingleAgentMode() ? .orchestrator : (isPlainChat ? .utility : .orchestrator))
        let profileTokenBudget = budget.contextTokenBudget(for: role)
            ?? budget.contextTokenBudget(for: .orchestrator)
        return [
            modelContextSettings.contextTokenBudgetOverride(isPlainChat: isPlainChat),
            profileTokenBudget,
        ].compactMap(\.self).min() ?? max(1, profileTokenBudget ?? 1)
    }

    private func conversationContextBundle(
        prompt: String,
        sessionID: UUID?,
        isPlainChat: Bool,
        environment: WorkspaceEnvironment?
    ) async -> ConversationContextBundle {
        let requestedMode = modelContextSettings.conversationContextMode(isPlainChat: isPlainChat)
        guard let sessionStore else {
            return transientConversationContextBundle(
                prompt: prompt,
                requestedMode: requestedMode,
                isPlainChat: isPlainChat)
        }
        let builder = Self.conversationContextBuilder(sessionStore: sessionStore, environment: environment)
        return await builder.build(request: ConversationContextRequest(
            sessionID: sessionID,
            prompt: prompt,
            mode: requestedMode,
            isPlainChat: isPlainChat,
            effectiveContextTokenCap: effectiveContextTokenCap(isPlainChat: isPlainChat)))
    }

    private func transientConversationContextBundle(
        prompt: String,
        requestedMode: ConversationContextMode,
        isPlainChat: Bool
    ) -> ConversationContextBundle {
        let effectiveMode: EffectiveConversationContextMode = requestedMode == .smart ? .smartDegraded : .simple
        var observations = ["Conversation context mode: \(effectiveMode.rawValue)"]
        guard ConversationContextBuilder.isLikelyContextDependent(prompt) else {
            return ConversationContextBundle(
                requestedMode: requestedMode,
                effectiveMode: effectiveMode,
                observations: observations,
                diagnostics: ["reason": "no-session-store-standalone"])
        }
        let cap = effectiveContextTokenCap(isPlainChat: isPlainChat)
        let tokenLimit = min(1_600, max(128, cap / 5))
        let rows = boundedVisibleTranscriptRows(prompt: prompt, tokenLimit: tokenLimit)
        if !rows.isEmpty {
            observations.append("Relevant prior conversation (background only; ignore if unrelated to the latest request):\n"
                + rows.joined(separator: "\n\n"))
        }
        return ConversationContextBundle(
            requestedMode: requestedMode,
            effectiveMode: effectiveMode,
            observations: observations,
            estimatedTokens: Int(ceil(Double(rows.joined(separator: "\n\n").count) / 4.0)),
            diagnostics: ["reason": "no-session-store-transient"])
    }

    private func boundedVisibleTranscriptRows(prompt: String, tokenLimit: Int) -> [String] {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        var skippedCurrentUser = false
        let candidates = chatMessages.reversed().compactMap { message -> String? in
            guard !message.isStreaming else { return nil }
            let trimmed = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            if !skippedCurrentUser, message.role == .user, trimmed == trimmedPrompt {
                skippedCurrentUser = true
                return nil
            }
            switch message.role {
            case .user:
                return "User: \(trimmed)"
            case .assistant:
                return "Assistant: \(Self.finalMessageText(trimmed, reasoningEffort: message.reasoningEffort))"
            default:
                return nil
            }
        }
        guard tokenLimit > 0 else { return [] }
        var selected: [String] = []
        var used = 0
        for row in candidates {
            let tokens = max(1, Int(ceil(Double(row.count) / 4.0)))
            if used + tokens <= tokenLimit {
                selected.append(row)
                used += tokens
                continue
            }
            break
        }
        return selected.reversed()
    }

    /// Compact checklist of the agent's own open todos, token-capped.
    private func openTodosObservation(sessionID: UUID?) async -> String? {
        guard let sessionStore, let sessionID,
              let todos = try? await sessionStore.todos(sessionID: sessionID) else { return nil }
        let open = todos.filter { $0.status == .pending || $0.status == .inProgress }
        guard !open.isEmpty else { return nil }
        let lines = open.prefix(20).map { todo in
            "- [\(todo.status == .inProgress ? "~" : " ")] \(todo.title)"
        }
        return "Current plan (your own open todos — continue them and keep them updated via the todo tool):\n"
            + String(lines.joined(separator: "\n").prefix(1_200))
    }

    private func compactConversationIfNeeded(
        sessionID: UUID?,
        isPlainChat: Bool,
        environment: WorkspaceEnvironment?
    ) async {
        guard let sessionStore, let sessionID else { return }
        // Both modes compact now: simple mode consults the checkpoint too, so
        // history older than the trimmed transcript isn't simply gone.
        let mode = modelContextSettings.conversationContextMode(isPlainChat: isPlainChat)
        let builder = Self.conversationContextBuilder(sessionStore: sessionStore, environment: environment)
        // Abstractive summarization through the local model; the builder degrades
        // to its extractive slice when this returns nil/empty (e.g. no model).
        let runSettings = settings
        let hooks = toolRuntimeHooks(sessionID: sessionID)
        let summarize: @Sendable (String) async -> String? = { joined in
            guard let environment else { return nil }
            let task = AgentTask(
                prompt: "Summarize this conversation history into at most 10 terse bullet points. "
                    + "Preserve decisions, file paths, identifiers, and open tasks. "
                    + "Do not call tools; output only the bullets.\n\n" + joined,
                kind: .summarize,
                maxTokens: 400)
            let stream = await environment.runAgent(task, runSettings, hooks)
            var text: String?
            do {
                for try await event in stream {
                    if case .completed(let result) = event { text = result.text }
                }
            } catch { return nil }
            return text
        }
        await builder.compactIfNeeded(sessionID: sessionID, mode: mode, summarize: summarize)
    }

    private nonisolated static func conversationContextBuilder(
        sessionStore: any SessionRuntimeStore,
        environment: WorkspaceEnvironment?
    ) -> ConversationContextBuilder {
        ConversationContextBuilder(
            loadMessageParts: { sessionID, limit in
                try await sessionStore.messageParts(sessionID: sessionID, limit: limit)
            },
            loadLatestCompaction: { sessionID in
                try await sessionStore.latestCompaction(sessionID: sessionID)
            },
            saveCompaction: { checkpoint in
                try await sessionStore.saveCompaction(checkpoint)
            },
            embedTexts: { texts in
                guard let environment else { return nil }
                return try await environment.embedTexts(texts)
            },
            loadMessageEmbeddings: { sessionID, limit in
                try await sessionStore.messageEmbeddings(sessionID: sessionID, limit: limit)
            },
            loadMessageEmbedding: { partID in
                try await sessionStore.messageEmbedding(partID: partID)
            },
            saveMessageEmbedding: { embedding in
                try await sessionStore.upsertMessageEmbedding(embedding)
            })
    }

    private static func formatContextUsageLabel(_ fraction: Double) -> String {
        let percent = min(max(fraction, 0), 1) * 100
        if percent >= 10 {
            return "\(Int(percent.rounded()))%"
        }
        return String(format: "%.1f%%", percent)
    }

    private func trimChatTranscript() {
        let budget = ResourceBudget.resolved(for: settings.resourceProfile)
        // `utf8.count` is O(1) per String (native storage), so this scan is
        // O(messageCount) rather than O(totalCharacters) of a grapheme `.count`.
        // It slightly over-counts multibyte text, which only trims a touch earlier.
        var total = chatMessages.reduce(0) { $0 + $1.text.utf8.count }
        while total > budget.chatTranscriptRetainedCharacters,
              let first = chatMessages.first,
              !first.isStreaming,
              chatMessages.count > 2 {
            total -= first.text.utf8.count
            chatMessages.removeFirst()
        }

        let toolIDs = chatMessages.filter(\.isToolEvent).map(\.id)
        let excessToolCount = max(0, toolIDs.count - budget.chatToolEventRetainedCount)
        if excessToolCount > 0 {
            let removing = Set(toolIDs.prefix(excessToolCount))
            chatMessages.removeAll { removing.contains($0.id) }
        }
    }

    private func appendNotice(severity: AppNoticeSeverity, title: String, message: String) {
        notices.append(.init(severity: severity, title: title, message: message))
        if notices.count > 5 {
            notices.removeFirst(notices.count - 5)
        }
    }

    private func refreshAvailableChatModels(includeConfigured: Bool) {
        var ids = Self.discoverLocalModelIDs()
        if includeConfigured {
            let configured = settings.orchestratorModelID.trimmingCharacters(in: .whitespacesAndNewlines)
            if !configured.isEmpty, ModelCompatibility.isSupported(configured) {
                ids.insert(configured, at: 0)
            }
        }
        availableChatModelIDs = Self.uniqueNonEmpty(ids)
    }

    private static func discoverLocalModelIDs() -> [String] {
        let fileManager = FileManager.default
        let environment = ProcessInfo.processInfo.environment
        let home = fileManager.homeDirectoryForCurrentUser
        var roots: [URL] = []
        if let hubCache = environment["HF_HUB_CACHE"], !hubCache.isEmpty {
            roots.append(URL(fileURLWithPath: hubCache, isDirectory: true))
        }
        if let hfHome = environment["HF_HOME"], !hfHome.isEmpty {
            roots.append(URL(fileURLWithPath: hfHome, isDirectory: true).appendingPathComponent("hub", isDirectory: true))
        }
        roots.append(home.appendingPathComponent(".cache/huggingface/hub", isDirectory: true))
        roots.append(home.appendingPathComponent("Library/Caches/huggingface/hub", isDirectory: true))

        var ids: [String] = []
        for root in roots {
            guard let entries = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for entry in entries {
                guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
                let name = entry.lastPathComponent
                guard name.hasPrefix("models--") else { continue }
                let parts = name.dropFirst("models--".count).split(separator: "--").map(String.init)
                guard parts.count >= 2 else { continue }
                ids.append(parts.joined(separator: "/"))
            }
        }
        return uniqueNonEmpty(ModelCompatibility.supportedModelIDs(ids)).sorted()
    }

    private static func uniqueNonEmpty(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            result.append(trimmed)
        }
        return result
    }

    private static func quantizationAdvertised(by modelID: String) -> QuantizationLevel? {
        QuantizationLevel.advertisedBits(inRepoID: modelID).flatMap(QuantizationLevel.init(rawValue:))
    }

    private func setActivity(_ activity: WorkspaceActivity) {
        activities.removeAll { $0.kind == activity.kind }
        activities.append(activity)
    }

    private func removeActivity(_ kind: WorkspaceActivityKind) {
        activities.removeAll { $0.kind == kind }
    }

    private func isModelLoadCancellationRequested(_ loadID: UUID) -> Bool {
        cancelledModelLoadIDs.contains(loadID) || activeModelLoadID != loadID || Task.isCancelled
    }

    private func updateModelDownloadProgress(
        loadID: UUID,
        modelID: String,
        role: ModelRole,
        fractionCompleted: Double
    ) {
        guard activeModelLoadID == loadID, modelStatus == .loading else { return }
        modelDownloadProgress = ModelDownloadProgressViewState(
            modelID: modelID,
            roleLabel: role.rawValue,
            fractionCompleted: fractionCompleted)
    }

    private func finishModelLoadRun(_ loadID: UUID) {
        guard activeModelLoadID == loadID else {
            cancelledModelLoadIDs.remove(loadID)
            return
        }
        activeModelLoadID = nil
        cancelledModelLoadIDs.remove(loadID)
        modelLoadTask = nil
        modelDownloadProgress = nil
        removeActivity(.modelLoading)
    }

    private func completeCancelledModelLoad(
        _ loadID: UUID,
        taskID: UUID,
        recovery: RecoveryOperationToken?
    ) async {
        let isCurrent = activeModelLoadID == loadID
        if isCurrent {
            modelStatus = .idle
            modelDownloadProgress = nil
        }
        await taskScheduler.finish(id: taskID, status: .cancelled, message: "Cancelled")
        await finishRecovery(recovery, status: .cancelled, message: "Cancelled")
        await recordCancellation(kind: .model, message: "Model loading cancelled")
        if isCurrent {
            finishModelLoadRun(loadID)
        } else {
            cancelledModelLoadIDs.remove(loadID)
        }
    }

    private func cancelWorkspaceTasks() {
        reindexTask?.cancel()
        watchTask?.cancel()
        configWatchTask?.cancel()
        chatTask?.cancel()
        modelLoadTask?.cancel()
        reindexTask = nil
        watchTask = nil
        configWatchTask = nil
        chatTask = nil
        modelLoadTask = nil
        activities.removeAll()
    }

    private var effectiveRuntimeSettings: ModelSettingsViewState {
        RuntimeConfigMapper.resolve(
            config: loadedWorkspaceConfig?.effective,
            settings: settings,
            resourceBudget: ResourceBudget.resolved(for: settings.resourceProfile)).settings
    }

    /// Effective write permission from the resolved tool policy (`.allow`/`.ask`/`.deny`).
    private var effectiveWritePermission: ToolPermissionEffect {
        RuntimeConfigMapper.resolve(
            config: loadedWorkspaceConfig?.effective,
            settings: settings,
            resourceBudget: ResourceBudget.resolved(for: settings.resourceProfile)).toolPolicy.writePermission
    }

    private func publish(_ event: AppEvent) async {
        await eventBus.publish(event)
        // The health snapshot fan-out (events + scheduler + metrics + recovery +
        // memory policy + durable cursors) is expensive and rebuilds the whole
        // health view state. Only do it while the panel is visible — openHealth()
        // refreshes explicitly, so the panel still populates on open. This stops a
        // closed Health panel from forcing a refresh on nearly every operation.
        if isHealthPresented {
            await refreshHealthStatus()
        }
    }

    private func durableEventCursorStates(
        sessionLimit: Int = 5,
        eventLimit: Int = 200
    ) async -> [DurableEventCursorViewState] {
        guard let sessionStore else { return [] }
        do {
            let sessions = try await sessionStore.recentSessions(
                limit: sessionLimit,
                workspacePath: workspaceURL?.path)
            var states: [DurableEventCursorViewState] = []
            for session in sessions {
                let events = try await sessionStore.events(
                    sessionID: session.id,
                    after: nil,
                    limit: eventLimit)
                let streamID = DurableEventCursor.sessionStreamID(session.id)
                states.append(DurableEventCursorViewState(
                    id: streamID,
                    title: session.title,
                    streamID: streamID,
                    sequence: events.last?.sequence ?? 0,
                    replayedEventCount: events.count,
                    isTruncated: events.count >= eventLimit))
            }
            return states
        } catch {
            return []
        }
    }

    private func diagnosticsSessionObservability(
        limit: Int
    ) async -> (cursors: [DurableEventCursor], events: [SessionEvent]) {
        guard let sessionStore else { return ([], []) }
        do {
            let sessions = try await sessionStore.recentSessions(
                limit: max(1, min(10, limit)),
                workspacePath: workspaceURL?.path)
            var cursors: [DurableEventCursor] = []
            var events: [SessionEvent] = []
            for session in sessions {
                let replayed = try await sessionStore.events(
                    sessionID: session.id,
                    after: nil,
                    limit: limit)
                if let last = replayed.last {
                    cursors.append(DurableEventCursor(
                        sessionID: session.id,
                        cursor: last.cursor,
                        updatedAt: last.createdAt))
                }
                events.append(contentsOf: replayed)
            }
            return (cursors.sorted(), Array(events.sorted { $0.createdAt < $1.createdAt }.suffix(limit)))
        } catch {
            return ([], [])
        }
    }

    private func recordDuration(
        _ kind: MetricKind,
        start: ContinuousClock.Instant,
        metadata: [String: String] = [:]
    ) async {
        let duration = start.duration(to: ContinuousClock.now)
        await metricsRecorder.record(.init(kind: kind, unit: .milliseconds, value: duration.milliseconds, metadata: metadata))
        await refreshHealthStatus()
    }

    private func recordFailure(kind: AppEventKind, message: String) async {
        await eventBus.publish(.init(kind: kind, severity: .error, message: message))
        await eventBus.publish(.init(kind: .failure, severity: .error, message: message, metadata: ["source": kind.rawValue]))
        await metricsRecorder.record(.init(kind: .failureCount, unit: .count, value: 1, metadata: ["source": kind.rawValue]))
        await taskScheduler.recordManual(kind: kind.rawValue, title: "\(kind.rawValue) failure", status: .failed, message: message)
        if let operation = recoveryOperationKind(for: kind) {
            _ = try? await recoveryJournal.recordFailure(
                kind: operation,
                title: "\(kind.rawValue) failure",
                message: message,
                metadata: workspaceRecoveryMetadata())
        }
        await refreshHealthStatus()
    }

    private func recordCancellation(kind: AppEventKind, message: String) async {
        await eventBus.publish(.init(kind: kind, severity: .warning, message: message))
        await eventBus.publish(.init(kind: .cancellation, severity: .warning, message: message, metadata: ["source": kind.rawValue]))
        await metricsRecorder.record(.init(kind: .cancellationCount, unit: .count, value: 1, metadata: ["source": kind.rawValue]))
        await taskScheduler.recordManual(kind: kind.rawValue, title: "\(kind.rawValue) cancelled", status: .cancelled, message: message)
        if let operation = recoveryOperationKind(for: kind) {
            await recordRecoveryInstant(
                operation,
                title: "\(kind.rawValue) cancelled",
                status: .cancelled,
                message: message,
                metadata: workspaceRecoveryMetadata())
        }
        await refreshHealthStatus()
    }

    private func beginRecovery(
        _ kind: RecoveryOperationKind,
        title: String,
        metadata: [String: String] = [:]
    ) async -> RecoveryOperationToken? {
        try? await recoveryJournal.beginOperation(kind: kind, title: title, metadata: metadata)
    }

    private func finishRecovery(
        _ token: RecoveryOperationToken?,
        status: RecoveryOperationStatus,
        message: String? = nil
    ) async {
        guard let token else { return }
        try? await recoveryJournal.finishOperation(token, status: status, message: message)
        await refreshHealthStatus()
    }

    private func recordRecoveryInstant(
        _ kind: RecoveryOperationKind,
        title: String,
        status: RecoveryOperationStatus,
        message: String? = nil,
        metadata: [String: String] = [:]
    ) async {
        guard let token = await beginRecovery(kind, title: title, metadata: metadata) else { return }
        await finishRecovery(token, status: status, message: message)
    }

    private func workspaceRecoveryMetadata(_ metadata: [String: String] = [:]) -> [String: String] {
        var result = metadata
        if let workspaceURL {
            result["workspacePath"] = workspaceURL.path
        }
        return result
    }

    private func modelRecoveryMetadata() -> [String: String] {
        var metadata = workspaceRecoveryMetadata()
        metadata["modelRole"] = settings.usesSingleAgentMode() ? "single-agent" : "orchestrator,utility,embeddings"
        let modelIDs = settings.usesSingleAgentMode()
            ? [settings.orchestratorModelID]
            : [settings.orchestratorModelID, settings.utilityModelID, settings.embeddingsModelID]
        metadata["modelID"] = modelIDs
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: ",")
        return metadata
    }

    private func recoveryOperationKind(for kind: AppEventKind) -> RecoveryOperationKind? {
        switch kind {
        case .workspace: return .workspaceOpen
        case .indexing: return .indexing
        case .search: return .search
        case .filePreview: return .filePreview
        case .git: return .gitRefresh
        case .chat: return .chat
        case .model: return .modelLoad
        case .tool: return .toolExecution
        case .patch: return .patchApply
        case .memory, .diagnostics, .task, .failure, .cancellation: return nil
        }
    }

    private func prepareSessionForPrompt(
        _ promptText: String,
        workspacePath: String?,
        mode: ConversationMode
    ) async -> SessionRecord? {
        visibleConversationMode = mode
        guard settings.persistPromptHistory, let sessionStore else {
            currentConversationID = nil
            currentConversationMode = mode
            currentConversationWorkspacePath = workspacePath
            return nil
        }
        do {
            if let currentConversationID,
               currentConversationMode == mode,
               currentConversationWorkspacePath == workspacePath,
               let existing = try await sessionStore.session(id: currentConversationID) {
                return existing
            }
            currentConversationMode = mode
            currentConversationWorkspacePath = workspacePath
            let session = try await sessionStore.createSession(
                id: nil,
                workspacePath: workspacePath,
                title: Self.historyTitle(from: promptText))
            setCurrentSession(session)
            await recordSessionEvent(sessionID: session.id, kind: .created, payload: ["title": session.title])
            await refreshChatThreads()
            return session
        } catch {
            appendNotice(severity: .warning, title: "Session not saved", message: String(describing: error))
            return nil
        }
    }

    private func loadSession(_ session: SessionRecord) async {
        guard let sessionStore else { return }
        do {
            setCurrentSession(session)
            let parts = try await sessionStore.messageParts(sessionID: session.id, limit: 500)
            chatMessages = parts.compactMap(Self.chatMessageViewState)
            // Restoring up to 500 parts can exceed the retained-transcript budget;
            // trim now rather than waiting for the next append to do it.
            trimChatTranscript()
            await refreshSessionRuntimeState(sessionID: session.id)
        } catch {
            appendNotice(severity: .warning, title: "Chat unavailable", message: String(describing: error))
        }
    }

    private func setCurrentSession(_ session: SessionRecord) {
        currentConversationID = session.id
        currentConversationWorkspacePath = session.workspacePath
        currentConversationMode = session.workspacePath == nil ? .chat : .code
        visibleConversationMode = currentConversationMode ?? .code
    }

    private func sessionCanBeShown(_ session: SessionRecord) -> Bool {
        if session.workspacePath == nil {
            return true
        }
        return session.workspacePath == workspaceURL?.path
    }

    private func recentPlainSessions(limit: Int) async throws -> [SessionRecord] {
        guard let sessionStore else { return [] }
        return try await sessionStore.recentSessions(limit: limit * 3, workspacePath: nil)
            .filter { $0.workspacePath == nil }
            .prefix(limit)
            .map { $0 }
    }

    private func persistSessionUserPrompt(
        sessionID: UUID?,
        promptText: String,
        messageID: UUID
    ) async {
        guard settings.persistPromptHistory, let sessionStore, let sessionID else { return }
        do {
            let input = try await sessionStore.admitInput(SessionInputRecord(sessionID: sessionID, prompt: promptText))
            await recordSessionEvent(sessionID: sessionID, kind: .promptAdmitted, messageID: messageID, payload: ["inputID": input.id.uuidString])
            try await sessionStore.markInputPromoted(id: input.id, promotedAt: Date())
            await recordSessionEvent(sessionID: sessionID, kind: .promptPromoted, messageID: messageID, payload: ["inputID": input.id.uuidString])
            await persistSessionMessagePart(sessionID: sessionID, messageID: messageID, role: .user, kind: "text", text: promptText)
        } catch {
            appendNotice(severity: .warning, title: "Session input not saved", message: String(describing: error))
        }
    }

    private func persistSessionAssistantMessage(
        sessionID: UUID?,
        id: UUID,
        fallbackText: String = "",
        role: SessionMessageRole = .assistant,
        kind: String = "text"
    ) async {
        guard settings.persistPromptHistory else { return }
        let message = chatMessages.first(where: { $0.id == id })
        let persistedText = message.map {
            Self.finalMessageText($0.text, reasoningEffort: $0.reasoningEffort)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let text = persistedText?.isEmpty == false ? persistedText! : fallbackText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        await persistSessionMessagePart(
            sessionID: sessionID,
            messageID: id,
            role: role,
            kind: kind,
            text: text,
            modelID: message?.modelID,
            reasoningEffort: message?.reasoningEffort)
    }

    private func persistSessionMessagePart(
        sessionID: UUID?,
        messageID: UUID,
        role: SessionMessageRole,
        kind: String,
        text: String,
        modelID: String? = nil,
        reasoningEffort: ReasoningEffort? = nil
    ) async {
        guard settings.persistPromptHistory, let sessionStore, let sessionID else { return }
        do {
            let part = SessionMessagePart(
                sessionID: sessionID,
                messageID: messageID,
                role: role,
                kind: kind,
                text: text,
                modelID: modelID,
                reasoningEffort: reasoningEffort)
            try await sessionStore.appendMessagePart(part)
            await recordSessionEvent(sessionID: sessionID, kind: .messagePartAppended, messageID: messageID, payload: [
                "role": role.rawValue,
                "kind": kind,
            ])
            let currentEnvironment = environment ?? chatOnlyEnvironment
            let builder = Self.conversationContextBuilder(sessionStore: sessionStore, environment: currentEnvironment)
            // Background embedding/index work runs at .utility so it cannot contend
            // with the .userInitiated token-generation loop.
            Task.detached(priority: .utility) {
                await builder.indexMessagePart(part)
            }
        } catch {
            appendNotice(severity: .warning, title: "Session message not saved", message: String(describing: error))
        }
    }

    private func recordSessionEvent(
        sessionID: UUID?,
        kind: SessionEventKind,
        messageID: UUID? = nil,
        payload: [String: String] = [:]
    ) async {
        guard settings.persistPromptHistory, let sessionStore, let sessionID else { return }
        do {
            let saved = try await sessionStore.appendEvent(SessionEvent(
                sessionID: sessionID,
                kind: kind,
                messageID: messageID,
                payload: payload))
            sessionTimelineItems.insert(Self.timelineItem(from: saved), at: 0)
            if sessionTimelineItems.count > 30 {
                sessionTimelineItems.removeLast(sessionTimelineItems.count - 30)
            }
        } catch {
            appendNotice(severity: .warning, title: "Session event not saved", message: String(describing: error))
        }
    }

    private func interruptSession(_ sessionID: UUID?, reason: String) async {
        guard settings.persistPromptHistory, let sessionStore, let sessionID else { return }
        do {
            try await sessionStore.interrupt(sessionID: sessionID)
            await recordSessionEvent(sessionID: sessionID, kind: .interrupted, payload: ["reason": reason])
        } catch {
            appendNotice(severity: .warning, title: "Session interrupt not saved", message: String(describing: error))
        }
    }

    private func refreshSessionRuntimeState(sessionID: UUID) async {
        guard let sessionStore else { return }
        do {
            let todos = try await sessionStore.todos(sessionID: sessionID)
            todoPanel = TodoPanelViewState(items: todos.map(Self.todoItemViewState))
            let events = try await sessionStore.events(sessionID: sessionID, after: nil, limit: 30)
            sessionTimelineItems = events.reversed().map(Self.timelineItem)
        } catch {
            todoPanel = TodoPanelViewState()
            sessionTimelineItems = []
        }
    }

    private func toolRuntimeHooks(sessionID: UUID?) -> ToolRuntimeHooks {
        ToolRuntimeHooks(
            permissionAuthorizer: { [weak self] request in
                guard let self else { return .deny }
                return await self.authorizeToolPermission(request)
            },
            settlementHandlers: ToolSettlementHandlers(
                updateTodos: { [weak self] items in
                    guard let self else { return Self.todoSummary(items) }
                    return try await self.settleTodos(items, sessionID: sessionID)
                },
                askQuestion: { [weak self] request in
                    guard let self else { throw ToolError.settlementUnavailable("question requires UI") }
                    return try await self.askQuestion(request, sessionID: sessionID)
                },
                scheduleTask: { [weak self] prompt in
                    guard let self else { throw ToolError.settlementUnavailable("task scheduling unavailable") }
                    return try await self.scheduleBackgroundTask(prompt, sessionID: sessionID)
                }))
    }

    private func authorizeToolPermission(_ request: ToolPermissionRequest) async -> ToolPermissionResolution {
        for continuation in permissionContinuations.values {
            continuation.resume(returning: .deny)
        }
        permissionContinuations.removeAll()
        return await withCheckedContinuation { continuation in
            permissionContinuations[request.id] = continuation
            permissionPrompt = PermissionPromptViewState(
                id: request.id,
                title: request.title,
                message: request.message,
                toolName: request.request.displayName,
                risk: permissionRisk(for: request.request))
        }
    }

    private func settleTodos(_ items: [ToolTodoItem], sessionID: UUID?) async throws -> String {
        let viewItems = items.map { item in
            TodoItemViewState(title: item.title, status: Self.todoStatus(item.status))
        }
        todoPanel = TodoPanelViewState(items: viewItems)
        if settings.persistPromptHistory, let sessionStore, let sessionID {
            let records = items.map { item in
                SessionTodo(sessionID: sessionID, title: item.title, status: Self.sessionTodoStatus(item.status))
            }
            try await sessionStore.replaceTodos(records, sessionID: sessionID)
            await recordSessionEvent(sessionID: sessionID, kind: .todoUpdated, payload: ["count": "\(records.count)"])
        }
        return Self.todoSummary(items)
    }

    private func askQuestion(_ request: ToolQuestionRequest, sessionID: UUID?) async throws -> ToolQuestionResponse {
        for continuation in questionContinuations.values {
            continuation.resume(throwing: CancellationError())
        }
        questionContinuations.removeAll()
        await recordSessionEvent(sessionID: sessionID, kind: .toolCallStarted, payload: ["tool": "question"])
        let response = try await withCheckedThrowingContinuation { continuation in
            questionContinuations[request.id] = continuation
            questionPrompt = QuestionPromptViewState(
                id: request.id,
                prompt: request.prompt,
                options: request.options)
        }
        await recordSessionEvent(sessionID: sessionID, kind: .toolCallSettled, payload: ["tool": "question"])
        return response
    }

    private func scheduleBackgroundTask(_ prompt: String, sessionID: UUID?) async throws -> ToolTaskSettlement {
        let jobID = UUID()
        let title = Self.historyTitle(from: prompt).isEmpty ? "Tool task" : Self.historyTitle(from: prompt)
        let job = BackgroundToolJobViewState(
            id: jobID,
            title: title,
            status: .queued,
            detail: prompt,
            canCancel: false)
        backgroundToolJobs.insert(job, at: 0)
        if backgroundToolJobs.count > 20 {
            backgroundToolJobs.removeLast(backgroundToolJobs.count - 20)
        }
        await taskScheduler.recordManual(kind: "tool.task", title: title, status: .completed, message: "Queued by task tool")
        await recordSessionEvent(sessionID: sessionID, kind: .toolCallSettled, payload: [
            "tool": "task",
            "jobID": jobID.uuidString,
            "status": "queued",
        ])
        return ToolTaskSettlement(jobID: jobID, status: "queued", message: "Task was recorded for background handling.")
    }

    private func permissionRisk(for request: ToolRequest) -> String {
        switch request {
        case .writeFile, .editFile, .applyPatch:
            return "writes"
        case .runTests, .shell:
            return "process"
        default:
            return "tool"
        }
    }

    private static func chatMessageViewState(from part: SessionMessagePart) -> ChatMessageViewState? {
        if part.kind == "fileChanges",
           let summary = decodedToolSummary(part.text) {
            return ChatMessageViewState(
                id: part.messageID,
                role: .tool,
                kind: part.kind,
                text: part.text,
                isCollapsed: false,
                timestamp: part.createdAt,
                toolSummary: summary)
        }
        let role: ChatMessageRole
        switch part.role {
        case .system:
            role = .system
        case .user:
            role = .user
        case .assistant:
            role = ["error", "cancelled"].contains(part.kind) ? .error : .assistant
        case .tool:
            role = .tool
        }
        return ChatMessageViewState(
            id: part.messageID,
            role: role,
            kind: part.kind,
            text: part.text,
            isCollapsed: role == .tool || role == .system,
            timestamp: part.createdAt,
            modelID: part.modelID,
            reasoningEffort: part.reasoningEffort)
    }

    private static func todoItemViewState(_ todo: SessionTodo) -> TodoItemViewState {
        TodoItemViewState(id: todo.id, title: todo.title, status: todoStatus(todo.status))
    }

    private static func todoStatus(_ status: ToolTodoItem.Status) -> TodoItemStatus {
        switch status {
        case .pending:
            return .pending
        case .inProgress:
            return .inProgress
        case .completed:
            return .completed
        }
    }

    private static func todoStatus(_ status: SessionTodo.Status) -> TodoItemStatus {
        switch status {
        case .pending:
            return .pending
        case .inProgress:
            return .inProgress
        case .completed:
            return .completed
        case .cancelled:
            return .pending
        }
    }

    private static func sessionTodoStatus(_ status: ToolTodoItem.Status) -> SessionTodo.Status {
        switch status {
        case .pending:
            return .pending
        case .inProgress:
            return .inProgress
        case .completed:
            return .completed
        }
    }

    nonisolated private static func todoSummary(_ items: [ToolTodoItem]) -> String {
        items.enumerated().map { index, item in
            "\(index + 1). [\(item.status.rawValue)] \(item.title)"
        }.joined(separator: "\n")
    }

    private static func timelineItem(from event: SessionEvent) -> SessionTimelineItemViewState {
        SessionTimelineItemViewState(
            id: event.id,
            title: event.kind.rawValue,
            detail: event.payload
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: " "),
            createdAt: event.createdAt,
            severity: timelineSeverity(event.kind))
    }

    private static func timelineSeverity(_ kind: SessionEventKind) -> AppNoticeSeverity {
        switch kind {
        case .failed:
            return .error
        case .interrupted:
            return .warning
        default:
            return .info
        }
    }

    private func persistUserPrompt(
        _ promptText: String,
        workspacePath explicitWorkspacePath: String? = nil,
        usesCurrentWorkspace: Bool = true
    ) async {
        guard settings.persistPromptHistory, let appStore else { return }
        do {
            let mode: ConversationMode = usesCurrentWorkspace ? .code : .chat
            let workspacePath = usesCurrentWorkspace ? (explicitWorkspacePath ?? workspaceURL?.path) : explicitWorkspacePath
            try await appStore.recordPrompt(promptText, workspacePath: workspacePath, mode: mode)
            let conversationID = try await ensureConversation(for: promptText, workspacePath: workspacePath, mode: mode)
            try await appStore.appendMessage(conversationID: conversationID, role: ChatMessageRole.user.rawValue, text: promptText, createdAt: Date())
            await refreshChatThreads()
        } catch {
            appendNotice(severity: .warning, title: "History not saved", message: String(describing: error))
        }
    }

    private func persistAssistantMessage(
        id: UUID,
        fallbackText: String = "",
        role: ChatMessageRole = .assistant
    ) async {
        guard settings.persistPromptHistory, let appStore, let currentConversationID else { return }
        let persistedText = chatMessages.first(where: { $0.id == id })?.text
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let text = persistedText?.isEmpty == false ? persistedText! : fallbackText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            let speed = chatMessages.first(where: { $0.id == id })?.tokensPerSecond
            try await appStore.appendMessage(
                conversationID: currentConversationID,
                role: role.rawValue,
                text: text,
                createdAt: Date(),
                tokensPerSecond: speed)
            await refreshChatThreads()
        } catch {
            appendNotice(severity: .warning, title: "History not saved", message: String(describing: error))
        }
    }

    private func chatMessageViewState(from message: PersistedConversationMessage) -> ChatMessageViewState? {
        guard let role = ChatMessageRole(rawValue: message.role) else { return nil }
        return ChatMessageViewState(
            role: role,
            text: message.text,
            isCollapsed: role == .tool,
            timestamp: message.createdAt,
            tokensPerSecond: message.tokensPerSecond)
    }

    private func ensureConversation(for promptText: String, workspacePath: String?, mode: ConversationMode) async throws -> UUID {
        visibleConversationMode = mode
        if let currentConversationID,
           currentConversationMode == mode,
           currentConversationWorkspacePath == workspacePath {
            return currentConversationID
        }
        let title = Self.historyTitle(from: promptText)
        let id = try await appStore?.createConversation(title: title, workspacePath: workspacePath, mode: mode) ?? UUID()
        currentConversationID = id
        currentConversationMode = mode
        currentConversationWorkspacePath = workspacePath
        return id
    }

    private func persistModelAssignments() async {
        guard let appStore else { return }
        do {
            try await appStore.saveModelAssignment(.init(
                role: ModelRole.orchestrator.rawValue,
                modelID: settings.orchestratorModelID,
                quantization: settings.orchestratorQuantization.bitWidth))
            guard !settings.usesSingleAgentMode() else { return }
            try await appStore.saveModelAssignment(.init(
                role: ModelRole.utility.rawValue,
                modelID: settings.utilityModelID,
                quantization: settings.utilityQuantization.bitWidth))
            if !settings.embeddingsModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try await appStore.saveModelAssignment(.init(
                    role: ModelRole.embeddings.rawValue,
                    modelID: settings.embeddingsModelID,
                    quantization: settings.embeddingsQuantization.bitWidth))
            }
        } catch {
            appendNotice(severity: .warning, title: "Model settings not saved", message: String(describing: error))
        }
    }

    private func restoreModelAssignmentsFromAppStore() async {
        guard let appStore else { return }
        do {
            var updated = settings
            for assignment in try await appStore.modelAssignments() {
                guard let quantization = QuantizationLevel(rawValue: assignment.quantization) else { continue }
                switch ModelRole(rawValue: assignment.role) {
                case .orchestrator:
                    if updated.orchestratorModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        updated.orchestratorModelID = assignment.modelID
                        updated.orchestratorQuantization = quantization
                    }
                case .utility:
                    if updated.utilityModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        updated.utilityModelID = assignment.modelID
                        updated.utilityQuantization = quantization
                    }
                case .embeddings:
                    if updated.embeddingsModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        updated.embeddingsModelID = assignment.modelID
                        updated.embeddingsQuantization = quantization
                    }
                case .none:
                    break
                }
            }
            settings = updated
        } catch {
            appendNotice(severity: .warning, title: "Model settings restore failed", message: String(describing: error))
        }
    }

    private static func historyTitle(from prompt: String) -> String {
        let collapsed = prompt
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        if collapsed.count <= 80 { return collapsed }
        return String(collapsed.prefix(77)) + "..."
    }

    private func scheduleChatThreadsRefresh(includeDraft: Bool = false) {
        Task { await refreshChatThreads(includeDraft: includeDraft) }
    }

    private func refreshChatThreads(includeDraft: Bool = false) async {
        guard settings.persistPromptHistory, let sessionStore else {
            chatThreads = includeDraft ? [.init(title: "New Chat", isSelected: true, isDraft: true, shortcut: "⌘1")] : []
            globalChatThreads = includeDraft ? [.init(title: "New Chat", isSelected: true, isDraft: true, shortcut: "⌘1")] : []
            return
        }
        do {
            let sessions: [SessionRecord]
            if let workspacePath = workspaceURL?.path {
                sessions = try await sessionStore.recentSessions(limit: 12, workspacePath: workspacePath)
            } else {
                sessions = []
            }
            let globalSessions = try await recentPlainSessions(limit: 12)
            refreshChatThreads(from: sessions, includeDraft: includeDraft)
            refreshGlobalChatThreads(from: globalSessions, includeDraft: includeDraft)
        } catch {
            chatThreads = includeDraft ? [.init(title: "New Chat", isSelected: true, isDraft: true, shortcut: "⌘1")] : chatThreads
            globalChatThreads = includeDraft ? [.init(title: "New Chat", isSelected: true, isDraft: true, shortcut: "⌘1")] : globalChatThreads
        }
    }

    private func refreshChatThreads(
        from sessions: [SessionRecord],
        includeDraft: Bool = false
    ) {
        var threads = sessions.enumerated().map { index, session in
            ChatThreadViewState(
                id: session.id,
                title: session.title.isEmpty ? "Untitled Chat" : session.title,
                subtitle: session.updatedAt.formatted(date: .abbreviated, time: .shortened),
                workspacePath: session.workspacePath,
                isSelected: session.id == currentConversationID && currentConversationMode == .code,
                isDraft: false,
                isInterrupted: session.isInterrupted,
                isActiveNow: chatTask != nil && session.id == currentConversationID,
                shortcut: index < 9 ? "⌘\(index + 1)" : nil)
        }
        if includeDraft || currentConversationID == nil {
            threads.insert(.init(title: "New Chat", isSelected: true, isDraft: true, shortcut: "⌘1"), at: 0)
            threads = threads.enumerated().map { index, thread in
                var updated = thread
                updated.shortcut = index < 9 ? "⌘\(index + 1)" : nil
                return updated
            }
        }
        chatThreads = threads
    }

    private func refreshGlobalChatThreads(
        from sessions: [SessionRecord],
        includeDraft: Bool = false
    ) {
        var threads = sessions.enumerated().map { index, session in
            ChatThreadViewState(
                id: session.id,
                title: session.title.isEmpty ? "Untitled Chat" : session.title,
                subtitle: session.updatedAt.formatted(date: .abbreviated, time: .shortened),
                workspacePath: session.workspacePath,
                isSelected: session.id == currentConversationID && currentConversationMode == .chat,
                isDraft: false,
                isInterrupted: session.isInterrupted,
                isActiveNow: chatTask != nil && session.id == currentConversationID,
                shortcut: index < 9 ? "⌘\(index + 1)" : nil)
        }
        if includeDraft || currentConversationID == nil {
            threads.insert(.init(title: "New Chat", isSelected: true, isDraft: true, shortcut: "⌘1"), at: 0)
            threads = threads.enumerated().map { index, thread in
                var updated = thread
                updated.shortcut = index < 9 ? "⌘\(index + 1)" : nil
                return updated
            }
        }
        globalChatThreads = threads
    }

    private func refreshChatThreads(
        from conversations: [PersistedConversation],
        includeDraft: Bool = false
    ) {
        var threads = conversations.enumerated().map { index, conversation in
            ChatThreadViewState(
                id: conversation.id,
                title: conversation.title.isEmpty ? "Untitled Chat" : conversation.title,
                isSelected: conversation.id == currentConversationID && currentConversationMode == .code,
                isDraft: false,
                shortcut: index < 9 ? "⌘\(index + 1)" : nil)
        }
        if includeDraft || currentConversationID == nil {
            threads.insert(.init(title: "New Chat", isSelected: true, isDraft: true, shortcut: "⌘1"), at: 0)
            threads = threads.enumerated().map { index, thread in
                var updated = thread
                updated.shortcut = index < 9 ? "⌘\(index + 1)" : nil
                return updated
            }
        }
        chatThreads = threads
    }

    private func refreshGlobalChatThreads(
        from conversations: [PersistedConversation],
        includeDraft: Bool = false
    ) {
        var threads = conversations.enumerated().map { index, conversation in
            ChatThreadViewState(
                id: conversation.id,
                title: conversation.title.isEmpty ? "Untitled Chat" : conversation.title,
                isSelected: conversation.id == currentConversationID && currentConversationMode == .chat,
                isDraft: false,
                shortcut: index < 9 ? "⌘\(index + 1)" : nil)
        }
        if includeDraft || currentConversationID == nil {
            threads.insert(.init(title: "New Chat", isSelected: true, isDraft: true, shortcut: "⌘1"), at: 0)
            threads = threads.enumerated().map { index, thread in
                var updated = thread
                updated.shortcut = index < 9 ? "⌘\(index + 1)" : nil
                return updated
            }
        }
        globalChatThreads = threads
    }

    private func setCurrentConversation(_ conversation: PersistedConversation) {
        currentConversationID = conversation.id
        currentConversationMode = conversation.mode
        currentConversationWorkspacePath = conversation.workspacePath
        visibleConversationMode = conversation.mode
    }

    private func conversationCanBeShown(_ conversation: PersistedConversation) -> Bool {
        switch conversation.mode {
        case .chat:
            return conversation.workspacePath == nil
        case .code:
            guard let workspacePath = workspaceURL?.path else { return false }
            return conversation.workspacePath == workspacePath
        }
    }

    private func insertDraftChatThread() {
        var threads = chatThreads.filter { !$0.isDraft }
        threads = threads.map { thread in
            var updated = thread
            updated.isSelected = false
            return updated
        }
        threads.insert(.init(title: "New Chat", isSelected: true, isDraft: true), at: 0)
        chatThreads = threads.enumerated().map { index, thread in
            var updated = thread
            updated.shortcut = index < 9 ? "⌘\(index + 1)" : nil
            return updated
        }
    }

    private func insertDraftGlobalChatThread() {
        var threads = globalChatThreads.filter { !$0.isDraft }
        threads = threads.map { thread in
            var updated = thread
            updated.isSelected = false
            return updated
        }
        threads.insert(.init(title: "New Chat", isSelected: true, isDraft: true), at: 0)
        globalChatThreads = threads.enumerated().map { index, thread in
            var updated = thread
            updated.shortcut = index < 9 ? "⌘\(index + 1)" : nil
            return updated
        }
    }

    private func modelRuntimeEnvironment() async throws -> WorkspaceEnvironment {
        if let environment {
            return environment
        }
        if let chatOnlyEnvironment {
            return chatOnlyEnvironment
        }
        let root = Self.chatOnlyRuntimeURL()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let environment = try await factory.makeWorkspaceEnvironment(
            root: root,
            settings: settings,
            metricsRecorder: metricsRecorder,
            eventBus: eventBus,
            config: nil)
        chatOnlyEnvironment = environment
        return environment
    }

    private static func chatOnlyRuntimeURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("Interless", isDirectory: true)
            .appendingPathComponent("ChatRuntime", isDirectory: true)
    }

    private func filteredRecentConversations(limit: Int, mode: ConversationMode) async throws -> [PersistedConversation] {
        guard let appStore else { return [] }
        let workspacePath = workspaceURL?.path
        return try await appStore.recentConversations(limit: limit * 3, mode: mode)
            .filter { conversation in
                guard mode == .code else { return conversation.workspacePath == nil }
                guard let workspacePath else { return false }
                return conversation.workspacePath == workspacePath
            }
            .prefix(limit)
            .map { $0 }
    }

    private func diagnosticsSettings() -> [String: String] {
        [
            "resourceProfile": settings.resourceProfile.rawValue,
            "allowWrites": settings.allowWrites ? "true" : "false",
            "allowNetworkTools": settings.allowNetworkTools ? "true" : "false",
            "persistPromptHistory": settings.persistPromptHistory ? "true" : "false",
            "maxToolIterations": String(settings.maxToolIterations),
            "toolCallFormat": settings.toolCallFormat?.rawValue ?? "auto",
            "orchestratorQuantization": "q\(settings.orchestratorQuantization.bitWidth)",
            "utilityQuantization": "q\(settings.utilityQuantization.bitWidth)",
            "embeddingsQuantization": "q\(settings.embeddingsQuantization.bitWidth)",
            "orchestratorModelID": settings.orchestratorModelID,
            "utilityModelID": settings.utilityModelID,
            "embeddingsModelID": settings.embeddingsModelID,
        ]
    }

    private static func defaultDiagnosticsURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        let stamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        return base
            .appendingPathComponent("Interless/Diagnostics", isDirectory: true)
            .appendingPathComponent("diagnostics-\(stamp).json")
    }

    private static func healthEvent(_ event: AppEvent) -> HealthEventViewState {
        HealthEventViewState(
            id: event.id,
            date: event.date,
            kind: event.kind.rawValue,
            severity: healthSeverity(event.severity),
            message: event.message)
    }

    private static func healthSeverity(_ severity: AppEventSeverity) -> HealthEventSeverity {
        switch severity {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .warning
        case .error: return .error
        }
    }

    private static func healthTask(_ task: TrackedTaskRecord) -> HealthTaskViewState {
        HealthTaskViewState(
            id: task.id,
            title: task.title,
            kind: task.kind,
            status: healthTaskStatus(task.status),
            priority: task.priority.rawValue,
            message: task.message)
    }

    private static func healthTaskStatus(_ status: TrackedTaskStatus) -> HealthTaskStatus {
        switch status {
        case .running: return .running
        case .completed: return .completed
        case .failed: return .failed
        case .cancelled: return .cancelled
        }
    }

    private static func healthMetric(_ summary: MetricSummary) -> HealthMetricViewState {
        HealthMetricViewState(
            kind: summary.kind.rawValue,
            unit: summary.unit.rawValue,
            count: summary.count,
            latest: summary.latest,
            average: summary.average)
    }

    private static func memoryPolicy(_ state: MemoryPolicyState) -> MemoryPolicyViewState {
        MemoryPolicyViewState(
            requestedProfile: state.requestedProfile,
            resolvedProfile: state.resolvedProfile,
            usedFraction: state.usedFraction,
            processBytes: state.snapshot?.footprint.processFootprintBytes ?? 0,
            totalBytes: state.snapshot?.footprint.totalUnifiedBytes ?? 0,
            gpuActiveBytes: state.snapshot?.gpu.activeBytes ?? 0,
            gpuCacheBytes: state.snapshot?.gpu.cacheBytes ?? 0,
            activeActions: state.activeActions)
    }

    private func recoveryItem(_ record: RecoveryJournalRecord) -> RecoveryItemViewState {
        let action = recoveryAction(record)
        return RecoveryItemViewState(
            id: record.id,
            title: record.title,
            operationKind: record.operationKind.rawValue,
            status: record.status.rawValue,
            message: record.message,
            workspacePath: record.metadata["workspacePath"],
            relativePath: record.metadata["relativePath"],
            action: action)
    }

    private func recoveryAction(_ record: RecoveryJournalRecord) -> RecoveryActionViewState {
        let kind = recoveryActionKind(record.actionKind ?? .dismiss)
        return RecoveryActionViewState(kind: kind, disabledReason: recoveryDisabledReason(for: kind, record: record))
    }

    private func recoveryActionKind(_ kind: RecoveryActionKind) -> RecoveryActionViewKind {
        switch kind {
        case .retryWorkspaceOpen: return .retryWorkspaceOpen
        case .retryIndexing: return .retryIndexing
        case .retrySearch: return .retrySearch
        case .retryFilePreview: return .retryFilePreview
        case .retryGitRefresh: return .retryGitRefresh
        case .retryModelLoad: return .retryModelLoad
        case .reviewPatch: return .reviewPatch
        case .openHealth: return .openHealth
        case .dismiss: return .dismiss
        }
    }

    private func recoveryDisabledReason(for action: RecoveryActionViewKind, record: RecoveryJournalRecord) -> String? {
        switch action {
        case .retryWorkspaceOpen:
            return record.metadata["workspacePath"] == nil ? "No workspace path recorded." : nil
        case .retryIndexing, .retryGitRefresh, .reviewPatch:
            return environment == nil ? "Open a workspace first." : nil
        case .retrySearch:
            if environment == nil { return "Open a workspace first." }
            return searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No current search query." : nil
        case .retryFilePreview:
            if environment == nil { return "Open a workspace first." }
            return record.metadata["relativePath"] == nil ? "No file path recorded." : nil
        case .retryModelLoad:
            if environment == nil { return "Open a workspace first." }
            return settings.validationErrors.isEmpty ? nil : settings.validationErrors.joined(separator: " ")
        case .openHealth, .dismiss:
            return nil
        }
    }
}

private extension Duration {
    var milliseconds: Double {
        let components = components
        return Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}
