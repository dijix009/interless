import Foundation
import Testing
import Agents
import AppCore
import Core
import Persistence
import Shared
import Tooling
import UI
import Workspace

@MainActor
struct AppCoreTests {
    @Test func preferencesDefaultAndRoundTrip() {
        let defaults = UserDefaults(suiteName: "if-tests-\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
        let preferences = AppPreferences(defaults: defaults)

        #expect(preferences.lastWorkspacePath == nil)
        #expect(preferences.restoreLastWorkspaceOnLaunch)
        #expect(preferences.modelSettings.orchestratorModelID == "")
        #expect(!preferences.modelSettings.allowWrites)
        #expect(preferences.reasoningEffort == .low)
        #expect(preferences.modelContextSettings == ModelContextSettingsViewState())
        #expect(preferences.modelContextSettings.plainChatContextMode == .simple)
        #expect(preferences.modelContextSettings.codeChatContextMode == .smart)

        var settings = ModelSettingsViewState()
        settings.orchestratorModelID = "orch"
        settings.utilityModelID = "util"
        settings.allowWrites = true
        settings.toolCallFormat = .llama3
        settings.resourceProfile = .smallRAM
        preferences.lastWorkspacePath = "/tmp/work"
        preferences.restoreLastWorkspaceOnLaunch = false
        preferences.recentWorkspacePaths = ["/tmp/work", "/tmp/other"]
        preferences.lastSelectedFilePath = "README.md"
        preferences.lastSearchQuery = "readme"
        preferences.layoutPreferences = WorkspaceLayoutPreferences(sidebarWidth: 300, editorWidth: 700, chatWidth: 500)
        preferences.modelSettings = settings
        preferences.reasoningEffort = .high
        preferences.modelContextSettings = ModelContextSettingsViewState(
            plainChatMaxAnswerTokens: 768,
            codeChatMaxAnswerTokens: 1_536,
            plainChatMaxContextWindowTokens: 8_192,
            codeChatMaxContextWindowTokens: 16_384,
            plainChatContextMode: .smart,
            codeChatContextMode: .simple)

        #expect(preferences.lastWorkspacePath == "/tmp/work")
        #expect(!preferences.restoreLastWorkspaceOnLaunch)
        #expect(preferences.recentWorkspacePaths == ["/tmp/work", "/tmp/other"])
        #expect(preferences.lastSelectedFilePath == "README.md")
        #expect(preferences.lastSearchQuery == "readme")
        #expect(preferences.layoutPreferences.sidebarWidth == 300)
        preferences.expandedFileTreePaths = ["Sources", "Tests"]
        preferences.isModelOnboardingDismissed = true
        #expect(preferences.expandedFileTreePaths == Set(["Sources", "Tests"]))
        #expect(preferences.isModelOnboardingDismissed)
        #expect(preferences.modelSettings == settings)
        #expect(preferences.reasoningEffort == .high)
        #expect(preferences.modelContextSettings.plainChatMaxAnswerTokens == 768)
        #expect(preferences.modelContextSettings.codeChatMaxAnswerTokens == 1_536)
        #expect(preferences.modelContextSettings.plainChatMaxContextWindowTokens == 8_192)
        #expect(preferences.modelContextSettings.codeChatMaxContextWindowTokens == 16_384)
        #expect(preferences.modelContextSettings.plainChatContextMode == .smart)
        #expect(preferences.modelContextSettings.codeChatContextMode == .simple)
    }

    @Test func openingWorkspaceDoesNotAutoLoadModels() async {
        let factory = FakeAppDependencyFactory()
        let session = WorkspaceSessionModel(preferences: AppPreferences(defaults: testDefaults()), factory: factory)

        await session.openWorkspace(URL(fileURLWithPath: "/tmp/work"))

        #expect(await factory.makeCount == 1)
        #expect(await factory.loadSettings.isEmpty)
        #expect(session.workspaceURL?.path == "/tmp/work")
        #expect(session.fileTree.map(\.name) == ["README.md"])
        #expect(session.notices.isEmpty)
    }

    @Test func openingWorkspacePassesLoadedAgentConfigToFactory() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try """
        {
          "agents": {
            "general": {
              "system": "Configured runtime prompt.",
              "model": "local-general"
            }
          }
        }
        """.write(to: root.appendingPathComponent("interless.json"), atomically: true, encoding: .utf8)
        let factory = FakeAppDependencyFactory()
        let session = WorkspaceSessionModel(preferences: AppPreferences(defaults: testDefaults()), factory: factory)

        await session.openWorkspace(root)

        let config = try #require(await factory.configs.last ?? nil)
        #expect(config.effective.agents["general"]?.system == "Configured runtime prompt.")
        #expect(config.effective.agents["general"]?.model == "local-general")
    }

    @Test func restoreLastWorkspaceOpensValidPathAndDoesNotLoadModels() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let defaults = testDefaults()
        let preferences = AppPreferences(defaults: defaults)
        preferences.lastWorkspacePath = root.path
        preferences.lastSelectedFilePath = "README.md"
        preferences.lastSearchQuery = "readme"
        let factory = FakeAppDependencyFactory()
        let session = WorkspaceSessionModel(preferences: preferences, factory: factory)

        await session.restoreLastWorkspaceIfNeeded()
        try? await Task.sleep(for: .milliseconds(50))

