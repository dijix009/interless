import Testing
import Foundation
import Shared
import UI

struct UITests {
    @Test func fileTreeGroupsPathSegments() {
        let nodes = FileTreeNode.grouped(paths: ["Sources/App/Main.swift", "README.md"])

        #expect(nodes.map(\.name) == ["README.md", "Sources"])
        #expect(nodes[1].children.first?.name == "App")
        #expect(nodes[1].children.first?.children.first?.path == "Sources/App/Main.swift")
    }

    @Test func fileTreeFiltersByPathSegments() {
        let nodes = FileTreeNode.grouped(paths: ["Sources/App/Main.swift", "Tests/AppTests.swift", "README.md"])
        let filtered = FileTreeNode.filtered(nodes: nodes, query: "tests")

        #expect(filtered.map(\.name) == ["Tests"])
        #expect(filtered.first?.children.first?.path == "Tests/AppTests.swift")
    }

    @Test func fileTreeVisibleRowsRespectExpansionFilteringAndLimit() {
        let nodes = FileTreeNode.grouped(paths: [
            "Sources/App/Main.swift",
            "Sources/App/Session.swift",
            "Tests/AppTests.swift",
            "README.md",
        ])

        let collapsed = FileTreeModel.visibleRows(nodes: nodes, expandedPaths: [])
        let expanded = FileTreeModel.visibleRows(nodes: nodes, expandedPaths: ["Sources", "Sources/App"])
        let filtered = FileTreeModel.visibleRows(nodes: nodes, expandedPaths: [], filter: "session")
        let limited = FileTreeModel.visibleRows(nodes: nodes, expandedPaths: ["Sources", "Sources/App"], limit: 2)

        #expect(collapsed.map(\.path) == ["README.md", "Sources", "Tests"])
        #expect(expanded.contains { $0.path == "Sources/App/Main.swift" })
        #expect(filtered.map(\.path).contains("Sources/App/Session.swift"))
        #expect(limited.count == 2)
    }

    @Test func diffFormatterClassifiesLines() {
        let lines = DiffFormatter.classify("""
        diff --git a/a b/a
        @@ -1 +1 @@
        -old
        +new
         context
        """)

        #expect(lines.map(\.kind) == [.file, .hunk, .deletion, .addition, .context])
    }

    @Test func diffFormatterGroupsFilesHunksAndStats() {
        let files = DiffFormatter.files("""
        diff --git a/a.swift b/a.swift
        --- a/a.swift
        +++ b/a.swift
        @@ -1,2 +1,2 @@
        -old
        +new
         context
        diff --git a/b.swift b/b.swift
        @@ -1 +1 @@
        +added
        """)

        #expect(files.count == 2)
        #expect(files[0].newPath == "a.swift")
        #expect(files[0].additions == 1)
        #expect(files[0].deletions == 1)
        #expect(files[0].hunks.count == 1)
        #expect(files[1].additions == 1)
    }

