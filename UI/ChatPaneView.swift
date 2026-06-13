import AppKit
import Shared
import SwiftUI

public struct ChatPaneView: View {
    public var messages: [ChatMessageViewState]
    @Binding private var draft: String
    public var focusTarget: WorkspaceFocusTarget
    public var modelName: String
    public var modelStatus: ModelLoadStatus
    public var modelDownloadProgress: ModelDownloadProgressViewState?
    public var availableModels: [String]
    public var agentName: String
    public var agentItems: [AgentSwitcherItemViewState]
    public var selectedAgentID: String?
    public var preferences: ChatSurfacePreferences
    public var showsWorkspaceComposerControls: Bool
    public var contextUsageLabel: String?
    public var contextUsageFraction: Double?
    public var reasoningEffort: ReasoningEffort
    public var reasoningOptions: [ReasoningOptionViewState]
    public var changedFileSummary: String?
    public var permissionPrompt: PermissionPromptViewState?
    public var questionPrompt: QuestionPromptViewState?
    public var attachments: [PromptComposerAttachmentViewState]
    public var promptSuggestions: [PromptSuggestionViewState]
    public var queuedPrompts: [QueuedPromptViewState]
    public var onSend: @MainActor () -> Void
    public var onCancel: @MainActor () -> Void
    public var onSelectModel: @MainActor () -> Void
    public var onSelectModelID: @MainActor (String) -> Void
    public var onSelectAgent: @MainActor (String) -> Void
    public var onSelectReasoningEffort: @MainActor (ReasoningEffort) -> Void
    public var onPlus: @MainActor () -> Void
    public var onRemoveAttachment: @MainActor (UUID) -> Void
    public var onResolvePermission: @MainActor (PermissionPromptAction) -> Void
    public var onAnswerQuestion: @MainActor (String) -> Void
    public var onCancelQuestion: @MainActor () -> Void
    public var onReviewChangedFiles: @MainActor () -> Void
    public var onRevertSnapshot: @MainActor (String) -> Void
    @FocusState private var isDraftFocused: Bool
    @State private var isModelPickerSheetPresented = false
    @State private var isReasoningPickerPresented = false
    private let bottomAnchorID = "chat-bottom-anchor"

    public init(
        messages: [ChatMessageViewState],
        draft: Binding<String>,
        focusTarget: WorkspaceFocusTarget = .none,
        modelName: String = "",
        modelStatus: ModelLoadStatus = .idle,
        modelDownloadProgress: ModelDownloadProgressViewState? = nil,
        availableModels: [String] = [],
        agentName: String = "General",
        agentItems: [AgentSwitcherItemViewState] = [],
        selectedAgentID: String? = nil,
        preferences: ChatSurfacePreferences = ChatSurfacePreferences(),
        showsWorkspaceComposerControls: Bool = true,
        contextUsageLabel: String? = nil,
        contextUsageFraction: Double? = nil,
        reasoningEffort: ReasoningEffort = .none,
        reasoningOptions: [ReasoningOptionViewState] = [],
        changedFileSummary: String? = nil,
        permissionPrompt: PermissionPromptViewState? = nil,
        questionPrompt: QuestionPromptViewState? = nil,
        attachments: [PromptComposerAttachmentViewState] = [],
        promptSuggestions: [PromptSuggestionViewState] = PromptSuggestionModel.defaults,
        queuedPrompts: [QueuedPromptViewState] = [],
        onSend: @escaping @MainActor () -> Void,
        onCancel: @escaping @MainActor () -> Void,
        onSelectModel: @escaping @MainActor () -> Void = {},
        onSelectModelID: @escaping @MainActor (String) -> Void = { _ in },
        onSelectAgent: @escaping @MainActor (String) -> Void = { _ in },
        onSelectReasoningEffort: @escaping @MainActor (ReasoningEffort) -> Void = { _ in },
        onPlus: @escaping @MainActor () -> Void = {},
        onRemoveAttachment: @escaping @MainActor (UUID) -> Void = { _ in },
        onResolvePermission: @escaping @MainActor (PermissionPromptAction) -> Void = { _ in },
        onAnswerQuestion: @escaping @MainActor (String) -> Void = { _ in },
        onCancelQuestion: @escaping @MainActor () -> Void = {},
        onReviewChangedFiles: @escaping @MainActor () -> Void = {},
        onRevertSnapshot: @escaping @MainActor (String) -> Void = { _ in }
    ) {
        self.messages = messages
        self._draft = draft
        self.focusTarget = focusTarget
        self.modelName = modelName
        self.modelStatus = modelStatus
        self.modelDownloadProgress = modelDownloadProgress
        self.availableModels = availableModels
        self.agentName = agentName
        self.agentItems = agentItems
        self.selectedAgentID = selectedAgentID
        self.preferences = preferences
        self.showsWorkspaceComposerControls = showsWorkspaceComposerControls
        self.contextUsageLabel = contextUsageLabel
        self.contextUsageFraction = contextUsageFraction
        self.reasoningEffort = reasoningEffort
        self.reasoningOptions = reasoningOptions
        self.changedFileSummary = changedFileSummary
        self.permissionPrompt = permissionPrompt
        self.questionPrompt = questionPrompt
        self.attachments = attachments
        self.promptSuggestions = promptSuggestions
        self.queuedPrompts = queuedPrompts
        self.onSend = onSend
        self.onCancel = onCancel
        self.onSelectModel = onSelectModel
        self.onSelectModelID = onSelectModelID
        self.onSelectAgent = onSelectAgent
        self.onSelectReasoningEffort = onSelectReasoningEffort
        self.onPlus = onPlus
        self.onRemoveAttachment = onRemoveAttachment
        self.onResolvePermission = onResolvePermission
        self.onAnswerQuestion = onAnswerQuestion
        self.onCancelQuestion = onCancelQuestion
        self.onReviewChangedFiles = onReviewChangedFiles
        self.onRevertSnapshot = onRevertSnapshot
    }