        #expect(session.workspaceURL?.path == root.path)
        #expect(session.selectedFilePath == "README.md")
        #expect(session.searchQuery == "readme")
        #expect(session.searchHits.map(\.relativePath) == ["README.md"])
        #expect(await factory.loadSettings.isEmpty)
    }

    @Test func missingRestorePathShowsDismissibleNotice() async {
        let preferences = AppPreferences(defaults: testDefaults())
        preferences.lastWorkspacePath = "/tmp/interless-missing-\(UUID().uuidString)"
        let session = WorkspaceSessionModel(preferences: preferences, factory: FakeAppDependencyFactory())

        await session.restoreLastWorkspaceIfNeeded()

        #expect(session.notices.first?.title == "Workspace not restored")
        let id = session.notices[0].id
        session.dismissNotice(id)
        #expect(session.notices.isEmpty)
    }

    @Test func loadModelsPassesSettingsAndUpdatesState() async {
        let factory = FakeAppDependencyFactory()
        let session = WorkspaceSessionModel(preferences: AppPreferences(defaults: testDefaults()), factory: factory)
        session.settings.orchestratorModelID = "orch"
        session.settings.utilityModelID = "util"
        session.settings.allowWrites = true

        await session.openWorkspace(URL(fileURLWithPath: "/tmp/work"))
        await session.loadModels()

        #expect(session.modelStatus == .loaded)
        #expect(session.modelDownloadProgress == nil)
        #expect(await factory.loadSettings.last?.orchestratorModelID == "orch")
        #expect(await factory.loadSettings.last?.allowWrites == true)
    }

    @Test func modelDownloadProgressIsPublishedWhileLoading() async {
        let factory = FakeAppDependencyFactory(longRunningLoad: true)
        let session = WorkspaceSessionModel(preferences: AppPreferences(defaults: testDefaults()), factory: factory)
        session.settings.orchestratorModelID = "orch"
        session.settings.utilityModelID = "util"
        await session.openWorkspace(URL(fileURLWithPath: "/tmp/work"))

        let task = Task { await session.loadModels() }
        let published = await waitUntil {
            session.modelDownloadProgress?.percent == 45
        }
        #expect(published)
        #expect(session.viewState.modelDownloadProgress?.statusText == "Downloading model - 45%")
        session.cancelModelLoad()
        await task.value

        #expect(session.modelDownloadProgress == nil)
    }

    @Test func cancellingModelLoadStopsActivity() async {
        let factory = FakeAppDependencyFactory(longRunningLoad: true)
        let session = WorkspaceSessionModel(preferences: AppPreferences(defaults: testDefaults()), factory: factory)
        session.settings.orchestratorModelID = "orch"
        session.settings.utilityModelID = "util"
        await session.openWorkspace(URL(fileURLWithPath: "/tmp/work"))

        let task = Task { await session.loadModels() }
        let started = await waitUntil {
            session.activities.contains { $0.kind == .modelLoading } || session.modelStatus == .loading
        }
        #expect(started)
        session.cancelModelLoad()
        await task.value

        #expect(!session.activities.contains { $0.kind == .modelLoading })
        #expect(session.modelStatus == .idle)
    }

    @Test func sessionSearchFileSelectionGitAndStreamingChat() async {
        let factory = FakeAppDependencyFactory()
        let session = WorkspaceSessionModel(preferences: AppPreferences(defaults: testDefaults()), factory: factory)
        await session.openWorkspace(URL(fileURLWithPath: "/tmp/work"))

        session.searchQuery = "readme"
        await session.search()
        await session.selectFile("README.md")
        await session.refreshGit()
        await session.runChatPrompt("hello")
        try? await Task.sleep(for: .milliseconds(50))

        #expect(session.searchHits == [SearchHit(relativePath: "README.md", score: 0.1, snippet: "readme")])
        #expect(session.selectedFileText == "contents of README.md")
        #expect(session.selectedFilePreview.kind == .text)
        #expect(session.viewState.gitSummary.contains("main"))
        #expect(session.diffLines.map(\.kind).contains(.addition))
        #expect(session.diffFiles.first?.additions == 1)
        #expect(session.chatMessages.contains { $0.role == .assistant && $0.text == "answer" })
        #expect(session.chatMessages.first { $0.role == .assistant }?.tokensPerSecond == 50)
        #expect(session.chatMessages.contains { $0.role == .tool && $0.text.contains("Started") && $0.isCollapsed })
    }

    @Test func codeChatIncludesWorkspaceContextWithoutRequiringAPath() async throws {
        let factory = FakeAppDependencyFactory()
        let session = WorkspaceSessionModel(preferences: AppPreferences(defaults: testDefaults()), factory: factory)
        await session.openWorkspace(URL(fileURLWithPath: "/tmp/work"))

        await session.runChatPrompt("What is this project?")
        for _ in 0..<100 {
            if await !factory.runTasks.isEmpty { break }
            try? await Task.sleep(for: .milliseconds(10))
        }

        let task = try #require(await factory.runTasks.last)
        #expect(task.observations.contains { $0.contains("Current workspace folder: work") })
        #expect(task.observations.contains { $0.contains("Top-level workspace entries: README.md") })
        #expect(task.observations.contains { $0.contains("README.md:") && $0.contains("contents of README.md") })
        #expect(task.observations.contains { $0.contains("Code mode file-change contract") && $0.contains("write_file") })
        #expect(task.observations.contains { $0.contains("temperature-converter.html") && $0.contains("question tool") })
    }

    @Test func codeChatShowsChangedFileCardAndSanitizesLargeGeneratedFileDump() async throws {
        let longHTML = String(repeating: "<div>temperature converter</div>\n", count: 80)
        let response = """
        I wrote the file.

        ```html
        \(longHTML)
        ```
        """
        let snapshotID = UUID().uuidString
        let factory = FakeAppDependencyFactory(
            responseText: response,
            toolResult: ToolResult(
                request: .writeFile(path: "temperature-converter.html", contents: longHTML),
                stdout: "temperature-converter.html",
                didWrite: true,
                snapshotID: snapshotID,
                fileChanges: [
                    ToolFileChange(path: "temperature-converter.html", operation: .created, snapshotID: snapshotID)
                ]))
        let session = WorkspaceSessionModel(preferences: AppPreferences(defaults: testDefaults()), factory: factory)
        await session.openWorkspace(URL(fileURLWithPath: "/tmp/work"))

        await session.runChatPrompt("Create a simple html temperature converter.")
        for _ in 0..<100 {
            if session.chatMessages.contains(where: { $0.role == .assistant && !$0.isStreaming }) { break }
            try? await Task.sleep(for: .milliseconds(10))
        }

        let summary = try #require(session.chatMessages.first { $0.kind == "fileChanges" }?.toolSummary)
        #expect(summary.title == "Created 1 file")
        #expect(summary.files.map(\.path) == ["temperature-converter.html"])
        #expect(summary.snapshotID == snapshotID)
        #expect(summary.canUndo)
        #expect(summary.canReview)

        let assistant = try #require(session.chatMessages.first { $0.role == .assistant })
        #expect(assistant.text.contains("written to `temperature-converter.html`"))
        #expect(!assistant.text.contains(longHTML.prefix(80)))
    }

    @Test func codeChatWritesGeneratedMarkdownFileWhenModelIgnoresToolCalls() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let response = """
        Sure, here is the file:

        ```html
        <!-- temperature-converter.html -->
        <!DOCTYPE html>
        <html>
        <head>
            <title>Temperature Converter</title>
        </head>
        <body>
            <h1>Temperature Converter</h1>
            <script>
                function convert() {
                    return "converted";
                }
            </script>
        </body>
        </html>
        ```
        """
        let factory = FakeAppDependencyFactory(responseText: response)
        let session = WorkspaceSessionModel(preferences: AppPreferences(defaults: testDefaults()), factory: factory)
        session.settings.allowWrites = true
        await session.openWorkspace(root)

        await session.runChatPrompt("Can you create me a simple .html file that convert C to F and K?")
        for _ in 0..<100 {
            if session.chatMessages.contains(where: { $0.kind == "fileChanges" }),
               session.chatMessages.contains(where: { $0.role == .assistant && !$0.isStreaming }) {
                break
            }
            try? await Task.sleep(for: .milliseconds(10))
        }

        let writtenURL = root.appendingPathComponent("temperature-converter.html")
        #expect(FileManager.default.fileExists(atPath: writtenURL.path))
        let written = try String(contentsOf: writtenURL, encoding: .utf8)
        #expect(written.contains("<!DOCTYPE html>"))
        #expect(!written.contains("temperature-converter.html -->"))
        let summary = try #require(session.chatMessages.first { $0.kind == "fileChanges" }?.toolSummary)
        #expect(summary.title == "Created 1 file")
        #expect(summary.files.map(\.path) == ["temperature-converter.html"])
        let assistant = try #require(session.chatMessages.first { $0.role == .assistant })
        #expect(assistant.text.contains("written to `temperature-converter.html`"))
        #expect(!assistant.text.contains("<!DOCTYPE html>"))
        let executed = await factory.executedToolRequests
        #expect(executed == [.writeFile(path: "temperature-converter.html", contents: written)])
    }

    @Test func codeModeGeneratedFileFallbackExtractsHtmlFilenameComment() throws {
        let response = """
        Sure, here is the file:

        ```html
        <!-- temperature-converter.html -->
        <!DOCTYPE html>
        <html>
        <head><title>Temperature Converter</title></head>
        <body>
            <h1>Temperature Converter</h1>
            <script>
                function convert() { return "converted"; }
            </script>
        </body>
        </html>
        ```
        """

        let candidate = try #require(CodeModeGeneratedFileFallback.candidate(
            prompt: "Can you create me a simple .html file that convert C to F and K?",
            assistantText: response,
            selectedPath: nil))
        #expect(candidate.path == "temperature-converter.html")
        #expect(candidate.contents.contains("<!DOCTYPE html>"))
        #expect(!candidate.contents.contains("temperature-converter.html -->"))
    }

    @Test func codeChatDoesNotAutoWriteGeneratedFileWhenWritesDisabled() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let response = """
        Sure, here is the file:

        ```html
        <!-- temperature-converter.html -->
        <!DOCTYPE html>
        <html><head><title>Temperature Converter</title></head>
        <body><h1>Temperature Converter</h1></body>
        </html>
        ```
        """
        let factory = FakeAppDependencyFactory(responseText: response)
        let session = WorkspaceSessionModel(preferences: AppPreferences(defaults: testDefaults()), factory: factory)
        // writes disabled (default) — the fallback must not fire
        await session.openWorkspace(root)
        await session.runChatPrompt("Can you create me a simple .html file that convert C to F and K?")
        for _ in 0..<100 {
            if session.chatMessages.contains(where: { $0.role == .assistant && !$0.isStreaming }) { break }
            try? await Task.sleep(for: .milliseconds(10))
        }

        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("temperature-converter.html").path))
        #expect(!session.chatMessages.contains { $0.kind == "fileChanges" })
        #expect(await factory.executedToolRequests.isEmpty)
        #expect(session.permissionPrompt == nil)
        // The model's code is still shown (sanitizer doesn't strip when nothing was written).
        let assistant = try #require(session.chatMessages.first { $0.role == .assistant })
        #expect(assistant.text.contains("<!DOCTYPE html>"))
    }

    @Test func sanitizerTreatsInfoBearingInnerFenceAsOneBlock() {
        let text = "Here:\n```markdown\nintro\n```swift\nlet x = 1\n```\nthanks"
        let out = CodeModeFinalAnswerSanitizer.sanitize(
            text,
            fileChanges: [ToolFileChange(path: "a.md", operation: .created, snapshotID: nil)],
            minimumFenceCharacters: 10)
        // The whole fenced block (incl. the inner ```swift) collapses to the
        // reference, not split at the inner fence; trailing prose survives.
        #expect(out.contains("written to `a.md`"))
        #expect(!out.contains("let x = 1"))
        #expect(out.contains("thanks"))
    }

    @Test func codeModeFallbackReturnsNilWithoutAnExplicitPath() {
        // A mutation-like prompt + a >=80-byte code block but NO derivable path
        // (no filename comment, no path in prompt/info, no selected file) must NOT
        // mint a file from prompt keywords.
        let response = """
        Sure, here is an example:

        ```html
        <!DOCTYPE html>
        <html><head><title>Example</title></head>
        <body><h1>Hello world example page</h1></body>
        </html>
        ```
        """
        #expect(CodeModeGeneratedFileFallback.candidate(
            prompt: "Can you write me a simple html page that says hello?",
            assistantText: response,
            selectedPath: nil) == nil)

        // But an explicit path in the prompt still produces a candidate.
        let candidate = CodeModeGeneratedFileFallback.candidate(
            prompt: "Create the file pages/hello.html that says hello",
            assistantText: response,
            selectedPath: nil)
        #expect(candidate?.path == "pages/hello.html")
    }

    @Test func codeModeFinalAnswerSanitizerPreservesChatStyleCodeWhenNoFileWasWritten() {
        let text = """
        ```swift
        print("hello")
        ```
        """

        #expect(CodeModeFinalAnswerSanitizer.sanitize(text, fileChanges: []) == text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @Test func codeChatIncludesWorkspaceInstructionsPromptReferencesAndEpoch() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try "Root instruction".write(to: root.appendingPathComponent("AGENTS.md"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        try "Nested instruction".write(to: root.appendingPathComponent("Sources/AGENTS.md"), atomically: true, encoding: .utf8)
        let factory = FakeAppDependencyFactory()
        let session = WorkspaceSessionModel(preferences: AppPreferences(defaults: testDefaults()), factory: factory)
        await session.openWorkspace(root)
        await session.selectFile("Sources/App.swift")

        await session.runChatPrompt("Summarize @file:README.md")
        for _ in 0..<100 {
            if await !factory.runTasks.isEmpty { break }
            try? await Task.sleep(for: .milliseconds(10))
        }

        let task = try #require(await factory.runTasks.last)
        #expect(task.observations.contains { $0.contains("Workspace instructions:") && $0.contains("Root instruction") && $0.contains("Nested instruction") })
        #expect(task.observations.contains { $0.contains("Prompt references:") && $0.contains("contents of README.md") })
        #expect(task.observations.contains { $0.contains("Context epoch: revision 1") })
    }

    @Test func plainChatRecordsGenerationSpeed() async throws {
        let factory = FakeAppDependencyFactory(completionStopReason: "length")
        let session = WorkspaceSessionModel(preferences: AppPreferences(defaults: testDefaults()), factory: factory)

        await session.runPlainChatPrompt("hello")
        for _ in 0..<100 {
            if session.chatMessages.contains(where: { $0.role == .assistant && !$0.isStreaming }) { break }
            try? await Task.sleep(for: .milliseconds(10))
        }

        let assistant = try #require(session.chatMessages.first { $0.role == .assistant })
        #expect(assistant.text == "answer")
        #expect(assistant.tokensPerSecond == 50)
        #expect(assistant.completionStopReason == "length")
    }

    @Test func modelContextSettingsApplyToPlainAndCodeChatTasks() async throws {
        let factory = FakeAppDependencyFactory()
        let session = WorkspaceSessionModel(preferences: AppPreferences(defaults: testDefaults()), factory: factory)
        session.setModelContextSettings(ModelContextSettingsViewState(
            plainChatMaxAnswerTokens: 640,
            codeChatMaxAnswerTokens: 1_024,
            plainChatMaxContextWindowTokens: 4_096,
            codeChatMaxContextWindowTokens: 8_192))

        await session.runPlainChatPrompt("plain")
        for _ in 0..<100 {
            if await factory.runTasks.count >= 1 { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        let plainTask = try #require(await factory.runTasks.last)

        await session.openWorkspace(URL(fileURLWithPath: "/tmp/work"))
        await session.runChatPrompt("code")
        for _ in 0..<100 {
            if await factory.runTasks.count >= 2 { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        let codeTask = try #require(await factory.runTasks.last)

        #expect(session.viewState.modelContextSettings.plainChatMaxAnswerTokens == 640)
        #expect(plainTask.maxTokens == 640)
        #expect(plainTask.contextTokenBudget == 4_096)
        #expect(codeTask.maxTokens == 1_024)
        #expect(codeTask.contextTokenBudget == 8_192)
    }

    @Test func completedAssistantMessagesTrimTrailingWhitespace() async throws {
        let factory = FakeAppDependencyFactory(responseText: "answer\n\n   \n")
        let session = WorkspaceSessionModel(preferences: AppPreferences(defaults: testDefaults()), factory: factory)

        await session.runPlainChatPrompt("hello")
        for _ in 0..<100 {
            if session.chatMessages.contains(where: { $0.role == .assistant && !$0.isStreaming }) { break }
            try? await Task.sleep(for: .milliseconds(10))
        }

        let assistant = try #require(session.chatMessages.first { $0.role == .assistant })
        #expect(assistant.text == "answer")
    }

    @Test func reasoningEffortClampsWhenSelectedModelDoesNotSupportReasoning() {
        let session = WorkspaceSessionModel(preferences: AppPreferences(defaults: testDefaults()), factory: FakeAppDependencyFactory())
        session.settings.orchestratorModelID = "Qwen/Qwen3-4B-MLX-4bit"
        session.setReasoningEffort(.high)

        #expect(session.viewState.selectedReasoningEffort == .high)
        #expect(session.viewState.reasoningOptions.map(\.effort) == [.none, .low, .medium, .high])

        session.settings.orchestratorModelID = "mlx-community/gemma-2-2b-it-4bit"

        #expect(session.viewState.selectedReasoningEffort == .none)
        #expect(session.viewState.reasoningOptions.map(\.effort) == [.none])
    }

    @Test func plainChatSnapshotsModelAndReasoningForAssistantMessage() async throws {
        let factory = FakeAppDependencyFactory()
        let session = WorkspaceSessionModel(preferences: AppPreferences(defaults: testDefaults()), factory: factory)
        session.settings.orchestratorModelID = "Qwen/Qwen3-4B-MLX-4bit"
        session.setReasoningEffort(.medium)

        await session.runPlainChatPrompt("hello")
        for _ in 0..<100 {
            if session.chatMessages.contains(where: { $0.role == .assistant && !$0.isStreaming }) { break }
            try? await Task.sleep(for: .milliseconds(10))
        }

        let assistant = try #require(session.chatMessages.first { $0.role == .assistant })
        #expect(assistant.modelID == "Qwen/Qwen3-4B-MLX-4bit")
        #expect(assistant.reasoningEffort == .medium)
        let task = try #require(await factory.runTasks.last)
        #expect(task.reasoningEffort == .medium)
        #expect(task.observations.contains { $0.contains("Reasoning preference: medium") })
    }

    @Test func plainChatReasoningNoneStripsQwenThinkBlocks() async throws {
        let factory = FakeAppDependencyFactory(responseText: "<think>\nhidden reasoning\n</think>\n\nVisible answer")
        let session = WorkspaceSessionModel(preferences: AppPreferences(defaults: testDefaults()), factory: factory)
        session.settings.orchestratorModelID = "Qwen/Qwen3-4B-MLX-4bit"
        session.setReasoningEffort(.none)

        await session.runPlainChatPrompt("hello")
        for _ in 0..<100 {
            if session.chatMessages.contains(where: { $0.role == .assistant && !$0.isStreaming }) { break }
            try? await Task.sleep(for: .milliseconds(10))
        }

        let assistant = try #require(session.chatMessages.first { $0.role == .assistant })
        #expect(assistant.text == "Visible answer")
        #expect(assistant.reasoningEffort == ReasoningEffort.none)
        let task = try #require(await factory.runTasks.last)
        #expect(task.observations.contains { $0.contains("/no_think") })
    }

    @Test func plainChatCarriesPriorTurnsIntoNextPrompt() async throws {
        let factory = FakeAppDependencyFactory()
        let session = WorkspaceSessionModel(preferences: AppPreferences(defaults: testDefaults()), factory: factory)

        await session.runPlainChatPrompt("Tell me a story about Priscilla.")
        for _ in 0..<100 {
            if session.chatMessages.contains(where: { $0.role == .assistant && !$0.isStreaming }) { break }
            try? await Task.sleep(for: .milliseconds(10))
        }

        await session.runPlainChatPrompt("Tell me more about her.")
        for _ in 0..<100 {
            if await factory.runTasks.count >= 2 { break }
            try? await Task.sleep(for: .milliseconds(10))
        }

        let task = try #require(await factory.runTasks.last)
        #expect(task.observations.contains("Conversation context mode: simple"))
        let transcript = try #require(task.observations.first { $0.contains("Relevant prior conversation") })
        #expect(transcript.contains("User: Tell me a story about Priscilla."))
        #expect(transcript.contains("Assistant: answer"))
    }

    @Test func plainChatStandaloneGreetingDoesNotCarryPriorTurns() async throws {
        let factory = FakeAppDependencyFactory()
        let session = WorkspaceSessionModel(preferences: AppPreferences(defaults: testDefaults()), factory: factory)

        await session.runPlainChatPrompt("Tell me a story about Finley.")
        for _ in 0..<100 {
            if await factory.runTasks.count >= 1 { break }
            try? await Task.sleep(for: .milliseconds(10))
        }

        await session.runPlainChatPrompt("Hello?")
        for _ in 0..<100 {
            if await factory.runTasks.count >= 2 { break }
            try? await Task.sleep(for: .milliseconds(10))
        }

        let task = try #require(await factory.runTasks.last)
        #expect(task.observations.contains("Conversation context mode: simple"))
        #expect(!task.observations.contains { $0.contains("Relevant prior conversation") })
    }

    @Test func plainChatComplexNewTopicDoesNotCarryPriorTurns() async throws {
        let factory = FakeAppDependencyFactory()
        let session = WorkspaceSessionModel(preferences: AppPreferences(defaults: testDefaults()), factory: factory)

        await session.runPlainChatPrompt("Tell me a story about Finley.")
        for _ in 0..<100 {
            if await factory.runTasks.count >= 1 { break }
            try? await Task.sleep(for: .milliseconds(10))
        }

        await session.runPlainChatPrompt("Write a Python script that sorts CSV files.")
        for _ in 0..<100 {
            if await factory.runTasks.count >= 2 { break }
            try? await Task.sleep(for: .milliseconds(10))
        }

        let task = try #require(await factory.runTasks.last)
        #expect(task.observations.contains("Conversation context mode: simple"))
        #expect(!task.observations.contains { $0.contains("Relevant prior conversation") })
        #expect(!task.observations.contains { $0.contains("Finley") })
    }

    @Test func codeChatStandaloneGreetingDoesNotCarryPriorTurns() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let factory = FakeAppDependencyFactory()
        let session = WorkspaceSessionModel(preferences: AppPreferences(defaults: testDefaults()), factory: factory)
        await session.openWorkspace(root)

        await session.runChatPrompt("Explain this workspace.")
        for _ in 0..<100 {
            if await factory.runTasks.count >= 1 { break }
            try? await Task.sleep(for: .milliseconds(10))
        }

        await session.runChatPrompt("Hello?")
        for _ in 0..<100 {
            if await factory.runTasks.count >= 2 { break }
            try? await Task.sleep(for: .milliseconds(10))
        }

        let task = try #require(await factory.runTasks.last)
        #expect(task.observations.contains("Conversation context mode: smartDegraded"))
        #expect(!task.observations.contains { $0.contains("Relevant prior conversation") })
    }

    @Test func contextWindowUsageReflectsDraftContent() {
        let session = WorkspaceSessionModel(preferences: AppPreferences(defaults: testDefaults()), factory: FakeAppDependencyFactory())
        session.settings.resourceProfile = .smallRAM
        session.chatDraft = String(repeating: "context ", count: 120)

        let chrome = session.viewState.chrome
        #expect((chrome.contextUsageFraction ?? 0) > 0)
        #expect(chrome.contextUsageLabel != "0.0%")
    }

    @Test func sessionPersistsAndRestoresLocalChatHistory() async throws {
        let sessionStore = try PersistenceBootstrap.inMemorySessionStore()
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let factory = FakeAppDependencyFactory()
        let preferences = AppPreferences(defaults: testDefaults())
        let session = WorkspaceSessionModel(
            preferences: preferences,
            factory: factory,
            sessionStore: sessionStore)
        await session.openWorkspace(root)

        await session.runChatPrompt("persist this prompt")
        try? await Task.sleep(for: .milliseconds(50))

        let nativeSession = try #require(try await sessionStore.recentSessions(limit: 1, workspacePath: root.path).first)
        #expect(nativeSession.title == "persist this prompt")
        #expect(try await sessionStore.messageParts(sessionID: nativeSession.id, limit: 10).map(\.role) == [.user, .tool, .assistant])
        #expect(try await sessionStore.events(sessionID: nativeSession.id, after: nil, limit: 20).map(\.kind).contains(.promptAdmitted))
        #expect(session.chatMessages.first { $0.role == .assistant }?.tokensPerSecond == 50)

        let restored = WorkspaceSessionModel(
            preferences: preferences,
            factory: factory,
            sessionStore: sessionStore)
        await restored.restoreLastWorkspaceIfNeeded()
        await restored.loadPersistedHistoryOnLaunch()
        #expect(restored.chatMessages.map(\.text).contains("persist this prompt"))
        #expect(restored.chatMessages.map(\.text).contains("answer"))
    }

    @Test func newChatKeepsExistingProjectThreadsVisible() async throws {
        let sessionStore = try PersistenceBootstrap.inMemorySessionStore()
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = WorkspaceSessionModel(
            preferences: AppPreferences(defaults: testDefaults()),
            factory: FakeAppDependencyFactory(),
            sessionStore: sessionStore)
        await session.openWorkspace(root)
        await session.runChatPrompt("first project chat")
        try? await Task.sleep(for: .milliseconds(50))

        session.clearChat()

        #expect(Array(session.viewState.chatThreads.map(\.title).prefix(2)) == ["New Chat", "first project chat"])
        #expect(session.viewState.chatThreads[0].isDraft)
        #expect(session.viewState.chatThreads[1].isSelected == false)

        await session.runChatPrompt("second project chat")
        try? await Task.sleep(for: .milliseconds(50))

        #expect(Array(session.viewState.chatThreads.map(\.title).prefix(2)) == ["second project chat", "first project chat"])
        #expect(session.viewState.chatThreads[0].isSelected)
    }

    @Test func codeAndPlainChatHistoriesStaySeparated() async throws {
        let sessionStore = try PersistenceBootstrap.inMemorySessionStore()
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = WorkspaceSessionModel(
            preferences: AppPreferences(defaults: testDefaults()),
            factory: FakeAppDependencyFactory(),
            sessionStore: sessionStore)
        await session.openWorkspace(root)

        await session.runChatPrompt("code only")
        try? await Task.sleep(for: .milliseconds(50))
        await session.setConversationMode(isPlainChat: true)
        await session.runPlainChatPrompt("chat only")
        try? await Task.sleep(for: .milliseconds(50))

        let state = session.viewState
        #expect(state.chatThreads.contains { $0.title == "code only" })
        #expect(!state.chatThreads.contains { $0.title == "chat only" })
        #expect(state.globalChatThreads.contains { $0.title == "chat only" })
        #expect(!state.globalChatThreads.contains { $0.title == "code only" })
        #expect(try await sessionStore.recentSessions(limit: 10, workspacePath: root.path).map(\.title) == ["code only"])
        let plainTitles = try await sessionStore.recentSessions(limit: 10, workspacePath: nil)
            .filter { $0.workspacePath == nil }
            .map(\.title)
        #expect(plainTitles.contains("chat only"))
        #expect(!plainTitles.contains("code only"))
    }

    @Test func legacyConversationsAreNotImportedIntoNativeSessionList() async throws {
        let appStore = try PersistenceBootstrap.inMemoryAppStore()
        let sessionStore = try PersistenceBootstrap.inMemorySessionStore()
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let legacyID = try await appStore.createConversation(
            title: "Legacy Chat",
            workspacePath: root.path,
            mode: .code)
        try await appStore.appendMessage(
            conversationID: legacyID,
            role: "user",
            text: "legacy prompt",
            createdAt: Date())
        let session = WorkspaceSessionModel(
            preferences: AppPreferences(defaults: testDefaults()),
            factory: FakeAppDependencyFactory(),
            appStore: appStore,
            sessionStore: sessionStore)

        await session.openWorkspace(root)
        await session.loadPersistedHistoryOnLaunch()

        #expect(!session.viewState.chatThreads.contains { $0.title == "Legacy Chat" })
        #expect(session.chatMessages.isEmpty)
        #expect(try await sessionStore.recentSessions(limit: 10, workspacePath: root.path).isEmpty)
    }

    @Test func healthStateRecordsSessionEventsMetricsAndOpenAction() async {
        let factory = FakeAppDependencyFactory()
        let session = WorkspaceSessionModel(preferences: AppPreferences(defaults: testDefaults()), factory: factory)
        await session.openWorkspace(URL(fileURLWithPath: "/tmp/work"))

        session.searchQuery = "readme"
        await session.search()
        await session.selectFile("README.md")
        await session.refreshGit()
        session.openHealth()
        await session.refreshHealthStatus()

        let health = session.viewState.health
        let eventKinds = Set(health.recentEvents.map(\.kind))
        let metricKinds = Set(health.metricSummaries.map(\.kind))

        #expect(session.isHealthPresented)
        #expect(eventKinds.isSuperset(of: ["workspace", "search", "filePreview", "git"]))
        #expect(metricKinds.isSuperset(of: ["searchDuration", "filePreviewDuration", "gitDuration"]))
        #expect(health.recentTasks.contains { $0.kind == "search" && $0.status == .completed })
        #expect(health.memoryPolicy?.resolvedProfile == .smallRAM)
    }

    @Test func healthAndDiagnosticsSurfaceDurableSessionReplay() async throws {
        let store = try PersistenceBootstrap.inMemorySessionStore()
        let durableSession = try await store.createSession(id: UUID(), workspacePath: "/tmp/work", title: "Durable Plan")
        _ = try await store.appendEvent(SessionEvent(sessionID: durableSession.id, kind: .created))
        _ = try await store.appendEvent(SessionEvent(
            sessionID: durableSession.id,
            kind: .toolCallSettled,
            payload: ["stdout": "secret output"]))
        let exportURL = try temporaryDirectory().appendingPathComponent("diagnostics.json")
        let session = WorkspaceSessionModel(
            preferences: AppPreferences(defaults: testDefaults()),
            factory: FakeAppDependencyFactory(),
            sessionStore: store)

        await session.openWorkspace(URL(fileURLWithPath: "/tmp/work"))
        await session.refreshHealthStatus()
        await session.exportDiagnostics(to: exportURL)

        let raw = try String(contentsOf: exportURL, encoding: .utf8)
        #expect(session.viewState.health.durableEventCursors.first?.title == "Durable Plan")
        #expect(session.viewState.health.durableEventCursors.first?.sequence == 2)
        #expect(raw.contains("\"observability\""))
        #expect(raw.contains("secret output") == false)
    }

    @Test func healthStateRecordsModelCancellationAndPatchFailure() async {
        let factory = FakeAppDependencyFactory(longRunningLoad: true)
        let session = WorkspaceSessionModel(preferences: AppPreferences(defaults: testDefaults()), factory: factory)
        session.settings.orchestratorModelID = "orch"
        session.settings.utilityModelID = "util"
        await session.openWorkspace(URL(fileURLWithPath: "/tmp/work"))

        let loadTask = Task { await session.loadModels() }
        _ = await waitUntil {
            session.activities.contains { $0.kind == .modelLoading } || session.modelStatus == .loading
        }
        session.cancelModelLoad()
        await loadTask.value
        session.loadPatchProposal("""
        diff --git a/README.md b/README.md
        --- a/README.md
        +++ b/README.md
        @@ -1 +1 @@
        -old
        +new
        """)
        await session.applyAcceptedPatch()
        await session.refreshHealthStatus()

        let health = session.viewState.health
        let eventKinds = Set(health.recentEvents.map(\.kind))
        let metricKinds = Set(health.metricSummaries.map(\.kind))

        #expect(eventKinds.contains("cancellation"))
        #expect(eventKinds.contains("failure"))
        #expect(metricKinds.contains("cancellationCount"))
        #expect(metricKinds.contains("failureCount"))
        #expect(health.recentFailures.contains { $0.kind == "failure" })
    }

    @Test func recoveryJournalRecordsSessionOperationsWithoutPersistingPrompt() async throws {
        let url = try recoveryJournalURL()
        let journal = RecoveryJournal(fileURL: url)
        let session = WorkspaceSessionModel(
            preferences: AppPreferences(defaults: testDefaults()),
            factory: FakeAppDependencyFactory(),
            recoveryJournal: journal)

        await session.openWorkspace(URL(fileURLWithPath: "/tmp/work"))
        await session.search("readme")
        await session.selectFile("README.md")
        await session.refreshGit()
        await session.runChatPrompt("secret prompt should not be written")
        try? await Task.sleep(for: .milliseconds(60))

        let snapshot = try await journal.snapshot()
        let kinds = Set(snapshot.records.map(\.operationKind))
        let raw = try String(contentsOf: url, encoding: .utf8)

        #expect(kinds.isSuperset(of: [.workspaceOpen, .search, .filePreview, .gitRefresh, .chat]))
        #expect(!raw.contains("secret prompt"))
    }

    @Test func diagnosticsExportWritesRedactedBundleFromSessionState() async throws {
        let url = try temporaryDirectory().appendingPathComponent("diagnostics.json")
        let session = WorkspaceSessionModel(
            preferences: AppPreferences(defaults: testDefaults()),
            factory: FakeAppDependencyFactory())

        await session.openWorkspace(URL(fileURLWithPath: "/tmp/work-secret"))
        await session.selectFile("README.md")
        await session.runChatPrompt("secret prompt should not leak")
        try? await Task.sleep(for: .milliseconds(60))
        await session.exportDiagnostics(to: url)

        let raw = try String(contentsOf: url, encoding: .utf8)
        #expect(session.lastDiagnosticsExport?.path == url.path)
        #expect(session.notices.contains { $0.title == "Diagnostics exported" })
        #expect(raw.contains("secret prompt") == false)
        #expect(raw.contains("contents of README.md") == false)
        #expect(raw.contains("/tmp/work-secret") == false)
        #expect(raw.contains("\"memoryPolicy\""))
        #expect(raw.contains("\"schemaVersion\" : 2"))
    }

    @Test func fakeSoakCycleKeepsStateBoundedAndExportsDiagnostics() async throws {
        let url = try temporaryDirectory().appendingPathComponent("soak-diagnostics.json")
        let session = WorkspaceSessionModel(
            preferences: AppPreferences(defaults: testDefaults()),
            factory: FakeAppDependencyFactory())

        await session.openWorkspace(URL(fileURLWithPath: "/tmp/work"))
        for index in 0..<8 {
            session.searchQuery = "readme-\(index)"
            await session.search()
            await session.selectFile("README.md")
            await session.refreshGit()
            await session.runChatPrompt("soak prompt \(index)")
        }
        try? await Task.sleep(for: .milliseconds(80))
        await session.exportDiagnostics(to: url)
        await session.refreshHealthStatus()

        let raw = try String(contentsOf: url, encoding: .utf8)
        #expect(session.chatMessages.count <= 24)
        #expect(session.viewState.health.recentEvents.count <= 60)
        #expect(raw.count < 200_000)
        #expect(raw.contains("soak prompt") == false)
    }

    @Test func startupRecoveryDetectsUnfinishedPreviousRunAndDoesNotAutoLoadModels() async throws {
        let url = try recoveryJournalURL()
        let oldJournal = RecoveryJournal(fileURL: url, appRunID: UUID())
        _ = try await oldJournal.beginOperation(
            kind: .modelLoad,
            title: "Load models",
            metadata: ["workspacePath": "/tmp/work", "modelID": "orch", "modelRole": "orchestrator"])
        let factory = FakeAppDependencyFactory()
        let session = WorkspaceSessionModel(
            preferences: AppPreferences(defaults: testDefaults()),
            factory: factory,
            recoveryJournal: RecoveryJournal(fileURL: url, appRunID: UUID()))

        await session.loadRecoveryJournalOnLaunch()

        #expect(session.notices.first?.title == "Recovery available")
        #expect(session.viewState.health.recoveryItems.first?.status == "unfinishedPreviousRun")
        #expect(session.viewState.health.recoveryItems.first?.action.kind == .retryModelLoad)
        #expect(await factory.loadSettings.isEmpty)
    }

    @Test func recoveryRetryUsesSafeExplicitOperationsOnly() async throws {
        let url = try recoveryJournalURL()
        let journal = RecoveryJournal(fileURL: url)
        let fileFailure = try await journal.recordFailure(
            kind: .filePreview,
            title: "Preview file",
            message: "Preview failed",
            metadata: ["workspacePath": "/tmp/work", "relativePath": "README.md"])
        _ = try await journal.recordFailure(
            kind: .patchApply,
            title: "Apply patch",
            message: "Patch failed",
            metadata: ["workspacePath": "/tmp/work"])
        let session = WorkspaceSessionModel(
            preferences: AppPreferences(defaults: testDefaults()),
            factory: FakeAppDependencyFactory(),
            recoveryJournal: journal)

        await session.openWorkspace(URL(fileURLWithPath: "/tmp/work"))
        await session.refreshHealthStatus()
        session.retryRecoveryAction(fileFailure.id)
        _ = await waitUntil {
            session.selectedFileText == "contents of README.md"
        }

        #expect(session.selectedFilePath == "README.md")
        #expect(session.selectedFileText == "contents of README.md")
        let patchItem = try #require(session.viewState.health.recoveryItems.first { $0.operationKind == "patchApply" })
        #expect(patchItem.action.kind == .reviewPatch)
        #expect(session.patchProposal == nil)
    }

    @Test func recoveryDismissAndClearAcknowledgedItems() async throws {
        let url = try recoveryJournalURL()
        let journal = RecoveryJournal(fileURL: url)
        let failure = try await journal.recordFailure(kind: .search, title: "Search", message: "failed")
        let session = WorkspaceSessionModel(
            preferences: AppPreferences(defaults: testDefaults()),
            factory: FakeAppDependencyFactory(),
            recoveryJournal: journal)

        await session.refreshHealthStatus()
        #expect(session.viewState.health.recoveryItems.count == 1)
        session.dismissRecoveryItem(failure.id)
        try? await Task.sleep(for: .milliseconds(30))
        session.clearRecoveryJournal()
        try? await Task.sleep(for: .milliseconds(30))

        let snapshot = try await journal.snapshot()
        #expect(snapshot.recoveryItems.isEmpty)
        #expect(snapshot.records.isEmpty)
    }

    @Test func corruptRecoveryJournalSurfacesWarningNotice() async throws {
        let url = try recoveryJournalURL()
        try Data("bad json".utf8).write(to: url)
        let session = WorkspaceSessionModel(
            preferences: AppPreferences(defaults: testDefaults()),
            factory: FakeAppDependencyFactory(),
            recoveryJournal: RecoveryJournal(fileURL: url))

        await session.loadRecoveryJournalOnLaunch()

        #expect(session.notices.contains { $0.title == "Recovery journal reset" })
        #expect(session.viewState.health.recoveryWarning?.contains("Corrupted journal archived") == true)
    }

    @Test func cancelActiveChatStopsLongRunningStream() async {
        let factory = FakeAppDependencyFactory(longRunningAgent: true)
        let session = WorkspaceSessionModel(preferences: AppPreferences(defaults: testDefaults()), factory: factory)
        await session.openWorkspace(URL(fileURLWithPath: "/tmp/work"))

        await session.runChatPrompt("slow")
        session.cancelActiveChat()
        try? await Task.sleep(for: .milliseconds(20))

        #expect(session.chatMessages.contains { $0.role == .assistant })
    }

    @Test func focusActionsUpdateWorkspaceFocusTarget() async {
        let preferences = AppPreferences(defaults: testDefaults())
        let session = WorkspaceSessionModel(preferences: preferences, factory: FakeAppDependencyFactory())

        session.focusSearch()
        #expect(session.viewState.focusTarget == .search)

        session.focusChat()
        #expect(session.viewState.focusTarget == .chat)
    }

    @Test func safePreviewTruncatesBinaryAndRejectsSymlinkEscape() async throws {
        let root = try temporaryDirectory()
        let outside = try temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        try "abcdef".write(to: root.appendingPathComponent("large.txt"), atomically: true, encoding: .utf8)
        try Data([0, 1, 2, 3]).write(to: root.appendingPathComponent("image.bin"))
        try "secret".write(to: outside.appendingPathComponent("secret.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("escape.txt"),
            withDestinationURL: outside.appendingPathComponent("secret.txt"))
        let loader = SafeFilePreviewLoader(maxPreviewBytes: 3)

        let large = try await loader.preview(root: root, relativePath: "large.txt")
        let binary = try await loader.preview(root: root, relativePath: "image.bin")

        #expect(large.isTruncated)
        #expect(large.text.contains("Preview truncated"))
        #expect(binary.kind == .binary)
        await #expect(throws: SafeFilePreviewError.pathEscapesWorkspace("escape.txt")) {
            _ = try await loader.preview(root: root, relativePath: "escape.txt")
        }
    }

    @Test func packagingResourcesExistAndDocumentSwiftPMBundlePath() throws {
        let root = projectRoot()
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("Resources/AppBundle/Info.plist").path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("Resources/AppBundle/Interless.entitlements").path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("Resources/AppBundle/AppIcon.svg").path))
        #expect(FileManager.default.isExecutableFile(atPath: root.appendingPathComponent("scripts/package-app.sh").path))
        let docs = try String(contentsOf: root.appendingPathComponent("docs/PHASE4.md"), encoding: .utf8)
        #expect(docs.contains("SwiftPM app bundle packaging"))
        #expect(docs.contains("scripts/package-app.sh"))
    }

    @Test func patchCoordinatorParsesAndAppliesAcceptedHunks() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try "old\nkeep\n".write(to: root.appendingPathComponent("File.txt"), atomically: true, encoding: .utf8)
        var proposal = PatchReviewCoordinator.parseUnifiedDiff("""
        diff --git a/File.txt b/File.txt
        --- a/File.txt
        +++ b/File.txt
        @@ -1,2 +1,2 @@
        -old
        +new
         keep
        """)

        #expect(proposal.files.count == 1)
        #expect(proposal.acceptedHunkCount == 1)
        proposal.setHunkAccepted(fileID: "File.txt", hunkID: 0, isAccepted: true)
        let result = try await PatchReviewCoordinator(root: root, allowsWrites: true).apply(proposal)
        let contents = try String(contentsOf: root.appendingPathComponent("File.txt"), encoding: .utf8)

        #expect(result.hunksApplied == 1)
        #expect(contents == "new\nkeep\n")
    }

    @Test func patchCoordinatorSnapshotsBeforeApplyAndCanRevert() async throws {
        let root = try temporaryDirectory()
        let snapshotStorage = try temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: snapshotStorage)
        }
        try "old\n".write(to: root.appendingPathComponent("File.txt"), atomically: true, encoding: .utf8)
        var proposal = PatchReviewCoordinator.parseUnifiedDiff("""
        diff --git a/File.txt b/File.txt
        --- a/File.txt
        +++ b/File.txt
        @@ -1 +1 @@
        -old
        +new
        """)
        proposal.setHunkAccepted(fileID: "File.txt", hunkID: 0, isAccepted: true)
        let snapshotStore = WorkspaceSnapshotStore(root: root, storageRoot: snapshotStorage)

        let result = try await PatchReviewCoordinator(
            root: root,
            allowsWrites: true,
            snapshotStore: snapshotStore).apply(proposal)

        #expect(result.snapshotID != nil)
        #expect(try String(contentsOf: root.appendingPathComponent("File.txt"), encoding: .utf8) == "new\n")
        if let snapshotID = result.snapshotID {
            _ = try await snapshotStore.revert(snapshotID)
        }
        #expect(try String(contentsOf: root.appendingPathComponent("File.txt"), encoding: .utf8) == "old\n")
    }

    @Test func patchCoordinatorRejectsDisabledWritesStaleContextAndSymlinkEscape() async throws {
        let root = try temporaryDirectory()
        let outside = try temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        try "current\n".write(to: root.appendingPathComponent("File.txt"), atomically: true, encoding: .utf8)
        try "secret\n".write(to: outside.appendingPathComponent("Secret.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("Escape.txt"),
            withDestinationURL: outside.appendingPathComponent("Secret.txt"))
        let proposal = PatchReviewCoordinator.parseUnifiedDiff("""
        diff --git a/File.txt b/File.txt
        --- a/File.txt
        +++ b/File.txt
        @@ -1 +1 @@
        -old
        +new
        """)
        let escape = PatchReviewCoordinator.parseUnifiedDiff("""
        diff --git a/Escape.txt b/Escape.txt
        --- a/Escape.txt
        +++ b/Escape.txt
        @@ -1 +1 @@
        -secret
        +changed
        """)

        await #expect(throws: PatchReviewError.writesDisabled) {
            _ = try await PatchReviewCoordinator(root: root, allowsWrites: false).apply(proposal)
        }
        await #expect(throws: PatchReviewError.staleContext("File.txt")) {
            _ = try await PatchReviewCoordinator(root: root, allowsWrites: true).apply(proposal)
        }
        await #expect(throws: PatchReviewError.pathEscapesWorkspace("Escape.txt")) {
            _ = try await PatchReviewCoordinator(root: root, allowsWrites: true).apply(escape)
        }
    }

    @Test func patchCoordinatorRejectsOversizedTargetsBeforeReading() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try "0123456789\n".write(to: root.appendingPathComponent("File.txt"), atomically: true, encoding: .utf8)
        let proposal = PatchReviewCoordinator.parseUnifiedDiff("""
        diff --git a/File.txt b/File.txt
        --- a/File.txt
        +++ b/File.txt
        @@ -1 +1 @@
        -0123456789
        +changed
        """)

        await #expect(throws: PatchReviewError.fileTooLarge(path: "File.txt", bytes: 11, limit: 4)) {
            _ = try await PatchReviewCoordinator(
                root: root,
                allowsWrites: true,
                maxTargetFileBytes: 4).apply(proposal)
        }
    }

    @Test func sessionLoadsAndRejectsPatchWithoutWrites() async {
        let session = WorkspaceSessionModel(preferences: AppPreferences(defaults: testDefaults()), factory: FakeAppDependencyFactory())
        await session.openWorkspace(URL(fileURLWithPath: "/tmp/work"))
        session.loadPatchProposal("""
        diff --git a/README.md b/README.md
        --- a/README.md
        +++ b/README.md
        @@ -1 +1 @@
        -old
        +new
        """)

        #expect(session.patchProposal?.acceptedHunkCount == 1)
        await session.applyAcceptedPatch()
        #expect(session.notices.last?.title == "Patch not applied")
    }

    @Test func modelOnboardingAndTreeDisclosurePersistThroughSession() {
        let preferences = AppPreferences(defaults: testDefaults())
        let session = WorkspaceSessionModel(preferences: preferences, factory: FakeAppDependencyFactory())

        session.toggleFileTreeDirectory("Sources")
        session.settings.resourceProfile = .balanced
        session.dismissModelOnboarding()
        session.applyRecommendedModels()

        #expect(preferences.expandedFileTreePaths == Set(["Sources"]))
        #expect(preferences.isModelOnboardingDismissed)
        #expect(session.settings.orchestratorModelID == "Qwen3.6-35B-A3B")
        #expect(session.settings.utilityModelID == "Qwen3.5-2B")
    }

    @Test func modelOnboardingUsesSingleDownloadedModelOnSmallRAM() {
        let session = WorkspaceSessionModel(preferences: AppPreferences(defaults: testDefaults()), factory: FakeAppDependencyFactory())
        session.settings.resourceProfile = .smallRAM

        session.applyRecommendedModels()

        #expect(!session.settings.orchestratorModelID.isEmpty)
        #expect(session.settings.utilityModelID.isEmpty)
        #expect(session.settings.embeddingsModelID.isEmpty)
    }
}