    @Test func markdownMessageParserParsesFencedCodeBlocks() {
        let blocks = MarkdownMessageParser.parse("""
        Sure.

        ```html
        <!DOCTYPE html>
        <title>Temperature</title>
        ```
        """)

        #expect(blocks == [
            .paragraph("Sure."),
            .code(language: "html", text: "<!DOCTYPE html>\n<title>Temperature</title>", isClosed: true),
        ])
    }

    @Test func markdownMessageParserTreatsOpenFenceAsStreamingCode() {
        let blocks = MarkdownMessageParser.parse("""
        ```swift
        let value = 42
        """)

        #expect(blocks == [
            .code(language: "swift", text: "let value = 42", isClosed: false),
        ])
    }

    @Test func markdownMessageParserParsesCommonAssistantBlocks() {
        let blocks = MarkdownMessageParser.parse("""
        ## Summary

        - **Fast** rendering
        - Native SwiftUI

        1. Parse
        2. Render

        > Latest request stays authoritative.

        ---
        """)

        #expect(blocks == [
            .heading(level: 2, text: "Summary"),
            .unorderedList(["**Fast** rendering", "Native SwiftUI"]),
            .orderedList(start: 1, items: ["Parse", "Render"]),
            .blockquote("Latest request stays authoritative."),
            .horizontalRule,
        ])
    }

    @Test func assistantMessagesUseNativeMarkdownRenderer() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let chatPane = try String(
            contentsOf: root.appendingPathComponent("UI/ChatPaneView.swift"),
            encoding: .utf8)
        let renderer = try String(
            contentsOf: root.appendingPathComponent("UI/MarkdownMessageView.swift"),
            encoding: .utf8)

        #expect(chatPane.contains("MarkdownMessageView(text)"))
        #expect(renderer.contains("public enum MarkdownBlock"))
        #expect(renderer.contains("CodeBlockView(language: language, code: text, isClosed: isClosed)"))
        #expect(!renderer.contains("WKWebView"))
        #expect(!renderer.contains("WebView"))
    }

    @Test func parityPanelPresentationModelsAreStable() {
        let permission = PermissionPromptViewState(
            title: "Allow write",
            message: "edit_file wants to modify README.md",
            toolName: "edit_file",
            risk: "write")
        let todos = TodoPanelViewState(items: [
            TodoItemViewState(title: "Inspect", status: .completed),
            TodoItemViewState(title: "Patch", status: .inProgress),
            TodoItemViewState(title: "Test", status: .pending),
        ])
        let history = WorkspaceHistoryItemViewState(path: "/tmp/interless")
        let export = ShareExportViewState(includesMessages: true, includesToolOutputs: true)
        let timeline = SessionTimelineItemViewState(title: "Tool finished", detail: "grep", severity: .warning)

        #expect(permission.toolName == "edit_file")
        #expect(todos.openCount == 2)
        #expect(history.displayName == "interless")
        #expect(export.includesToolOutputs)
        #expect(timeline.severity == .warning)
    }

    @Test func sessionNavigatorGroupsWorkspacePlainPinnedInterruptedAndJobs() {
        let projectID = UUID()
        let plainID = UUID()
        let jobID = UUID()
        let sections = SessionNavigatorModel.sections(
            workspaceName: "interless",
            workspacePath: "/tmp/interless",
            projectThreads: [
                ChatThreadViewState(
                    id: projectID,
                    title: "Fix tools",
                    subtitle: "Today",
                    workspacePath: "/tmp/interless",
                    isInterrupted: true,
                    isActiveNow: true)
            ],
            plainThreads: [
                ChatThreadViewState(
                    id: plainID,
                    title: "Research",
                    isPinned: true,
                    isArchived: true,
                    unreadCount: 2)
            ],
            jobs: [
                BackgroundToolJobViewState(id: jobID, title: "Run tests", status: .running, detail: "swift test")
            ])

        #expect(sections.map(\.id).contains("workspace"))
        #expect(sections.map(\.id).contains("plain"))
        #expect(sections.map(\.id).contains("pinned"))
        #expect(sections.map(\.id).contains("recent"))
        #expect(sections.map(\.id).contains("interrupted"))
        #expect(sections.map(\.id).contains("active-jobs"))
        #expect(sections.first { $0.id == "workspace" }?.items.first?.isInterrupted == true)
        #expect(sections.first { $0.id == "pinned" }?.items.first?.unreadCount == 2)
        #expect(sections.first { $0.id == "active-jobs" }?.items.first?.title == "Run tests")
    }

    @Test func promptSuggestionModelFiltersOnlyMentionCommandAndSnippetPrefixes() {
        #expect(PromptSuggestionModel.suggestions(for: "").map(\.title).contains("@file"))
        #expect(PromptSuggestionModel.suggestions(for: "hello world").isEmpty)
        #expect(PromptSuggestionModel.suggestions(for: "@ag").map(\.kind) == [.agent])
        #expect(PromptSuggestionModel.suggestions(for: "/sk").map(\.kind) == [.skill])
        #expect(PromptSuggestionModel.suggestions(for: "#sn").map(\.kind) == [.snippet])
    }

    @Test func inspectorAndSettingsSectionsCoverNativeMigrationSurfaces() {
        #expect(WorkspaceInspectorTab.allCases.map(\.title) == [
            "Git",
            "Files",
            "Context",
            "Diff",
            "Todos",
            "Jobs",
            "Timeline",
            "History",
        ])
        #expect(SettingsHubSection.visibleCases.map(\.title) == [
            "Appearance",
            "Chat",
            "Model & Context",
            "Sessions",
            "Behavior",
            "MCP",
            "Usage",
        ])
    }

    @Test func modelContextSettingsNormalizeAndDisplayAutomaticLimits() {
        let settings = ModelContextSettingsViewState(
            plainChatMaxAnswerTokens: 1,
            codeChatMaxAnswerTokens: 100_000,
            plainChatMaxContextWindowTokens: 1,
            codeChatMaxContextWindowTokens: 200_000)

        #expect(ModelContextSettingsViewState().maxAnswerTokens(isPlainChat: true) == nil)
        #expect(ModelContextSettingsViewState().contextTokenBudgetOverride(isPlainChat: true) == nil)
        #expect(ModelContextSettingsViewState().conversationContextMode(isPlainChat: true) == .simple)
        #expect(ModelContextSettingsViewState().conversationContextMode(isPlainChat: false) == .smart)
        #expect(ModelContextSettingsViewState.displayTokenValue(0) == "Automatic")
        #expect(ModelContextSettingsViewState.classicAnswerTokenSteps == [
            0,
            1_024,
            2_048,
            4_096,
            8_192,
            16_384,
            32_768,
        ])
        #expect(ModelContextSettingsViewState.classicContextWindowTokenSteps.suffix(3) == [
            32_768,
            65_536,
            131_072,
        ])
        #expect(ModelContextSettingsViewState.nearestTokenStepIndex(
            for: 1_800,
            in: ModelContextSettingsViewState.classicAnswerTokenSteps) == 2)
        #expect(ModelContextSettingsViewState.snappedTokenValue(
            1_920,
            in: ModelContextSettingsViewState.classicAnswerTokenSteps,
            snapDistance: ModelContextSettingsViewState.answerTokenSnapDistance) == 2_048)
        #expect(ModelContextSettingsViewState.snappedTokenValue(
            2_432,
            in: ModelContextSettingsViewState.classicAnswerTokenSteps,
            snapDistance: ModelContextSettingsViewState.answerTokenSnapDistance) == 2_432)
        #expect(ModelContextSettingsViewState.snappedTokenValue(
            65_024,
            in: ModelContextSettingsViewState.classicContextWindowTokenSteps,
            snapDistance: ModelContextSettingsViewState.contextWindowTokenSnapDistance) == 65_536)
        #expect(settings.plainChatMaxAnswerTokens == ModelContextSettingsViewState.minimumAnswerTokens)
        #expect(settings.codeChatMaxAnswerTokens == ModelContextSettingsViewState.maximumAnswerTokens)
        #expect(settings.plainChatMaxContextWindowTokens == ModelContextSettingsViewState.minimumContextWindowTokens)
        #expect(settings.codeChatMaxContextWindowTokens == ModelContextSettingsViewState.maximumContextWindowTokens)
        #expect(settings.contextTokenBudgetOverride(isPlainChat: true) == ModelContextSettingsViewState.minimumContextWindowTokens)
        #expect(settings.contextTokenBudgetOverride(isPlainChat: false) == ModelContextSettingsViewState.maximumContextWindowTokens)
    }

    @Test func openChamberAlignedPresentationAdaptersSummarizeGitAndDiff() {
        let files = DiffFormatter.files("""
        diff --git a/a.swift b/a.swift
        --- a/a.swift
        +++ b/a.swift
        @@ -1 +1 @@
        -old
        +new
        """)
        let git = InspectorGitViewState(summary: "main +1 -1", diffFiles: files, fallbackLines: [])
        let diff = InspectorDiffViewState(files: files, fallbackLines: [], viewMode: .allFiles)

        #expect(git.changedFiles.first?.status == "M")
        #expect(git.changedFiles.first?.additions == 1)
        #expect(git.changedFiles.first?.deletions == 1)
        #expect(git.canReviewDiff)
        #expect(diff.fileCount == 1)
    }

    @Test func settingsAvailabilityCanDisableDeferredNativeSections() {
        let availability = SettingsSectionAvailability(
            sectionID: SettingsHubSection.skillsCatalog.id,
            isAvailable: false,
            reason: "Native catalog pending.")

        #expect(availability.sectionID == "skillsCatalog")
        #expect(!availability.isAvailable)
        #expect(availability.reason?.contains("pending") == true)
    }

    @Test func settingsHubAvoidsNavigationSplitViewInsideOverlay() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let contents = try String(
            contentsOf: root.appendingPathComponent("UI/SettingsHubView.swift"),
            encoding: .utf8)

        #expect(!contents.contains("NavigationSplitView"))
    }

    @Test func settingsAndHealthSubmenusUseCustomModalShells() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let health = try String(
            contentsOf: root.appendingPathComponent("UI/HealthStatusView.swift"),
            encoding: .utf8)
        let modelSettings = try String(
            contentsOf: root.appendingPathComponent("UI/ModelSettingsView.swift"),
            encoding: .utf8)

        #expect(!health.contains("NavigationSplitView"))
        #expect(!health.contains("List {"))
        #expect(!modelSettings.contains("Form {"))
        #expect(modelSettings.contains("settingsCard"))
    }

    @Test func workspaceViewDoesNotRenderLegacyProjectSourceDiffPanel() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let contents = try String(
            contentsOf: root.appendingPathComponent("UI/WorkspaceView.swift"),
            encoding: .utf8)

        #expect(!contents.contains("EditorTab"))
        #expect(!contents.contains("selectedEditorTab"))
        #expect(!contents.contains("editorPane"))
        #expect(!contents.contains("Diff (\\("))
        #expect(!contents.contains("DiffViewer("))
        #expect(!contents.contains("CodePreviewView("))
    }

    @Test func swiftUITransitionDoesNotIntroduceWebUIPatterns() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let uiFiles = [
            "UI/WorkspaceView.swift",
            "UI/WorkspaceInspectorView.swift",
            "UI/ChatPaneView.swift",
            "UI/MarkdownMessageView.swift",
            "UI/SettingsHubView.swift",
            "UI/SessionNavigatorView.swift",
        ]
        let forbidden = ["WKWebView", "WebView", "React", "Electron", ".css", "localhost", "http://127.0.0.1"]
        for file in uiFiles {
            let contents = try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8)
            for token in forbidden {
                #expect(!contents.contains(token), "\(file) should not contain \(token)")
            }
        }
    }

    @Test func healthFormattingAndFailureFilteringArePresentationOnly() {
        let state = HealthStatusViewState(
            activeTasks: [
                HealthTaskViewState(title: "Index workspace", kind: "indexing", status: .running, priority: "userInitiated")
            ],
            recentEvents: [
                HealthEventViewState(kind: "search", severity: .info, message: "Search completed"),
                HealthEventViewState(kind: "failure", severity: .error, message: "Search failed"),
            ],
            metricSummaries: [
                HealthMetricViewState(kind: "searchDuration", unit: "milliseconds", count: 2, latest: 12.4, average: 10.2),
                HealthMetricViewState(kind: "memoryFootprint", unit: "bytes", count: 1, latest: 1024, average: 1024),
            ],
            memorySummary: "Memory latest 1 KB",
            recoveryItems: [
                RecoveryItemViewState(
                    title: "Preview file",
                    operationKind: "filePreview",
                    status: "failed",
                    message: "Preview failed",
                    workspacePath: "/tmp/work",
                    relativePath: "README.md",
                    action: RecoveryActionViewState(kind: .retryFilePreview))
            ],
            diagnosticsExport: DiagnosticsExportViewState(path: "/tmp/diagnostics.json"))

        #expect(state.recentFailures.map(\.message) == ["Search failed"])
        #expect(state.metricSummaries[0].summary.contains("12 ms"))
        #expect(HealthFormatting.format(0.42, unit: "ratio") == "42%")
        #expect(!state.activeTasks.isEmpty)
        #expect(state.recoverySummary == "1 recovery items · 0 unfinished · 1 failed")
        #expect(state.diagnosticsExport?.summary.contains("diagnostics.json") == true)
    }

    @Test func recoveryFormattingProvidesActionLabelsAndSummaries() {
        let unfinished = RecoveryItemViewState(
            title: "Full reindex",
            operationKind: "indexing",
            status: "unfinishedPreviousRun",
            workspacePath: "/tmp/work",
            action: RecoveryActionViewState(kind: .retryIndexing, disabledReason: "Open a workspace first."))
        let failed = RecoveryItemViewState(
            title: "Load models",
            operationKind: "modelLoad",
            status: "failed",
            action: RecoveryActionViewState(kind: .retryModelLoad))

        #expect(RecoveryFormatting.title(for: .retryModelLoad) == "Retry Model Load")
        #expect(RecoveryFormatting.summary(items: [unfinished, failed]) == "2 recovery items · 1 unfinished · 1 failed")
        #expect(unfinished.summary.contains("/tmp/work"))
        #expect(unfinished.action.disabledReason == "Open a workspace first.")
    }

    @Test func patchReviewModelSummarizesAndDisablesApplySafely() {
        var proposal = PatchProposal(files: [
            PatchFile(oldPath: "A.swift", newPath: "A.swift", hunks: [
                PatchHunk(
                    id: 0,
                    header: "@@ -1 +1 @@",
                    oldStart: 1,
                    oldCount: 1,
                    newStart: 1,
                    newCount: 1,
                    lines: [
                        PatchLine(id: 0, kind: .deletion, text: "old"),
                        PatchLine(id: 1, kind: .addition, text: "new"),
                    ])
            ])
        ])

        #expect(proposal.summary.contains("1/1 hunks accepted"))
        #expect(PatchReviewModel.disabledApplyReason(proposal: proposal, writesAllowed: false)?.contains("Enable write tools") == true)
        #expect(PatchReviewModel.disabledApplyReason(proposal: proposal, writesAllowed: true) == nil)

        proposal.setHunkAccepted(fileID: "A.swift", hunkID: 0, isAccepted: false)
        #expect(PatchReviewModel.disabledApplyReason(proposal: proposal, writesAllowed: true) == "No hunks are accepted.")
    }

    @Test func settingsValidationRequiresModelIDs() {
        var settings = ModelSettingsViewState(resourceProfile: .balanced)
        #expect(settings.validationErrors.count == 2)

        settings.orchestratorModelID = "orchestrator"
        settings.utilityModelID = "utility"
        settings.allowWrites = false

        #expect(settings.validationErrors.isEmpty)
        #expect(!settings.allowWrites)
    }

    @Test func settingsValidationUsesOneChatModelForSmallRAM() {
        var settings = ModelSettingsViewState(resourceProfile: .smallRAM)
        #expect(settings.validationErrors == ["Chat model ID is required."])

        settings.orchestratorModelID = "mlx-community/Qwen2.5-0.5B-Instruct-4bit"
        #expect(settings.validationErrors.isEmpty)
    }

    @Test func settingsValidationRejectsUnsupportedOptiQModel() {
        var settings = ModelSettingsViewState(resourceProfile: .smallRAM)
        settings.orchestratorModelID = "mlx-community/Qwen3.5-2B-OptiQ-4bit"

        #expect(settings.validationErrors.count == 1)
        #expect(settings.validationErrors[0].contains("OptiQ"))
    }

    @Test func settingsWarnWhenWritesEnabled() {
        var settings = ModelSettingsViewState(orchestratorModelID: "orch", utilityModelID: "util")
        #expect(settings.writeWarning == nil)

        settings.allowWrites = true

        #expect(settings.writeWarning?.contains("Write tools") == true)
    }

    @Test func chatComposerListsOnlyDownloadedModels() {
        var settings = ModelSettingsViewState()
        #expect(ChatComposerModel.availableModelIDs(settings: settings).isEmpty)

        settings.orchestratorModelID = "mlx-community/Llama-3.2-1B-Instruct-4bit"
        settings.utilityModelID = "placeholder-utility"

        #expect(ChatComposerModel.availableModelIDs(settings: settings).isEmpty)
    }

    @Test func chatComposerPrefersLocalModelsOverRecommendationPlaceholders() {
        var settings = ModelSettingsViewState()
        settings.orchestratorModelID = "Qwen3.6-35B-A3B"
        let local = [
            "mlx-community/Llama-3.2-1B-Instruct-4bit",
            "mlx-community/Qwen2.5-0.5B-Instruct-4bit"
        ]

        #expect(ChatComposerModel.availableModelIDs(settings: settings, localModelIDs: local) == local)

        settings.orchestratorModelID = local[1]
        #expect(ChatComposerModel.availableModelIDs(settings: settings, localModelIDs: local) == [
            "mlx-community/Qwen2.5-0.5B-Instruct-4bit",
            "mlx-community/Llama-3.2-1B-Instruct-4bit"
        ])
    }

    @Test func chatComposerFiltersUnsupportedDownloadedModels() {
        var settings = ModelSettingsViewState()
        settings.orchestratorModelID = "mlx-community/Qwen3.5-2B-OptiQ-4bit"
        let local = [
            "mlx-community/Qwen3.5-2B-OptiQ-4bit",
            "mlx-community/Llama-3.2-1B-Instruct-4bit"
        ]

        #expect(ChatComposerModel.availableModelIDs(settings: settings, localModelIDs: local) == [
            "mlx-community/Llama-3.2-1B-Instruct-4bit"
        ])
    }

    @Test func chatComposerModelSelectionLoadsOnlyWhenNeeded() {
        #expect(ChatComposerModel.shouldLoadSelectedModel(
            currentModelID: "mlx-community/Llama-3.2-1B-Instruct-4bit",
            selectedModelID: "mlx-community/Llama-3.2-1B-Instruct-4bit",
            status: .loaded) == false)
        #expect(ChatComposerModel.shouldLoadSelectedModel(
            currentModelID: "mlx-community/Llama-3.2-1B-Instruct-4bit",
            selectedModelID: "mlx-community/gemma-2-2b-it-4bit",
            status: .loaded))
        #expect(ChatComposerModel.shouldLoadSelectedModel(
            currentModelID: "mlx-community/Llama-3.2-1B-Instruct-4bit",
            selectedModelID: "mlx-community/Llama-3.2-1B-Instruct-4bit",
            status: .idle))
        #expect(ChatComposerModel.shouldLoadSelectedModel(
            currentModelID: "mlx-community/Llama-3.2-1B-Instruct-4bit",
            selectedModelID: "   ",
            status: .idle) == false)
    }

    @Test func modelDownloadProgressFormatsComposerStatus() {
        let progress = ModelDownloadProgressViewState(
            modelID: "mlx-community/gemma-2-2b-it-4bit",
            roleLabel: "orchestrator",
            fractionCompleted: 0.451)

        #expect(progress.percent == 45)
        #expect(progress.statusText == "Downloading model - 45%")
    }

    @Test func reasoningOptionsMarkSelectedValidModelEffort() {
        let options = ReasoningOptionViewState.options(
            for: "Qwen/Qwen3-4B-MLX-4bit",
            selected: .medium)

        #expect(options.map(\.effort) == [.none, .low, .medium, .high])
        #expect(options.first { $0.effort == .medium }?.isSelected == true)
    }

    @Test func reasoningOptionsClampUnsupportedModelEffort() {
        let options = ReasoningOptionViewState.options(
            for: "mlx-community/gemma-2-2b-it-4bit",
            selected: .high)

        #expect(options.map(\.effort) == [.none])
        #expect(options.first?.isSelected == true)
    }

    @Test func chatModelPickerOffersGemmaDownloadCandidate() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let chatPaneContents = try String(
            contentsOf: root.appendingPathComponent("UI/ChatPaneView.swift"),
            encoding: .utf8)
        let pickerContents = try String(
            contentsOf: root.appendingPathComponent("UI/ComposerModelPickerSheet.swift"),
            encoding: .utf8)

        #expect(pickerContents.contains("mlx-community/gemma-2-2b-it-4bit"))
        #expect(chatPaneContents.contains("isModelPickerSheetPresented"))
        #expect(chatPaneContents.contains(".sheet(isPresented: $isModelPickerSheetPresented)"))
        #expect(chatPaneContents.contains("ComposerModelPickerSheet"))
        #expect(!chatPaneContents.contains("isModelPickerPresented"))
        #expect(!chatPaneContents.contains("modelPickerPopover"))
        #expect(!chatPaneContents.contains("selectModelFromMenu"))
        #expect(!pickerContents.contains(".popover"))
        #expect(!pickerContents.contains("MANUAL MODEL ID"))
        #expect(!pickerContents.contains("manualModelID"))
        #expect(pickerContents.contains("Download and load"))
    }

    @Test func composerModelPickerFiltersAndValidatesManualIDs() {
        let models = [
            "mlx-community/Llama-3.2-1B-Instruct-4bit",
            "mlx-community/gemma-2-2b-it-4bit",
        ]

        #expect(ComposerModelPickerModel.filteredModelIDs(models, query: "gemma") == [
            "mlx-community/gemma-2-2b-it-4bit",
        ])
        #expect(ComposerModelPickerModel.downloadCandidate(
            from: "mlx-community/gemma-2-2b-it-4bit",
            availableModels: []) == "mlx-community/gemma-2-2b-it-4bit")
        #expect(ComposerModelPickerModel.downloadCandidate(
            from: "mlx-community/gemma-2-2b-it-4bit",
            availableModels: models) == nil)
        #expect(ComposerModelPickerModel.downloadCandidateValidationMessage("mlx-community/Qwen3.5-2B-OptiQ-4bit")?.contains("OptiQ") == true)
        #expect(ComposerModelPickerModel.downloadCandidate(
            from: "mlx-community/Qwen3.5-2B-OptiQ-4bit",
            availableModels: []) == nil)
        #expect(ComposerModelPickerModel.downloadCandidateValidationMessage("gemma") == nil)
        #expect(ComposerModelPickerModel.downloadCandidate(from: "gemma", availableModels: []) == nil)
    }

    @Test func onboardingProvidesArchitectureRecommendedModels() {
        let onboarding = ModelOnboardingViewState()

        #expect(onboarding.recommendations.map(\.modelID).contains("Qwen3.6-35B-A3B"))
        #expect(onboarding.recommendations.map(\.modelID).contains("Qwen3.5-2B"))
        #expect(onboarding.guidanceText.contains("explicitly press Load"))
    }

    @Test func accessibilityCopyDescribesPatchHunksAndModelStatus() {
        let hunk = PatchHunk(
            id: 0,
            header: "@@ -1 +1 @@",
            oldStart: 1,
            oldCount: 1,
            newStart: 1,
            newCount: 1,
            lines: [PatchLine(id: 0, kind: .addition, text: "new")],
            isAccepted: false)

        #expect(AccessibilityCopy.patchHunkLabel(hunk).contains("Rejected"))
        #expect(AccessibilityCopy.modelStatusLabel(.loading) == "Model status: Loading")
    }

    @Test func chatToolEventsCanBeCollapsed() {
        let message = ChatMessageViewState(role: .tool, text: "Started gitStatus", isCollapsed: true)

        #expect(message.isToolEvent)
        #expect(message.isCollapsed)
    }

    @Test func changedFileSummaryMessagesRenderAsToolCards() throws {
        let summary = ChatToolSummaryViewState(
            title: "Created 1 file",
            subtitle: "+12 -0",
            files: [
                ChangedFileSummaryViewState(
                    path: "temperature-converter.html",
                    operation: "created",
                    additions: 12,
                    deletions: 0)
            ],
            snapshotID: UUID().uuidString,
            canReview: true,
            canUndo: true)
        let message = ChatMessageViewState(
            role: .tool,
            kind: "fileChanges",
            text: "{}",
            isCollapsed: false,
            toolSummary: summary)

        #expect(message.kind == "fileChanges")
        #expect(message.toolSummary?.files.first?.path == "temperature-converter.html")
        #expect(message.isToolEvent)
        #expect(!message.isCollapsed)

        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let contents = try String(
            contentsOf: root.appendingPathComponent("UI/ChatPaneView.swift"),
            encoding: .utf8)
        #expect(contents.contains("changedFilesCard(summary)"))
        #expect(contents.contains("onReviewChangedFiles()"))
        #expect(contents.contains("onRevertSnapshot(snapshotID)"))
    }

    @Test func uiTargetDoesNotImportRuntimeModules() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let uiFiles = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("UI"), includingPropertiesForKeys: nil)
        let forbidden = ["MLXEngine", "Persistence", "Workspace", "Tooling", "Agents", "GRDB"]

        for file in uiFiles where file.pathExtension == "swift" {
            let contents = try String(contentsOf: file, encoding: .utf8)
            for module in forbidden {
                #expect(!contents.contains("import \(module)"))
            }
        }
    }
}
