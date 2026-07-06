import AppCore
import Persistence
import SwiftUI
import UI

@main
struct InterlessApp: App {
    @State private var session: WorkspaceSessionModel

    init() {
        _session = State(initialValue: WorkspaceSessionModel(
            appStore: try? PersistenceBootstrap.liveAppStore(),
            sessionStore: try? PersistenceBootstrap.liveSessionStore(),
            configStore: try? PersistenceBootstrap.liveConfigStore()))
    }

    var body: some Scene {
        WindowGroup("Interless") {
            WorkspaceShell()
                .environment(session)
                .frame(minWidth: 1100, minHeight: 720)
                .ignoresSafeArea(.container, edges: .top)   // content extends under the floating top bar
                .task {
                    await session.loadRecoveryJournalOnLaunch()
                    await session.restoreLastWorkspaceIfNeeded()
                    await session.loadPersistedHistoryOnLaunch()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandMenu("Workspace") {
                Button("Open Workspace…") {
                    sessionOpenWorkspace()
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button("Reindex Workspace") {
                    Task { await session.startFullReindex() }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Button("Refresh Git") {
                    Task { await session.refreshGit() }
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])

                Button("Cancel Active Chat") {
                    session.cancelActiveChat()
                }
                .keyboardShortcut(".", modifiers: [.command])

                Button("Review Current Diff") {
                    Task { await session.loadCurrentDiffForReview() }
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])

                Button("Open Health") {
                    session.isHealthPresented = true
                    Task { await session.refreshHealthStatus() }
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])

                Button("Export Diagnostics…") {
                    sessionExportDiagnostics()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }

            CommandMenu("Models") {
                Button("Open Model Settings") {
                    session.isSettingsPresented = true
                }
                .keyboardShortcut(",", modifiers: [.command])

                Button("Load Models") {
                    Task { await session.loadModels() }
                }

                Button("Unload Models") {
                    Task { await session.unloadModels() }
                }

                Button("Cancel Model Load") {
                    session.cancelModelLoad()
                }
            }
        }
    }

    private func sessionOpenWorkspace() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Workspace"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await session.openWorkspace(url) }
    }

    private func sessionExportDiagnostics() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "interless-diagnostics.json"
        panel.prompt = "Export Diagnostics"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await session.exportDiagnostics(to: url) }
    }
}

private struct WorkspaceShell: View {
    @Environment(WorkspaceSessionModel.self) private var session
    @AppStorage("appearance.mode") private var appearanceModeRaw: String = AppearanceMode.system.rawValue

    private var appearanceMode: AppearanceMode {
        AppearanceMode(rawValue: appearanceModeRaw) ?? .system
    }

    var body: some View {
        @Bindable var session = session
        return WorkspaceView(
            state: session.viewState,
            chatDraft: $session.chatDraft,
            searchQuery: $session.searchQuery,
            fileTreeFilter: $session.fileTreeFilter,
            settings: $session.settings,
            isSettingsPresented: $session.isSettingsPresented,
            isHealthPresented: $session.isHealthPresented,
            actions: WorkspaceViewActions(
                openWorkspace: openWorkspace,
                reindex: { Task { await session.startFullReindex() } },
                selectFile: { path in Task { await session.selectFile(path) } },
                toggleFileTreeDirectory: session.toggleFileTreeDirectory,
                selectSearchHit: { hit in Task { await session.selectSearchHit(hit) } },
                search: { Task { await session.search() } },
                refreshGit: { Task { await session.refreshGit() } },
                startNewChat: { isPlainChat in session.clearChat(plain: isPlainChat) },
                setPlainChatMode: { isPlainChat in Task { await session.setConversationMode(isPlainChat: isPlainChat) } },
                selectChatThread: { id in Task { await session.selectConversation(id) } },
                renameChatThread: { id, title in Task { await session.renameConversation(id, title: title) } },
                sendChat: { Task { await session.runChatPrompt() } },
                sendPlainChat: { Task { await session.runPlainChatPrompt() } },
                cancelChat: { session.cancelActiveChat() },
                focusChat: session.focusChat,
                focusSearch: session.focusSearch,
                openHealth: session.openHealth,
                addChatContextFiles: addChatContextFiles,
                deleteChatThread: { id in Task { await session.deleteConversation(id) } },
                dismissNotice: session.dismissNotice,
                setPatchHunkAccepted: session.setPatchHunkAccepted,
                loadCurrentDiffForReview: { Task { await session.loadCurrentDiffForReview() } },
                applyAcceptedPatch: { Task { await session.applyAcceptedPatch() } },
                discardPatchProposal: session.discardPatchProposal,
                dismissModelOnboarding: session.dismissModelOnboarding,
                applyRecommendedModels: session.applyRecommendedModels,
                loadModels: { Task { await session.loadModels() } },
                unloadModels: { Task { await session.unloadModels() } },
                cancelModelLoad: { session.cancelModelLoad() },
                saveHuggingFaceToken: session.saveHuggingFaceToken,
                deleteHuggingFaceToken: session.deleteHuggingFaceToken,
                saveAnthropicAPIKey: session.saveAnthropicAPIKey,
                deleteAnthropicAPIKey: session.deleteAnthropicAPIKey,
                saveOpenAIAPIKey: session.saveOpenAIAPIKey,
                deleteOpenAIAPIKey: session.deleteOpenAIAPIKey,
                retryRecoveryAction: session.retryRecoveryAction,
                dismissRecoveryItem: session.dismissRecoveryItem,
                clearRecoveryJournal: session.clearRecoveryJournal,
                exportDiagnostics: exportDiagnostics,
                resolvePermissionPrompt: session.resolvePermissionPrompt,
                answerQuestionPrompt: session.answerQuestionPrompt,
                cancelQuestionPrompt: session.cancelQuestionPrompt,
                cancelBackgroundJob: session.cancelBackgroundJob,
                setReasoningEffort: session.setReasoningEffort,
                setModelContextSettings: session.setModelContextSettings,
                revertSnapshot: { snapshotID in Task { await session.revertSnapshot(snapshotID) } }))
        .preferredColorScheme(appearanceMode.colorScheme)
    }

    private func openWorkspace() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Workspace"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await session.openWorkspace(url) }
    }

    private func exportDiagnostics() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "interless-diagnostics.json"
        panel.prompt = "Export Diagnostics"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await session.exportDiagnostics(to: url) }
    }

    private func addChatContextFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add Files"
        panel.message = "Choose workspace files to reference in the chat prompt."
        panel.directoryURL = session.workspaceURL

        guard panel.runModal() == .OK else { return }
        let paths = panel.urls.compactMap { url in
            workspaceRelativePath(for: url) ?? url.lastPathComponent
        }
        guard !paths.isEmpty else { return }

        let insertion = paths
            .map { "- @\($0)" }
            .joined(separator: "\n")
        let prefix = session.chatDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Use these files as context:\n"
            : "\n\nUse these files as context:\n"
        session.chatDraft += prefix + insertion
    }

    private func workspaceRelativePath(for url: URL) -> String? {
        guard let root = session.workspaceURL else { return nil }
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        let filePath = url.standardizedFileURL.resolvingSymlinksInPath().path
        guard filePath == rootPath || filePath.hasPrefix(rootPath + "/") else { return nil }
        return String(filePath.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