private actor FakeAppDependencyFactory: AppDependencyFactory {
    var makeCount = 0
    var loadSettings: [ModelSettingsViewState] = []
    var runTasks: [AgentTask] = []
    var executedToolRequests: [ToolRequest] = []
    var configs: [LoadedInterlessConfig?] = []
    let responseText: String
    let longRunningAgent: Bool
    let longRunningLoad: Bool
    let completionStopReason: String
    let toolResult: ToolResult?

    init(
        responseText: String = "answer",
        longRunningAgent: Bool = false,
        longRunningLoad: Bool = false,
        completionStopReason: String = "",
        toolResult: ToolResult? = nil
    ) {
        self.responseText = responseText
        self.longRunningAgent = longRunningAgent
        self.longRunningLoad = longRunningLoad
        self.completionStopReason = completionStopReason
        self.toolResult = toolResult
    }

    func makeWorkspaceEnvironment(
        root: URL,
        settings: ModelSettingsViewState,
        metricsRecorder: MetricsRecorder,
        eventBus: EventBus,
        config: LoadedInterlessConfig?
    ) async throws -> WorkspaceEnvironment {
        makeCount += 1
        configs.append(config)
        return WorkspaceEnvironment(
            root: root,
            reindex: {
                AsyncStream { continuation in
                    continuation.yield(IndexingProgress(phase: .completed, scanned: 1, indexed: 1))
                    continuation.finish()
                }
            },
            watch: {
                AsyncStream { continuation in continuation.finish() }
            },
            search: { query, _ in
                [SearchHit(relativePath: "README.md", score: 0.1, snippet: query)]
            },
            previewFile: { path in
                FilePreviewViewState(path: path, kind: .text, text: "contents of \(path)", byteCount: path.count)
            },
            fileTree: {
                FileTreeNode.grouped(paths: ["README.md"])
            },
            gitStatus: {
                GitStatus(isRepository: true, branch: "main", entries: [.init(path: "README.md", xy: " M")])
            },
            gitDiff: { _ in
                """
                diff --git a/README.md b/README.md
                @@ -1 +1 @@
                +new
                """
            },
            executeTool: { request, _, runtimeHooks in
                try await self.executeFakeTool(root: root, request: request, runtimeHooks: runtimeHooks)
            },
            runAgent: { task, _, _ in
                let longRunning = self.longRunningAgent
                let responseText = self.responseText
                let toolResult = self.toolResult
                await self.recordRun(task)
                return AsyncThrowingStream { continuation in
                    continuation.yield(.toolStarted(.gitStatus))
                    if let toolResult {
                        continuation.yield(.toolFinished(toolResult))
                    }
                    continuation.yield(.token(TokenChunk(text: responseText, index: 0, isFinal: false)))
                    continuation.yield(.token(TokenChunk(
                        text: "",
                        index: 1,
                        isFinal: true,
                        info: .init(
                            generationTokenCount: 1,
                            generateTime: 0.02,
                            tokensPerSecond: 50,
                            stopReason: self.completionStopReason))))
                    if longRunning {
                        Task {
                            try? await Task.sleep(for: .seconds(5))
                            continuation.finish()
                        }
                    } else {
                        continuation.yield(.completed(AgentResult(taskID: UUID(), route: .utility, text: responseText)))
                        continuation.finish()
                    }
                }
            },
            loadModels: { settings, progressReporter in
                progressReporter?("mlx-community/gemma-2-2b-it-4bit", .orchestrator, 0)
                progressReporter?("mlx-community/gemma-2-2b-it-4bit", .orchestrator, 0.45)
                if self.longRunningLoad {
                    try await Task.sleep(for: .seconds(5))
                }
                progressReporter?("mlx-community/gemma-2-2b-it-4bit", .orchestrator, 1)
                await self.recordLoad(settings)
            },
            unloadModels: {},
            memoryPolicy: {
                MemoryPolicyState(
                    requestedProfile: settings.resourceProfile,
                    physicalMemoryBytes: 8 * 1024 * 1024 * 1024,
                    snapshot: MemorySnapshot(
                        footprint: MemoryFootprint(
                            processFootprintBytes: 2 * 1024 * 1024 * 1024,
                            totalUnifiedBytes: 8 * 1024 * 1024 * 1024)),
                    activeActions: [])
            })
    }

    private func recordLoad(_ settings: ModelSettingsViewState) {
        loadSettings.append(settings)
    }

    private func recordRun(_ task: AgentTask) {
        runTasks.append(task)
    }

    private func executeFakeTool(
        root: URL,
        request: ToolRequest,
        runtimeHooks: ToolRuntimeHooks?
    ) async throws -> ToolResult {
        executedToolRequests.append(request)
        if let toolResult {
            return toolResult
        }
        let loop = try ToolExecutionLoop(
            root: root,
            policy: ToolExecutionPolicy(allowsWrites: true),
            mutationRecorder: { _, _ in UUID().uuidString },
            permissionAuthorizer: runtimeHooks?.permissionAuthorizer,
            settlementHandlers: runtimeHooks?.settlementHandlers ?? .empty)
        return try await loop.execute(request)
    }
}

private func testDefaults() -> UserDefaults {
    UserDefaults(suiteName: "if-tests-\(UUID().uuidString)")!
}

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func recoveryJournalURL() throws -> URL {
    try temporaryDirectory().appendingPathComponent("recovery-journal.json")
}

private func projectRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

@MainActor
private func waitUntil(
    attempts: Int = 100,
    interval: Duration = .milliseconds(10),
    _ condition: @MainActor () -> Bool
) async -> Bool {
    for _ in 0..<attempts {
        if condition() { return true }
        try? await Task.sleep(for: interval)
    }
    return condition()
}

private func defaultsSuiteName(_ defaults: UserDefaults) -> String {
    defaults.dictionaryRepresentation()["NSArgumentDomain"] as? String ?? ""
}