    private var maxContentWidth: CGFloat {
        preferences.wideChatLayout ? 960 : 760
    }

    private var isWorking: Bool {
        messages.contains { $0.isStreaming }
    }

    private var isModelLoaded: Bool {
        modelStatus == .loaded
    }

    private var isComposerInputEnabled: Bool {
        isModelLoaded && !isWorking
    }

    private var isSendEnabled: Bool {
        isWorking || (isModelLoaded && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    /// Markdown is parsed only for finalized assistant messages. The still-streaming
    /// message renders as plain `Text` so the whole body isn't re-parsed (and
    /// `AttributedString(markdown:)` re-run per block) on every coalesced flush —
    /// which is O(n²) over a long answer. Mid-stream markdown is half-parsed anyway.
    public static func rendersMarkdown(for message: ChatMessageViewState) -> Bool {
        message.role == .assistant && !message.isStreaming
    }

    private var scrollSignature: Int {
        // O(messageCount) — `utf8.count` is O(1) — instead of building/joining a
        // whole-transcript string on every render (i.e. on every streamed chunk).
        var hasher = Hasher()
        hasher.combine(messages.count)
        for message in messages {
            hasher.combine(message.id)
            hasher.combine(message.text.utf8.count)
            hasher.combine(message.isStreaming)
        }
        hasher.combine(permissionPrompt?.id)
        hasher.combine(questionPrompt?.id)
        return hasher.finalize()
    }

    private var showsEmptyState: Bool {
        messages.isEmpty && permissionPrompt == nil && questionPrompt == nil
    }

    public var body: some View {
        VStack(spacing: 0) {
            if showsEmptyState {
                emptyState
            } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: .space4) {
                        ForEach(messages) { message in
                            messageRow(message)
                        }
                        inlineSettlementCards
                        Color.clear
                            .frame(height: 1)
                            .id(bottomAnchorID)
                    }
                    .frame(maxWidth: maxContentWidth)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, .space4)
                    .padding(.vertical, .space3)
                }
                .onAppear {
                    scrollToBottom(proxy, animated: false)
                }
                .onChange(of: scrollSignature) { _, _ in
                    scrollToBottom(proxy)
                }
            }
            }
            composer
        }
        .background(Theme.C.surface)
        .sheet(isPresented: $isModelPickerSheetPresented) {
            ComposerModelPickerSheet(
                selectedModelID: modelName,
                modelStatus: modelStatus,
                availableModels: availableModels,
                suggestedModels: suggestedDownloadModels,
                onSelectModelID: onSelectModelID,
                onOpenSettings: onSelectModel)
        }
        .onChange(of: focusTarget) { _, newValue in
            if newValue == .chat {
                isDraftFocused = true
            }
        }
    }

    // MARK: Empty / first-run state

    private var starterPrompts: [(symbol: String, label: String, insert: String)] {
        if showsWorkspaceComposerControls {
            return [
                ("magnifyingglass", "Explain this codebase", "Give me a high-level tour of this codebase — entry points, modules, and how they fit together."),
                ("ant", "Find a bug", "Look through the workspace for likely bugs or risky code and tell me what you find."),
                ("wand.and.stars", "Refactor a file", "Suggest a clean refactor for "),
                ("testtube.2", "Write tests", "Write unit tests for "),
            ]
        }
        return [
            ("text.alignleft", "Summarize text", "Summarize the following:\n\n"),
            ("chevron.left.forwardslash.chevron.right", "Write code", "Write a function that "),
            ("lightbulb", "Brainstorm", "Help me brainstorm ideas about "),
            ("questionmark.circle", "Explain a concept", "Explain how "),
        ]
    }

    private func runStarter(_ insert: String) {
        draft = insert
        isDraftFocused = true
    }

    private var emptyState: some View {
        VStack(spacing: .space4) {
            Spacer(minLength: 0)

            VStack(spacing: .space2) {
                HStack(spacing: 6) {
                    Text("interless")
                        .font(.system(.largeTitle, design: .monospaced).weight(.bold))
                        .foregroundStyle(Theme.C.textPrimary)
                    Text("›")
                        .font(.system(.largeTitle, design: .monospaced).weight(.bold))
                        .foregroundStyle(Theme.C.phosphor)
                    BlinkingCaret(width: 11, height: 24)
                }
                Text(isModelLoaded
                     ? "Ready. Ask anything, or pick a starting point below."
                     : "Select a model to begin — open Settings or the model menu in the composer.")
                    .font(.metaMono)
                    .foregroundStyle(Theme.C.textTertiary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: .space2) {
                ForEach(starterPrompts, id: \.label) { starter in
                    Button { runStarter(starter.insert) } label: {
                        HStack(spacing: .space2) {
                            Image(systemName: starter.symbol)
                                .font(.metaMono)
                                .foregroundStyle(Theme.C.phosphor)
                                .frame(width: 18)
                            Text(starter.label)
                                .font(.bodyS.weight(.medium))
                                .foregroundStyle(Theme.C.textPrimary)
                            Spacer(minLength: .space3)
                            Image(systemName: "arrow.up.left")
                                .font(.controlGlyphSm)
                                .foregroundStyle(Theme.C.textTertiary)
                                .accessibilityHidden(true)
                        }
                        .padding(.horizontal, .space3)
                        .padding(.vertical, .space2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card()
                    }
                    .buttonStyle(.plain)
                    .disabled(!isModelLoaded)
                    .opacity(isModelLoaded ? 1 : 0.5)
                }
            }
            .frame(maxWidth: 360)

            HStack(spacing: .space3) {
                keyHint("return", "send")
                keyHint("⌃⌘S", "sidebar")
                keyHint("⌘,", "settings")
            }
            .padding(.top, .space1)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.space5)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Interless — start a conversation")
    }

    private func keyHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(key)
                .font(.metaMonoSm)
                .foregroundStyle(Theme.C.textSecondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Theme.C.surface2, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(Theme.C.border, lineWidth: 1))
            Text(label)
                .font(.metaMono)
                .foregroundStyle(Theme.C.textTertiary)
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        Task { @MainActor in
            await Task.yield()
            if animated {
                withAnimation(.easeOut(duration: 0.16)) {
                    proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(bottomAnchorID, anchor: .bottom)
            }
        }
    }

    // MARK: Messages

    @ViewBuilder
    private func messageRow(_ message: ChatMessageViewState) -> some View {
        if let summary = message.toolSummary {
            changedFilesCard(summary)
        } else if message.isToolEvent && message.isCollapsed {
            HStack(spacing: 6) {
                Image(systemName: "wrench.and.screwdriver")
                Text(message.text).lineLimit(1)
                Spacer()
            }
            .font(.metaMono)
            .foregroundStyle(Theme.C.textTertiary)
            .padding(.horizontal, .space3)
            .padding(.vertical, .space2)
            .background(Theme.C.surface2, in: RoundedRectangle(cornerRadius: .radiusSm, style: .continuous))
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if message.role == .user {
            // Right-aligned chat bubble.
            let text = renderedMessageText(message)
            HStack {
                Spacer(minLength: 48)
                VStack(alignment: .trailing, spacing: .space1) {
                    messageText(text)
                        .font(.bodyS)
                        .foregroundStyle(Theme.C.textPrimary)
                        .textSelection(.enabled)
                        .padding(.horizontal, .space3)
                        .padding(.vertical, .space2)
                        .background(Theme.C.accentGlow, in: RoundedRectangle(cornerRadius: .radius, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: .radius, style: .continuous)
                                .stroke(Theme.C.border, lineWidth: 1)
                        }
                    footer(message, alignment: .trailing)
                }
            }
        } else {
            // Assistant / error / system: plain on the background, full width.
            let text = renderedMessageText(message)
            VStack(alignment: .leading, spacing: .space2) {
                if message.role == .assistant {
                    assistantHeader(message)
                }
                if Self.rendersMarkdown(for: message) {
                    MarkdownMessageView(text)
                } else {
                    Text(text)
                        .font(.bodyS)
                        .foregroundStyle(message.role == .error ? Theme.C.danger : Theme.C.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if message.isStreaming {
                    HStack(spacing: 6) {
                        Text("generating")
                            .font(.metaMono)
                            .foregroundStyle(Theme.C.phosphor)
                            .pulsing()
                        BlinkingCaret(width: 7, height: 13)
                    }
                }
                footer(message, alignment: .leading)
            }
        }
    }

    private func renderedMessageText(_ message: ChatMessageViewState) -> String {
        let trimmed = ReasoningOutputSanitizer.visibleText(
            message.text,
            reasoningEffort: message.reasoningEffort)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "…" : trimmed
    }

    private func changedFilesCard(_ summary: ChatToolSummaryViewState) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: .space3) {
                Image(systemName: "plus.app")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.C.textPrimary)
                    .frame(width: 38, height: 38)
                    .background(Theme.C.surface2, in: RoundedRectangle(cornerRadius: .radiusSm, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(summary.title)
                        .font(.bodyS.weight(.semibold))
                        .foregroundStyle(Theme.C.textPrimary)
                    if let subtitle = summary.subtitle {
                        Text(subtitle)
                            .font(.metaMono)
                            .foregroundStyle(Theme.C.success)
                    }
                }
                Spacer()
                if summary.canUndo, let snapshotID = summary.snapshotID {
                    Button("Undo") {
                        onRevertSnapshot(snapshotID)
                    }
                    .buttonStyle(.borderless)
                }
                if summary.canReview {
                    Button("Review") {
                        onReviewChangedFiles()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.space3)

            Divider().overlay(Theme.C.border)

            VStack(spacing: 0) {
                ForEach(summary.files) { file in
                    changedFileRow(file)
                }
            }
        }
        .background(Theme.C.surface, in: RoundedRectangle(cornerRadius: .radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: .radius, style: .continuous)
                .stroke(Theme.C.border, lineWidth: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func changedFileRow(_ file: ChangedFileSummaryViewState) -> some View {
        HStack(spacing: .space2) {
            Text(file.operation == "created" ? "Created" : "Edited")
                .font(.metaMono)
                .foregroundStyle(file.operation == "created" ? Theme.C.success : Theme.C.caution)
                .frame(width: 52, alignment: .leading)
            Text(file.path)
                .font(.bodyS)
                .foregroundStyle(Theme.C.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if let additions = file.additions, let deletions = file.deletions {
                HStack(spacing: .space1) {
                    Text("+\(additions)")
                        .foregroundStyle(Theme.C.success)
                    Text("-\(deletions)")
                        .foregroundStyle(Theme.C.danger)
                }
                .font(.metaMono)
            }
        }
        .padding(.horizontal, .space3)
        .padding(.vertical, .space2)
    }

    /// Renders user-message body honoring the Markdown / plain-text preference.
    /// `inlineOnlyPreservingWhitespace` keeps line breaks while rendering inline
    /// styles (bold, italic, `code`, links) — the safe choice for chat.
    @ViewBuilder
    private func messageText(_ text: String) -> some View {
        if preferences.userMessageRendering == .markdown,
           let attributed = try? AttributedString(
               markdown: text,
               options: AttributedString.MarkdownParsingOptions(
                   interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            Text(attributed)
        } else {
            Text(text)
        }
    }

    private func assistantHeader(_ message: ChatMessageViewState) -> some View {
        HStack(spacing: .space2) {
            Text(assistantModelName(for: message))
                .font(.bodyS.weight(.semibold))
                .foregroundStyle(Theme.C.textPrimary)
                .lineLimit(1)
            Text(agentName)
                .font(.metaMono)
                .foregroundStyle(Theme.C.phosphor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.C.phosphorGlow, in: Capsule())
                .overlay(Capsule().stroke(Theme.C.phosphor.opacity(0.35), lineWidth: 1))
            if preferences.showReasoningTraces {
                Text("reasoning: \(assistantReasoningLabel(for: message))")
                    .font(.metaMono)
                    .foregroundStyle(Theme.C.textTertiary)
            }
        }
    }

    private func assistantModelName(for message: ChatMessageViewState) -> String {
        if let modelID = message.modelID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !modelID.isEmpty {
            return displayName(for: modelID)
        }
        if message.isStreaming, !modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return displayName(for: modelName)
        }
        return "Unknown model"
    }

    private func assistantReasoningLabel(for message: ChatMessageViewState) -> String {
        guard let effort = message.reasoningEffort else { return "unknown" }
        return effort.displayName.lowercased()
    }

    private func footer(_ message: ChatMessageViewState, alignment: HorizontalAlignment) -> some View {
        let copyText = ReasoningOutputSanitizer.visibleText(
            message.text,
            reasoningEffort: message.reasoningEffort)
        return HStack(spacing: .space2) {
            if alignment == .trailing { copyButton(copyText) }
            Text(message.timestamp.formatted(.dateTime.weekday(.wide).hour().minute()))
                .font(.metaMono)
                .foregroundStyle(Theme.C.textTertiary)
            if let tokensPerSecond = message.tokensPerSecond, tokensPerSecond.isFinite, tokensPerSecond > 0 {
                Text("· \(Self.formatTokensPerSecond(tokensPerSecond)) tok/s")
                    .font(.metaMono)
                    .foregroundStyle(Theme.C.textTertiary)
            }
            if Self.isTokenLimitStop(message.completionStopReason) {
                Text("· token limit")
                    .font(.metaMono)
                    .foregroundStyle(Theme.C.accent)
            }
            if alignment == .leading { copyButton(copyText) }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .trailing ? .trailing : .leading)
    }

    private static func isTokenLimitStop(_ reason: String?) -> Bool {
        guard let reason = reason?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !reason.isEmpty else { return false }
        return reason.contains("length")
            || reason.contains("max")
            || reason.contains("token")
    }

    private static func formatTokensPerSecond(_ value: Double) -> String {
        if value >= 100 {
            return String(format: "%.0f", value)
        }
        if value >= 10 {
            return String(format: "%.1f", value)
        }
        return String(format: "%.2f", value)
    }

    private func copyButton(_ text: String) -> some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        } label: {
            Image(systemName: "doc.on.doc")
                .font(.caption2)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.C.textTertiary)
        .help("Copy message")
    }

    @ViewBuilder
    private var inlineSettlementCards: some View {
        if let permissionPrompt {
            PermissionPromptView(state: permissionPrompt, onDecision: onResolvePermission)
                .frame(maxWidth: 520, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        if let questionPrompt {
            QuestionPromptView(
                state: questionPrompt,
                onAnswer: onAnswerQuestion,
                onCancel: onCancelQuestion)
                .frame(maxWidth: 520, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: .space1) {
            changedFilesBar
            VStack(alignment: .leading, spacing: 0) {
                composerPrelude
                TextField(
                    "",
                    text: $draft,
                    prompt: Text(composerPlaceholder)
                        .foregroundStyle(Theme.C.textTertiary),
                    axis: .vertical)
                    .lineLimit(1...6)
                    .textFieldStyle(.plain)
                    .font(.bodyS.weight(.medium))
                    .foregroundStyle(isModelLoaded ? Theme.C.textPrimary : Theme.C.textTertiary)
                    .tint(Theme.C.phosphor)   // live caret — the cursor is "alive"
                    .focused($isDraftFocused)
                    .disabled(!isComposerInputEnabled)
                    .onSubmit {
                        if isSendEnabled, !isWorking {
                            onSend()
                        }
                    }
                    .frame(minHeight: 48, alignment: .topLeading)
                    .padding(.horizontal, .space3)
                    .padding(.top, 10)
                    .opacity(isModelLoaded ? 1 : 0.55)

                HStack(alignment: .center, spacing: 3) {
                    composerActionButtons
                    Spacer(minLength: 6)
                    composerControls
                }
                .padding(.horizontal, 9)
                .padding(.bottom, .space2)
            }
            .background(Theme.C.surface, in: RoundedRectangle(cornerRadius: .radiusLg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: .radiusLg, style: .continuous)
                    .stroke(isDraftFocused ? Theme.C.accent.opacity(0.58) : Theme.C.borderHover, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: .radiusLg, style: .continuous))
            .onTapGesture {
                if isComposerInputEnabled {
                    isDraftFocused = true
                }
            }
        }
        .frame(maxWidth: composerMaxWidth)
        .frame(maxWidth: .infinity)                   // centered in the pane
        .padding(.horizontal, .space3)
        .padding(.bottom, .space3)
    }

    @ViewBuilder
    private var changedFilesBar: some View {
        if showsWorkspaceComposerControls, let changedFileSummary, !changedFileSummary.isEmpty {
            HStack(spacing: 5) {
                Image(systemName: "square.and.pencil")
                    .font(.metaMonoSm)
                    .foregroundStyle(Theme.C.accent)
                Text(changedFilesText.prefix)
                    .font(.metaMonoSm)
                    .foregroundStyle(Theme.C.textSecondary)
                    .lineLimit(1)
                if let additions = changedFilesText.additions {
                    Text(additions)
                        .font(.metaMonoSm)
                        .foregroundStyle(Theme.C.diffAdd)
                        .lineLimit(1)
                }
                if let deletions = changedFilesText.deletions {
                    Text(deletions)
                        .font(.metaMonoSm)
                        .foregroundStyle(Theme.C.diffDel)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.down")
                    .font(.controlGlyphSm)
                    .foregroundStyle(Theme.C.textTertiary)
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, .space2)
        }
    }

    @ViewBuilder
    private var composerPrelude: some View {
        let suggestions = visiblePromptSuggestions
        if !attachments.isEmpty || !queuedPrompts.isEmpty || !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: .space1) {
                if !attachments.isEmpty {
                    horizontalChips {
                        ForEach(attachments) { attachment in
                            attachmentChip(attachment)
                        }
                    }
                }
                if !queuedPrompts.isEmpty {
                    horizontalChips {
                        ForEach(queuedPrompts) { queued in
                            queuedPromptChip(queued)
                        }
                    }
                }
                if !suggestions.isEmpty {
                    horizontalChips {
                        ForEach(suggestions) { suggestion in
                            suggestionChip(suggestion)
                        }
                    }
                }
            }
            .padding(.horizontal, .space3)
            .padding(.top, .space2)
        }
    }

    private func horizontalChips<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 3) {
                content()
            }
        }
    }

    private var visiblePromptSuggestions: [PromptSuggestionViewState] {
        guard showsWorkspaceComposerControls else { return [] }
        return Array(PromptSuggestionModel.suggestions(for: draft, candidates: promptSuggestions).prefix(6))
    }

    private func suggestionChip(_ suggestion: PromptSuggestionViewState) -> some View {
        Button {
            insertSuggestion(suggestion)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: suggestion.kind.symbolName)
                Text(suggestion.title)
                if let detail = suggestion.detail {
                    Text(detail)
                        .foregroundStyle(Theme.C.textTertiary)
                        .lineLimit(1)
                }
            }
            .font(.metaMonoSm)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.primary.opacity(0.06), in: Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.C.textSecondary)
        .help(suggestion.detail ?? suggestion.title)
    }

    private func attachmentChip(_ attachment: PromptComposerAttachmentViewState) -> some View {
        HStack(spacing: .space1) {
            Image(systemName: "paperclip")
            Text(attachment.name)
                .lineLimit(1)
            if !attachment.detail.isEmpty {
                Text(attachment.detail)
                    .foregroundStyle(Theme.C.textTertiary)
                    .lineLimit(1)
            }
            Button {
                onRemoveAttachment(attachment.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove attachment")
        }
        .font(.metaMonoSm)
        .foregroundStyle(Theme.C.textSecondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.primary.opacity(0.06), in: Capsule())
    }

    private func queuedPromptChip(_ queued: QueuedPromptViewState) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "clock")
            Text(queued.title)
                .lineLimit(1)
            Text(queued.delivery)
                .foregroundStyle(Theme.C.textTertiary)
        }
        .font(.metaMonoSm)
        .foregroundStyle(Theme.C.textSecondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.primary.opacity(0.06), in: Capsule())
    }

    private func insertSuggestion(_ suggestion: PromptSuggestionViewState) {
        let insertion = suggestion.insertionText
        guard !insertion.isEmpty else { return }
        if draft.isEmpty || draft.hasSuffix(" ") || draft.hasSuffix("\n") {
            draft += insertion
        } else {
            draft += " \(insertion)"
        }
        isDraftFocused = true
    }

    private var shortModelName: String {
        if modelStatus == .loading {
            return modelDownloadProgress?.statusText ?? "Loading model..."
        }
        if modelStatus == .cancelling {
            return "Switching model..."
        }
        guard isModelLoaded else {
            return "Select a model"
        }
        let base = modelName.split(separator: "/").last.map(String.init) ?? modelName
        return base.isEmpty ? "Select a model" : base
    }

    private var composerPlaceholder: String {
        guard isModelLoaded else { return "Select a model to start" }
        return showsWorkspaceComposerControls
            ? "@ for files/agents; / for commands and skills; ! for shell; # for snippets"
            : "Message Interless"
    }

    private var composerMaxWidth: CGFloat {
        preferences.wideChatLayout ? 960 : 780
    }

    private var changedFilesText: (prefix: String, additions: String?, deletions: String?) {
        guard let changedFileSummary else { return ("", nil, nil) }
        let parts = changedFileSummary.split(separator: " ").map(String.init)
        guard parts.count >= 3,
              let deletionToken = parts.last,
              deletionToken.hasPrefix("-"),
              let additionToken = parts.dropLast().last,
              additionToken.hasPrefix("+")
        else {
            return (changedFileSummary, nil, nil)
        }
        let prefix = parts.dropLast(2).joined(separator: " ")
        return (prefix, additionToken, deletionToken)
    }

    private var composerControls: some View {
        HStack(spacing: 5) {
            contextUsageStatus
            reasoningPickerButton
            modelPickerButton
            if showsWorkspaceComposerControls {
                agentPickerButton
            }

            Button {
                if isWorking { onCancel() } else { onSend() }
            } label: {
                Image(systemName: isWorking ? "stop.fill" : "paperplane")
                    .font(.system(size: 11.25, weight: .medium))
                    .foregroundStyle(isSendEnabled ? Theme.C.accent : Theme.C.textTertiary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!isSendEnabled)
            .help(isWorking ? "Stop" : "Send")
        }
    }

    private var contextUsageStatus: some View {
        HStack(spacing: .space1) {
            ZStack {
                Circle()
                    .stroke(Theme.C.textTertiary.opacity(0.34), lineWidth: 1.8)
                Circle()
                    .trim(from: 0, to: contextUsageDisplay.fraction)
                    .stroke(
                        contextUsageDisplay.fraction >= 0.85 ? Theme.C.accent : Theme.C.phosphor,
                        style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 10, height: 10)

            Text(contextUsageDisplay.label)
                .font(.metaMonoSm)
                .foregroundStyle(Theme.C.textSecondary)
                .lineLimit(1)
        }
        .frame(height: 18)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Context window usage \(contextUsageDisplay.label)")
        .help("Context window usage")
    }

    private var contextUsageDisplay: (label: String, fraction: Double) {
        let fraction = Self.clampedContextFraction(
            contextUsageFraction ?? Self.fraction(fromPercentLabel: contextUsageLabel) ?? 0)
        let label = contextUsageLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let label, !label.isEmpty {
            return (label, fraction)
        }
        return (Self.formatContextUsage(fraction), fraction)
    }

    private var effectiveReasoningOptions: [ReasoningOptionViewState] {
        if !reasoningOptions.isEmpty {
            return reasoningOptions
        }
        return ReasoningOptionViewState.options(for: modelName, selected: reasoningEffort)
    }

    private var effectiveReasoningEffort: ReasoningEffort {
        if let selected = effectiveReasoningOptions.first(where: \.isSelected)?.effort {
            return selected
        }
        return ReasoningEffort.resolved(reasoningEffort, for: modelName)
    }

    private var reasoningPickerButton: some View {
        Button {
            isReasoningPickerPresented.toggle()
        } label: {
            HStack(spacing: .space1) {
                Image(systemName: "gearshape.fill")
                    .font(.controlGlyph)
                Text("Reasoning: \(effectiveReasoningEffort.displayName)")
                    .font(.metaMonoSm)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .foregroundStyle(Theme.C.accent2)
            .frame(height: 18)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .popover(isPresented: $isReasoningPickerPresented, arrowEdge: .bottom) {
            reasoningPickerPopover
        }
        .help("Reasoning mode")
    }

    private var reasoningPickerPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Reasoning")
                    .font(.bodyS.weight(.semibold))
                    .foregroundStyle(Theme.C.textPrimary)
                Text(reasoningSupportDetail)
                    .font(.metaMono)
                    .foregroundStyle(Theme.C.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, .space3)
            .padding(.vertical, .space3)

            Divider()

            ForEach(effectiveReasoningOptions) { option in
                Button {
                    onSelectReasoningEffort(option.effort)
                    isReasoningPickerPresented = false
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: .space2) {
                        Image(systemName: option.isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(option.isSelected ? Theme.C.accent2 : Theme.C.textTertiary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.title)
                                .font(.bodyS.weight(.semibold))
                                .foregroundStyle(Theme.C.textPrimary)
                            Text(option.detail)
                                .font(.metaMono)
                                .foregroundStyle(Theme.C.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: .space3)
                    }
                    .padding(.horizontal, .space3)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 320)
        .background(.regularMaterial)
        .presentationBackground(.regularMaterial)
    }

    private var reasoningSupportDetail: String {
        if effectiveReasoningOptions.count <= 1 {
            return "The selected model does not advertise reasoning controls."
        }
        return "Valid options for the selected model."
    }

    private var composerActionButtons: some View {
        HStack(spacing: 7) {
            smallComposerButton("plus.circle", "Add context", action: onPlus)
            if showsWorkspaceComposerControls {
                smallComposerButton("arrow.up.left.and.arrow.down.right", "Expand composer", action: {})
                    .disabled(true)
                smallComposerButton("shield.lefthalf.filled", "Tool permissions", action: {})
                    .disabled(true)
            }
        }
    }

    private func smallComposerButton(_ symbolName: String, _ help: String, action: @escaping @MainActor () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbolName)
                .font(.system(size: 11.25, weight: .medium))
                .foregroundStyle(Theme.C.textSecondary)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private static func clampedContextFraction(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    private static func fraction(fromPercentLabel label: String?) -> Double? {
        guard let raw = label?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else { return nil }
        let numeric = raw
            .replacingOccurrences(of: "%", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(numeric) else { return nil }
        return value / 100
    }

    private static func formatContextUsage(_ fraction: Double) -> String {
        let percent = clampedContextFraction(fraction) * 100
        if percent >= 10 {
            return "\(Int(percent.rounded()))%"
        }
        return String(format: "%.1f%%", percent)
    }

    private var agentPickerButton: some View {
        Menu {
            ForEach(effectiveAgentItems) { agent in
                Button {
                    onSelectAgent(agent.id)
                } label: {
                    Label(agent.title, systemImage: selectedAgentID == agent.id ? "checkmark" : "person")
                }
                .disabled(!agent.isEnabled)
            }
        } label: {
            HStack(spacing: .space1) {
                Image(systemName: "person.crop.circle")
                    .font(.controlGlyph)
                Text(selectedComposerAgentTitle)
                    .font(.metaMonoSm)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.down")
                    .font(.controlGlyphSm)
                    .foregroundStyle(Theme.C.textTertiary)
            }
            .foregroundStyle(Theme.C.phosphor)
            .frame(height: 18)
            .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Agent")
    }

    private var effectiveAgentItems: [AgentSwitcherItemViewState] {
        if !agentItems.isEmpty {
            return agentItems
        }
        return [AgentSwitcherItemViewState(id: "general", title: agentName)]
    }

    private var selectedComposerAgentTitle: String {
        if let selectedAgentID,
           let selected = effectiveAgentItems.first(where: { $0.id == selectedAgentID }) {
            return selected.title
        }
        return effectiveAgentItems.first?.title ?? agentName
    }

    private func composerStatusButton(_ title: String, symbolName: String, foreground: Color, action: (@MainActor () -> Void)?) -> some View {
        Button {
            action?()
        } label: {
            HStack(spacing: .space1) {
                Image(systemName: symbolName)
                    .font(.system(size: 9, weight: .semibold))
                Text(title)
                    .font(.metaMonoSm)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .foregroundStyle(foreground)
            .frame(height: 18)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var suggestedDownloadModels: [String] {
        ComposerModelPickerModel.suggestedDownloadModelIDs.filter { !availableModels.contains($0) }
    }

    private var modelPickerButton: some View {
        Button {
            isModelPickerSheetPresented = true
        } label: {
            HStack(spacing: .space1) {
                Text(shortModelName)
                    .font(.metaMonoSm)
                    .foregroundStyle(Theme.C.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(height: 18)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .frame(maxWidth: 165)
        .help("Select downloaded model")
    }

    private func displayName(for id: String) -> String {
        id.split(separator: "/").last.map(String.init) ?? id
    }
}
