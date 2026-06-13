import Foundation
import Shared

public enum ChatMessageRole: String, Sendable, Equatable, Codable, CaseIterable {
    case user
    case assistant
    case tool
    case system
    case error
}

public struct ChatMessageViewState: Identifiable, Sendable, Equatable, Codable {
    public var id: UUID
    public var role: ChatMessageRole
    public var kind: String
    public var text: String
    public var isStreaming: Bool
    public var isCollapsed: Bool
    public var timestamp: Date
    public var tokensPerSecond: Double?
    public var completionStopReason: String?
    public var modelID: String?
    public var reasoningEffort: ReasoningEffort?
    public var toolSummary: ChatToolSummaryViewState?

    public init(
        id: UUID = UUID(),
        role: ChatMessageRole,
        kind: String = "text",
        text: String,
        isStreaming: Bool = false,
        isCollapsed: Bool = false,
        timestamp: Date = Date(),
        tokensPerSecond: Double? = nil,
        completionStopReason: String? = nil,
        modelID: String? = nil,
        reasoningEffort: ReasoningEffort? = nil,
        toolSummary: ChatToolSummaryViewState? = nil
    ) {
        self.id = id
        self.role = role
        self.kind = kind
        self.text = text
        self.isStreaming = isStreaming
        self.isCollapsed = isCollapsed
        self.timestamp = timestamp
        self.tokensPerSecond = tokensPerSecond
        self.completionStopReason = completionStopReason
        self.modelID = modelID
        self.reasoningEffort = reasoningEffort
        self.toolSummary = toolSummary
    }

    public var isToolEvent: Bool {
        role == .tool
    }

    private enum CodingKeys: String, CodingKey {
        case id, role, kind, text, isStreaming, isCollapsed, timestamp, tokensPerSecond
        case completionStopReason, modelID, reasoningEffort, toolSummary
    }

    // Backward-compatible: persisted history without a timestamp still decodes.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        role = try c.decode(ChatMessageRole.self, forKey: .role)
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "text"
        text = try c.decode(String.self, forKey: .text)
        isStreaming = try c.decodeIfPresent(Bool.self, forKey: .isStreaming) ?? false
        isCollapsed = try c.decodeIfPresent(Bool.self, forKey: .isCollapsed) ?? false
        timestamp = try c.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
        tokensPerSecond = try c.decodeIfPresent(Double.self, forKey: .tokensPerSecond)
        completionStopReason = try c.decodeIfPresent(String.self, forKey: .completionStopReason)
        modelID = try c.decodeIfPresent(String.self, forKey: .modelID)
        reasoningEffort = try c.decodeIfPresent(ReasoningEffort.self, forKey: .reasoningEffort)
        toolSummary = try c.decodeIfPresent(ChatToolSummaryViewState.self, forKey: .toolSummary)
    }
}

public struct ChangedFileSummaryViewState: Identifiable, Sendable, Equatable, Codable {
    public var id: String { path }
    public var path: String
    public var operation: String
    public var additions: Int?
    public var deletions: Int?

    public init(
        path: String,
        operation: String,
        additions: Int? = nil,
        deletions: Int? = nil
    ) {
        self.path = path
        self.operation = operation
        self.additions = additions
        self.deletions = deletions
    }
}

public struct ChatToolSummaryViewState: Sendable, Equatable, Codable {
    public var title: String
    public var subtitle: String?
    public var files: [ChangedFileSummaryViewState]
    public var snapshotID: String?
    public var canReview: Bool
    public var canUndo: Bool

    public init(
        title: String,
        subtitle: String? = nil,
        files: [ChangedFileSummaryViewState],
        snapshotID: String? = nil,
        canReview: Bool = true,
        canUndo: Bool = false
    ) {
        self.title = title
        self.subtitle = subtitle
        self.files = files
        self.snapshotID = snapshotID
        self.canReview = canReview
        self.canUndo = canUndo
    }
}

public struct ChatThreadViewState: Identifiable, Sendable, Equatable, Codable {
    public var id: UUID
    public var title: String
    public var subtitle: String?
    public var workspacePath: String?
    public var isSelected: Bool
    public var isDraft: Bool
    public var isPinned: Bool
    public var isArchived: Bool
    public var isInterrupted: Bool
    public var unreadCount: Int
    public var isActiveNow: Bool
    public var shortcut: String?

    public init(
        id: UUID = UUID(),
        title: String,
        subtitle: String? = nil,
        workspacePath: String? = nil,
        isSelected: Bool = false,
        isDraft: Bool = false,
        isPinned: Bool = false,
        isArchived: Bool = false,
        isInterrupted: Bool = false,
        unreadCount: Int = 0,
        isActiveNow: Bool = false,
        shortcut: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.workspacePath = workspacePath
        self.isSelected = isSelected
        self.isDraft = isDraft
        self.isPinned = isPinned
        self.isArchived = isArchived
        self.isInterrupted = isInterrupted
        self.unreadCount = max(0, unreadCount)
        self.isActiveNow = isActiveNow
        self.shortcut = shortcut
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, subtitle, workspacePath, isSelected, isDraft, isPinned, isArchived
        case isInterrupted, unreadCount, isActiveNow, shortcut
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle)
        workspacePath = try c.decodeIfPresent(String.self, forKey: .workspacePath)
        isSelected = try c.decodeIfPresent(Bool.self, forKey: .isSelected) ?? false
        isDraft = try c.decodeIfPresent(Bool.self, forKey: .isDraft) ?? false
        isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        isArchived = try c.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        isInterrupted = try c.decodeIfPresent(Bool.self, forKey: .isInterrupted) ?? false
        unreadCount = max(0, try c.decodeIfPresent(Int.self, forKey: .unreadCount) ?? 0)
        isActiveNow = try c.decodeIfPresent(Bool.self, forKey: .isActiveNow) ?? false
        shortcut = try c.decodeIfPresent(String.self, forKey: .shortcut)
    }
}

public enum SessionNavigatorItemKind: String, Sendable, Equatable, Codable, CaseIterable {
    case session
    case project
    case job
    case placeholder
}

public struct SessionNavigatorItemViewState: Identifiable, Sendable, Equatable, Codable {
    public var id: String
    public var kind: SessionNavigatorItemKind
    public var sessionID: UUID?
    public var title: String
    public var subtitle: String?
    public var relativeTime: String?
    public var groupLabel: String?
    public var branchLabel: String?
    public var changeSummary: String?
    public var symbolName: String
    public var isSelected: Bool
    public var isDraft: Bool
    public var isPinned: Bool
    public var isArchived: Bool
    public var isInterrupted: Bool
    public var unreadCount: Int
    public var isActiveNow: Bool
    public var isEnabled: Bool
    public var isMuted: Bool

    public init(
        id: String,
        kind: SessionNavigatorItemKind,
        sessionID: UUID? = nil,
        title: String,
        subtitle: String? = nil,
        relativeTime: String? = nil,
        groupLabel: String? = nil,
        branchLabel: String? = nil,
        changeSummary: String? = nil,
        symbolName: String,
        isSelected: Bool = false,
        isDraft: Bool = false,
        isPinned: Bool = false,
        isArchived: Bool = false,
        isInterrupted: Bool = false,
        unreadCount: Int = 0,
        isActiveNow: Bool = false,
        isEnabled: Bool = true,
        isMuted: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.sessionID = sessionID
        self.title = title
        self.subtitle = subtitle
        self.relativeTime = relativeTime
        self.groupLabel = groupLabel
        self.branchLabel = branchLabel
        self.changeSummary = changeSummary
        self.symbolName = symbolName
        self.isSelected = isSelected
        self.isDraft = isDraft
        self.isPinned = isPinned
        self.isArchived = isArchived
        self.isInterrupted = isInterrupted
        self.unreadCount = max(0, unreadCount)
        self.isActiveNow = isActiveNow
        self.isEnabled = isEnabled
        self.isMuted = isMuted
    }

    public init(thread: ChatThreadViewState, idPrefix: String, defaultSymbolName: String) {
        self.init(
            id: "\(idPrefix)-\(thread.id.uuidString)",
            kind: .session,
            sessionID: thread.isDraft ? nil : thread.id,
            title: thread.title,
            subtitle: thread.subtitle,
            relativeTime: thread.shortcut,
            groupLabel: thread.workspacePath.map { URL(fileURLWithPath: $0).lastPathComponent },
            symbolName: thread.isDraft ? "square.and.pencil" : defaultSymbolName,
            isSelected: thread.isSelected,
            isDraft: thread.isDraft,
            isPinned: thread.isPinned,
            isArchived: thread.isArchived,
            isInterrupted: thread.isInterrupted,
            unreadCount: thread.unreadCount,
            isActiveNow: thread.isActiveNow,
            isEnabled: true)
    }
}

public struct SessionNavigatorSectionViewState: Identifiable, Sendable, Equatable, Codable {
    public var id: String
    public var title: String
    public var subtitle: String?
    public var symbolName: String
    public var items: [SessionNavigatorItemViewState]
    public var isCollapsedByDefault: Bool

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        symbolName: String,
        items: [SessionNavigatorItemViewState],
        isCollapsedByDefault: Bool = false
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.symbolName = symbolName
        self.items = items
        self.isCollapsedByDefault = isCollapsedByDefault
    }
}

public enum SessionNavigatorModel {
    public static func sections(
        workspaceName: String,
        workspacePath: String?,
        projectThreads: [ChatThreadViewState],
        plainThreads: [ChatThreadViewState],
        jobs: [BackgroundToolJobViewState]
    ) -> [SessionNavigatorSectionViewState] {
        let projectItems = projectThreads.map {
            SessionNavigatorItemViewState(thread: $0, idPrefix: "project", defaultSymbolName: "bubble.left.and.bubble.right")
        }
        let plainItems = plainThreads.map {
            SessionNavigatorItemViewState(thread: $0, idPrefix: "plain", defaultSymbolName: "bubble")
        }
        let pinnedItems = (projectItems + plainItems).filter(\.isPinned)
        let interruptedItems = (projectItems + plainItems).filter(\.isInterrupted)
        let archivedItems = (projectItems + plainItems).filter(\.isArchived)
        let activeJobItems = jobs
            .filter { $0.status == .queued || $0.status == .running }
            .map {
                SessionNavigatorItemViewState(
                    id: "job-\($0.id.uuidString)",
                    kind: .job,
                    title: $0.title,
                    subtitle: $0.detail.isEmpty ? $0.status.rawValue : $0.detail,
                    relativeTime: $0.createdAt.formatted(.relative(presentation: .numeric)),
                    groupLabel: "job",
                    symbolName: $0.status == .running ? "play.circle" : "clock",
                    isActiveNow: $0.status == .running,
                    isEnabled: false,
                    isMuted: $0.status != .running)
            }

        var sections: [SessionNavigatorSectionViewState] = []
        if !pinnedItems.isEmpty {
            sections.append(.init(id: "pinned", title: "Pinned", symbolName: "pin", items: pinnedItems))
        }
        let recentItems = Array((projectItems + plainItems).prefix(8))
        if !recentItems.isEmpty {
            sections.append(.init(id: "recent", title: "Recent", symbolName: "clock", items: recentItems))
        }
        sections.append(.init(
            id: "workspace",
            title: workspaceName,
            subtitle: workspacePath,
            symbolName: workspacePath == nil ? "folder.badge.questionmark" : "folder",
            items: projectItems))
        sections.append(.init(
            id: "plain",
            title: "Plain Chats",
            symbolName: "bubble.left",
            items: plainItems,
            isCollapsedByDefault: false))
        if !interruptedItems.isEmpty {
            sections.append(.init(id: "interrupted", title: "Interrupted", symbolName: "pause.circle", items: interruptedItems))
        }
        if !activeJobItems.isEmpty {
            sections.append(.init(id: "active-jobs", title: "Active Jobs", symbolName: "bolt.horizontal", items: activeJobItems))
        }
        if !archivedItems.isEmpty {
            sections.append(.init(id: "archived", title: "Archived", symbolName: "archivebox", items: archivedItems, isCollapsedByDefault: true))
        }
        return sections
    }
}

public enum PromptSuggestionKind: String, Sendable, Equatable, Codable, CaseIterable {
    case file
    case agent
    case skill
    case snippet
    case command

    public var symbolName: String {
        switch self {
        case .file: return "doc.text"
        case .agent: return "person.2"
        case .skill: return "wand.and.stars"
        case .snippet: return "number"
        case .command: return "slash.circle"
        }
    }
}

public struct PromptSuggestionViewState: Identifiable, Sendable, Equatable, Codable {
    public var id: String
    public var kind: PromptSuggestionKind
    public var title: String
    public var insertionText: String
    public var detail: String?

    public init(id: String, kind: PromptSuggestionKind, title: String, insertionText: String, detail: String? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.insertionText = insertionText
        self.detail = detail
    }
}

public struct QueuedPromptViewState: Identifiable, Sendable, Equatable, Codable {
    public var id: UUID
    public var title: String
    public var delivery: String

    public init(id: UUID = UUID(), title: String, delivery: String = "queued") {
        self.id = id
        self.title = title
        self.delivery = delivery
    }
}

public enum ChatRenderMode: String, Sendable, Equatable, Codable, CaseIterable {
    case sorted
    case live
}

public enum UserMessageRenderingMode: String, Sendable, Equatable, Codable, CaseIterable {
    case markdown
    case plainText
}

public enum ChatDiffLayoutMode: String, Sendable, Equatable, Codable, CaseIterable {
    case dynamic
    case inline
    case sideBySide
}

public enum ChatDiffViewMode: String, Sendable, Equatable, Codable, CaseIterable {
    case singleFile
    case allFiles
}

public struct ChatSurfacePreferences: Sendable, Equatable, Codable {
    public var renderMode: ChatRenderMode
    public var userMessageRendering: UserMessageRenderingMode
    public var diffLayout: ChatDiffLayoutMode
    public var diffViewMode: ChatDiffViewMode
    public var showReasoningTraces: Bool
    public var stickyUserHeader: Bool
    public var wideChatLayout: Bool
    public var expandBashToolsByDefault: Bool
    public var expandEditToolsByDefault: Bool

    public init(
        renderMode: ChatRenderMode = .live,
        userMessageRendering: UserMessageRenderingMode = .plainText,
        diffLayout: ChatDiffLayoutMode = .inline,
        diffViewMode: ChatDiffViewMode = .allFiles,
        showReasoningTraces: Bool = true,
        stickyUserHeader: Bool = false,
        wideChatLayout: Bool = false,
        expandBashToolsByDefault: Bool = false,
        expandEditToolsByDefault: Bool = false
    ) {
        self.renderMode = renderMode
        self.userMessageRendering = userMessageRendering
        self.diffLayout = diffLayout
        self.diffViewMode = diffViewMode
        self.showReasoningTraces = showReasoningTraces
        self.stickyUserHeader = stickyUserHeader
        self.wideChatLayout = wideChatLayout
        self.expandBashToolsByDefault = expandBashToolsByDefault
        self.expandEditToolsByDefault = expandEditToolsByDefault
    }
}

public struct WorkspaceChromeViewState: Sendable, Equatable, Codable {
    public var title: String
    public var subtitle: String
    public var branchLabel: String?
    public var changeSummary: String?
    public var contextUsageLabel: String?
    public var contextUsageFraction: Double?
    public var runtimeLabel: String
    public var modelLabel: String
    public var isIndexing: Bool

    public init(
        title: String = "New Chat",
        subtitle: String = "No workspace",
        branchLabel: String? = nil,
        changeSummary: String? = nil,
        contextUsageLabel: String? = nil,
        contextUsageFraction: Double? = nil,
        runtimeLabel: String = "Local",
        modelLabel: String = "No model",
        isIndexing: Bool = false
    ) {
        self.title = title
        self.subtitle = subtitle
        self.branchLabel = branchLabel
        self.changeSummary = changeSummary
        self.contextUsageLabel = contextUsageLabel
        self.contextUsageFraction = contextUsageFraction
        self.runtimeLabel = runtimeLabel
        self.modelLabel = modelLabel
        self.isIndexing = isIndexing
    }
}

public struct ReasoningOptionViewState: Identifiable, Sendable, Equatable, Codable {
    public var effort: ReasoningEffort
    public var title: String
    public var detail: String
    public var isSelected: Bool

    public var id: String { effort.rawValue }

    public init(
        effort: ReasoningEffort,
        title: String? = nil,
        detail: String? = nil,
        isSelected: Bool = false
    ) {
        self.effort = effort
        self.title = title ?? effort.displayName
        self.detail = detail ?? effort.menuDetail
        self.isSelected = isSelected
    }

    public static func options(
        for modelID: String,
        selected selectedEffort: ReasoningEffort
    ) -> [ReasoningOptionViewState] {
        let resolved = ReasoningEffort.resolved(selectedEffort, for: modelID)
        return ReasoningEffort.options(for: modelID).map {
            ReasoningOptionViewState(effort: $0, isSelected: $0 == resolved)
        }
    }
}

public struct ChangedFileRowViewState: Identifiable, Sendable, Equatable, Codable {
    public var id: String
    public var path: String
    public var status: String
    public var additions: Int
    public var deletions: Int
    public var isStaged: Bool
    public var canRevert: Bool

    public init(
        id: String,
        path: String,
        status: String,
        additions: Int = 0,
        deletions: Int = 0,
        isStaged: Bool = false,
        canRevert: Bool = false
    ) {
        self.id = id
        self.path = path
        self.status = status
        self.additions = max(0, additions)
        self.deletions = max(0, deletions)
        self.isStaged = isStaged
        self.canRevert = canRevert
    }

    public init(file: DiffFile, isStaged: Bool = false) {
        let path = file.newPath.isEmpty ? file.oldPath : file.newPath
        let status: String
        if file.oldPath.isEmpty {
            status = "A"
        } else if file.newPath.isEmpty {
            status = "D"
        } else {
            status = "M"
        }
        self.init(
            id: "\(isStaged ? "staged" : "changed")-\(path)",
            path: path,
            status: status,
            additions: file.additions,
            deletions: file.deletions,
            isStaged: isStaged,
            canRevert: !isStaged)
    }
}

public struct InspectorGitViewState: Sendable, Equatable, Codable {
    public var branchLabel: String
    public var summary: String
    public var stagedFiles: [ChangedFileRowViewState]
    public var changedFiles: [ChangedFileRowViewState]
    public var canReviewDiff: Bool
    public var canCommit: Bool
    public var canSync: Bool

    public init(
        branchLabel: String = "workspace",
        summary: String = "Git status unavailable",
        stagedFiles: [ChangedFileRowViewState] = [],
        changedFiles: [ChangedFileRowViewState] = [],
        canReviewDiff: Bool = false,
        canCommit: Bool = false,
        canSync: Bool = false
    ) {
        self.branchLabel = branchLabel
        self.summary = summary
        self.stagedFiles = stagedFiles
        self.changedFiles = changedFiles
        self.canReviewDiff = canReviewDiff
        self.canCommit = canCommit
        self.canSync = canSync
    }

    public init(summary: String, diffFiles: [DiffFile], fallbackLines: [DiffLine]) {
        self.init(
            summary: summary,
            changedFiles: diffFiles.map { ChangedFileRowViewState(file: $0) },
            canReviewDiff: !diffFiles.isEmpty || !fallbackLines.isEmpty)
    }
}

public struct InspectorDiffViewState: Sendable, Equatable, Codable {
    public var files: [DiffFile]
    public var fallbackLines: [DiffLine]
    public var selectedFileID: String?
    public var viewMode: ChatDiffViewMode

    public init(
        files: [DiffFile] = [],
        fallbackLines: [DiffLine] = [],
        selectedFileID: String? = nil,
        viewMode: ChatDiffViewMode = .allFiles
    ) {
        self.files = files
        self.fallbackLines = fallbackLines
        self.selectedFileID = selectedFileID
        self.viewMode = viewMode
    }

    public var fileCount: Int {
        files.isEmpty && !fallbackLines.isEmpty ? 1 : files.count
    }
}

public struct SettingsSectionAvailability: Sendable, Equatable, Codable {
    public var sectionID: String
    public var isAvailable: Bool
    public var reason: String?

    public init(sectionID: String, isAvailable: Bool = true, reason: String? = nil) {
        self.sectionID = sectionID
        self.isAvailable = isAvailable
        self.reason = reason
    }
}

public struct ModelContextSettingsViewState: Sendable, Equatable, Codable {
    public static let answerTokenStep = 128
    public static let contextTokenStep = 1_024
    public static let minimumAnswerTokens = 128
    public static let maximumAnswerTokens = 32_768
    public static let minimumContextWindowTokens = 1_024
    public static let maximumContextWindowTokens = 131_072
    public static let answerTokenSnapDistance = answerTokenStep * 2
    public static let contextWindowTokenSnapDistance = contextTokenStep
    public static let classicAnswerTokenSteps = [
        0,
        1_024,
        2_048,
        4_096,
        8_192,
        16_384,
        32_768,
    ]
    public static let classicContextWindowTokenSteps = [
        0,
        1_024,
        2_048,
        4_096,
        8_192,
        16_384,
        32_768,
        65_536,
        131_072,
    ]

    public var plainChatMaxAnswerTokens: Int
    public var codeChatMaxAnswerTokens: Int
    public var plainChatMaxContextWindowTokens: Int
    public var codeChatMaxContextWindowTokens: Int
    public var plainChatContextMode: ConversationContextMode
    public var codeChatContextMode: ConversationContextMode

    public var maxContextWindowTokens: Int {
        get {
            codeChatMaxContextWindowTokens > 0
                ? codeChatMaxContextWindowTokens
                : plainChatMaxContextWindowTokens
        }
        set {
            let normalized = Self.normalizedContextTokenValue(newValue)
            plainChatMaxContextWindowTokens = normalized
            codeChatMaxContextWindowTokens = normalized
        }
    }

    public init(
        plainChatMaxAnswerTokens: Int = 0,
        codeChatMaxAnswerTokens: Int = 0,
        maxContextWindowTokens: Int = 0,
        plainChatMaxContextWindowTokens: Int? = nil,
        codeChatMaxContextWindowTokens: Int? = nil,
        plainChatContextMode: ConversationContextMode = .simple,
        codeChatContextMode: ConversationContextMode = .smart
    ) {
        let legacyContext = Self.normalizedContextTokenValue(maxContextWindowTokens)
        self.plainChatMaxAnswerTokens = Self.normalizedAnswerTokenValue(plainChatMaxAnswerTokens)
        self.codeChatMaxAnswerTokens = Self.normalizedAnswerTokenValue(codeChatMaxAnswerTokens)
        self.plainChatMaxContextWindowTokens = Self.normalizedContextTokenValue(plainChatMaxContextWindowTokens ?? legacyContext)
        self.codeChatMaxContextWindowTokens = Self.normalizedContextTokenValue(codeChatMaxContextWindowTokens ?? legacyContext)
        self.plainChatContextMode = plainChatContextMode
        self.codeChatContextMode = codeChatContextMode
    }

    public func normalized() -> ModelContextSettingsViewState {
        ModelContextSettingsViewState(
            plainChatMaxAnswerTokens: plainChatMaxAnswerTokens,
            codeChatMaxAnswerTokens: codeChatMaxAnswerTokens,
            plainChatMaxContextWindowTokens: plainChatMaxContextWindowTokens,
            codeChatMaxContextWindowTokens: codeChatMaxContextWindowTokens,
            plainChatContextMode: plainChatContextMode,
            codeChatContextMode: codeChatContextMode)
    }

    public func maxAnswerTokens(isPlainChat: Bool) -> Int? {
        let value = isPlainChat ? plainChatMaxAnswerTokens : codeChatMaxAnswerTokens
        return value > 0 ? value : nil
    }

    public var contextTokenBudgetOverride: Int? {
        contextTokenBudgetOverride(isPlainChat: false)
    }

    public func contextTokenBudgetOverride(isPlainChat: Bool) -> Int? {
        let value = isPlainChat ? plainChatMaxContextWindowTokens : codeChatMaxContextWindowTokens
        return value > 0 ? value : nil
    }

    public func conversationContextMode(isPlainChat: Bool) -> ConversationContextMode {
        isPlainChat ? plainChatContextMode : codeChatContextMode
    }

    public static func displayTokenValue(_ value: Int) -> String {
        value > 0 ? "\(value.formatted()) tokens" : "Automatic"
    }

    public static func nearestTokenStepIndex(for value: Int, in steps: [Int]) -> Int {
        guard !steps.isEmpty else { return 0 }
        var bestIndex = 0
        var bestDistance = abs(value - steps[0])
        for index in steps.indices.dropFirst() {
            let distance = abs(value - steps[index])
            if distance < bestDistance {
                bestIndex = index
                bestDistance = distance
            }
        }
        return bestIndex
    }

    public static func snappedTokenValue(_ value: Int, in steps: [Int], snapDistance: Int) -> Int {
        guard !steps.isEmpty, snapDistance >= 0 else { return value }
        let nearest = steps[nearestTokenStepIndex(for: value, in: steps)]
        return abs(value - nearest) <= snapDistance ? nearest : value
    }

    private static func normalizedAnswerTokenValue(_ value: Int) -> Int {
        guard value > 0 else { return 0 }
        return min(max(value, minimumAnswerTokens), maximumAnswerTokens)
    }

    private static func normalizedContextTokenValue(_ value: Int) -> Int {
        guard value > 0 else { return 0 }
        return min(max(value, minimumContextWindowTokens), maximumContextWindowTokens)
    }

    private enum CodingKeys: String, CodingKey {
        case plainChatMaxAnswerTokens
        case codeChatMaxAnswerTokens
        case maxContextWindowTokens
        case plainChatMaxContextWindowTokens
        case codeChatMaxContextWindowTokens
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyContext = try container.decodeIfPresent(Int.self, forKey: .maxContextWindowTokens) ?? 0
        self.init(
            plainChatMaxAnswerTokens: try container.decodeIfPresent(Int.self, forKey: .plainChatMaxAnswerTokens) ?? 0,
            codeChatMaxAnswerTokens: try container.decodeIfPresent(Int.self, forKey: .codeChatMaxAnswerTokens) ?? 0,
            maxContextWindowTokens: legacyContext,
            plainChatMaxContextWindowTokens: try container.decodeIfPresent(Int.self, forKey: .plainChatMaxContextWindowTokens),
            codeChatMaxContextWindowTokens: try container.decodeIfPresent(Int.self, forKey: .codeChatMaxContextWindowTokens))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(plainChatMaxAnswerTokens, forKey: .plainChatMaxAnswerTokens)
        try container.encode(codeChatMaxAnswerTokens, forKey: .codeChatMaxAnswerTokens)
        try container.encode(plainChatMaxContextWindowTokens, forKey: .plainChatMaxContextWindowTokens)
        try container.encode(codeChatMaxContextWindowTokens, forKey: .codeChatMaxContextWindowTokens)
    }
}

public enum PromptSuggestionModel {
    public static let defaults: [PromptSuggestionViewState] = [
        .init(id: "file", kind: .file, title: "@file", insertionText: "@", detail: "Add a file or folder"),
        .init(id: "agent", kind: .agent, title: "@agent", insertionText: "@agent ", detail: "Route to an agent"),
        .init(id: "skill", kind: .skill, title: "/skill", insertionText: "/skill ", detail: "Run a native skill"),
        .init(id: "snippet", kind: .snippet, title: "#snippet", insertionText: "#", detail: "Insert reusable context"),
        .init(id: "command", kind: .command, title: "/command", insertionText: "/", detail: "Use a prompt command"),
    ]

    public static func suggestions(for draft: String, candidates: [PromptSuggestionViewState] = defaults) -> [PromptSuggestionViewState] {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return candidates }
        let token = trimmed.split(whereSeparator: \.isWhitespace).last.map(String.init) ?? trimmed
        guard token.hasPrefix("@") || token.hasPrefix("/") || token.hasPrefix("#") else { return [] }
        return candidates.filter {
            $0.title.localizedCaseInsensitiveContains(token)
                || $0.insertionText.localizedCaseInsensitiveContains(token)
                || ($0.detail?.localizedCaseInsensitiveContains(token) ?? false)
        }
    }
}

public enum WorkspaceInspectorTab: String, Sendable, Equatable, Codable, CaseIterable, Identifiable {
    case git
    case files
    case context
    case diff
    case todos
    case jobs
    case timeline
    case history

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .git: return "Git"
        case .files: return "Files"
        case .context: return "Context"
        case .diff: return "Diff"
        case .todos: return "Todos"
        case .jobs: return "Jobs"
        case .timeline: return "Timeline"
        case .history: return "History"
        }
    }

    public var symbolName: String {
        switch self {
        case .git: return "point.3.connected.trianglepath.dotted"
        case .files: return "folder"
        case .context: return "doc.text"
        case .diff: return "plus.forwardslash.minus"
        case .todos: return "checklist"
        case .jobs: return "bolt.horizontal"
        case .timeline: return "clock"
        case .history: return "arrow.counterclockwise"
        }
    }
}

public enum SettingsHubSection: String, Sendable, Equatable, Codable, CaseIterable, Identifiable {
    case appearance
    case chat
    case modelContext
    case notifications
    case sessions
    case shortcuts
    case git
    case magicPrompts
    case projects
    case agents
    case behavior
    case commands
    case mcp
    case providers
    case usage
    case skills
    case skillsCatalog

    public var id: String { rawValue }

    public static let visibleCases: [SettingsHubSection] = [
        .appearance,
        .chat,
        .modelContext,
        .sessions,
        .behavior,
        .mcp,
        .usage,
    ]

    public var title: String {
        switch self {
        case .appearance: return "Appearance"
        case .chat: return "Chat"
        case .modelContext: return "Model & Context"
        case .notifications: return "Notifications"
        case .sessions: return "Sessions"
        case .shortcuts: return "Shortcuts"
        case .git: return "Git"
        case .magicPrompts: return "Magic Prompts"
        case .projects: return "Projects"
        case .agents: return "Agents"
        case .behavior: return "Behavior"
        case .commands: return "Commands"
        case .mcp: return "MCP"
        case .providers: return "Providers"
        case .usage: return "Usage"
        case .skills: return "Skills"
        case .skillsCatalog: return "Skills Catalog"
        }
    }

    public var symbolName: String {
        switch self {
        case .appearance: return "paintpalette"
        case .chat: return "bubble.left.and.bubble.right"
        case .modelContext: return "slider.horizontal.3"
        case .notifications: return "bell"
        case .sessions: return "clock.arrow.circlepath"
        case .shortcuts: return "command"
        case .git: return "point.3.filled.connected.trianglepath.dotted"
        case .magicPrompts: return "sparkles"
        case .projects: return "folder"
        case .agents: return "person.2"
        case .behavior: return "brain.head.profile"
        case .commands: return "terminal"
        case .mcp: return "point.3.connected.trianglepath.dotted"
        case .providers: return "cloud"
        case .usage: return "chart.bar"
        case .skills: return "book"
        case .skillsCatalog: return "books.vertical"
        }
    }
}

public enum AppNoticeSeverity: String, Sendable, Equatable, Codable, CaseIterable {
    case info
    case warning
    case error
}

public struct AppNotice: Identifiable, Sendable, Equatable, Codable {
    public var id: UUID
    public var severity: AppNoticeSeverity
    public var title: String
    public var message: String

    public init(
        id: UUID = UUID(),
        severity: AppNoticeSeverity,
        title: String,
        message: String
    ) {
        self.id = id
        self.severity = severity
        self.title = title
        self.message = message
    }
}

public enum WorkspaceActivityKind: String, Sendable, Equatable, Codable, CaseIterable {
    case indexing
    case search
    case git
    case modelLoading
    case chat
    case patchApply
}

public enum BackgroundToolJobStatus: String, Sendable, Equatable, Codable, CaseIterable {
    case queued
    case running
    case completed
    case failed
    case cancelled
}

public struct BackgroundToolJobViewState: Identifiable, Sendable, Equatable, Codable {
    public var id: UUID
    public var title: String
    public var status: BackgroundToolJobStatus
    public var detail: String
    public var createdAt: Date
    public var canCancel: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        status: BackgroundToolJobStatus = .queued,
        detail: String = "",
        createdAt: Date = Date(),
        canCancel: Bool = false
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.detail = detail
        self.createdAt = createdAt
        self.canCancel = canCancel
    }
}

public enum HealthEventSeverity: String, Sendable, Equatable, Codable, CaseIterable {
    case debug
    case info
    case warning
    case error
}

public struct HealthEventViewState: Identifiable, Sendable, Equatable, Codable {
    public var id: UUID
    public var date: Date
    public var kind: String
    public var severity: HealthEventSeverity
    public var message: String

    public init(id: UUID = UUID(), date: Date = Date(), kind: String, severity: HealthEventSeverity, message: String) {
        self.id = id
        self.date = date
        self.kind = kind
        self.severity = severity
        self.message = message
    }
}

public enum HealthTaskStatus: String, Sendable, Equatable, Codable, CaseIterable {
    case running
    case completed
    case failed
    case cancelled
}

public struct HealthTaskViewState: Identifiable, Sendable, Equatable, Codable {
    public var id: UUID
    public var title: String
    public var kind: String
    public var status: HealthTaskStatus
    public var priority: String
    public var message: String?

    public init(id: UUID = UUID(), title: String, kind: String, status: HealthTaskStatus, priority: String, message: String? = nil) {
        self.id = id
        self.title = title
        self.kind = kind
        self.status = status
        self.priority = priority
        self.message = message
    }
}

public struct HealthMetricViewState: Identifiable, Sendable, Equatable, Codable {
    public var id: String { kind }
    public var kind: String
    public var unit: String
    public var count: Int
    public var latest: Double
    public var average: Double

    public init(kind: String, unit: String, count: Int, latest: Double, average: Double) {
        self.kind = kind
        self.unit = unit
        self.count = count
        self.latest = latest
        self.average = average
    }

    public var summary: String {
        "\(kind): latest \(HealthFormatting.format(latest, unit: unit)), avg \(HealthFormatting.format(average, unit: unit)), n=\(count)"
    }
}

public enum RecoveryActionViewKind: String, Sendable, Equatable, Codable, CaseIterable {
    case retryWorkspaceOpen
    case retryIndexing
    case retrySearch
    case retryFilePreview
    case retryGitRefresh
    case retryModelLoad
    case reviewPatch
    case openHealth
    case dismiss
}

public struct RecoveryActionViewState: Identifiable, Sendable, Equatable, Codable {
    public var id: RecoveryActionViewKind { kind }
    public var kind: RecoveryActionViewKind
    public var title: String
    public var disabledReason: String?

    public init(kind: RecoveryActionViewKind, title: String? = nil, disabledReason: String? = nil) {
        self.kind = kind
        self.title = title ?? RecoveryFormatting.title(for: kind)
        self.disabledReason = disabledReason
    }
}

public struct RecoveryItemViewState: Identifiable, Sendable, Equatable, Codable {
    public var id: UUID
    public var title: String
    public var operationKind: String
    public var status: String
    public var message: String?
    public var workspacePath: String?
    public var relativePath: String?
    public var action: RecoveryActionViewState

    public init(
        id: UUID = UUID(),
        title: String,
        operationKind: String,
        status: String,
        message: String? = nil,
        workspacePath: String? = nil,
        relativePath: String? = nil,
        action: RecoveryActionViewState
    ) {
        self.id = id
        self.title = title
        self.operationKind = operationKind
        self.status = status
        self.message = message
        self.workspacePath = workspacePath
        self.relativePath = relativePath
        self.action = action
    }

    public var summary: String {
        let target = relativePath ?? workspacePath
        if let target, !target.isEmpty {
            return "\(operationKind) · \(status) · \(target)"
        }
        return "\(operationKind) · \(status)"
    }
}

public enum RecoveryFormatting {
    public static func title(for action: RecoveryActionViewKind) -> String {
        switch action {
        case .retryWorkspaceOpen: return "Retry Open"
        case .retryIndexing: return "Retry Index"
        case .retrySearch: return "Retry Search"
        case .retryFilePreview: return "Retry Preview"
        case .retryGitRefresh: return "Retry Git"
        case .retryModelLoad: return "Retry Model Load"
        case .reviewPatch: return "Review Diff"
        case .openHealth: return "Open Health"
        case .dismiss: return "Dismiss"
        }
    }

    public static func summary(items: [RecoveryItemViewState]) -> String {
        if items.isEmpty { return "No recovery items" }
        let failed = items.filter { $0.status == "failed" }.count
        let unfinished = items.filter { $0.status == "unfinishedPreviousRun" }.count
        return "\(items.count) recovery items · \(unfinished) unfinished · \(failed) failed"
    }
}

public struct HealthStatusViewState: Sendable, Equatable, Codable {
    public var activeTasks: [HealthTaskViewState]
    public var recentTasks: [HealthTaskViewState]
    public var recentEvents: [HealthEventViewState]
    public var metricSummaries: [HealthMetricViewState]
    public var memorySummary: String
    public var memoryPolicy: MemoryPolicyViewState?
    public var recoveryItems: [RecoveryItemViewState]
    public var recoverySummary: String
    public var recoveryWarning: String?
    public var diagnosticsExport: DiagnosticsExportViewState?
    public var configStatus: ConfigStatusViewState
    public var durableEventCursors: [DurableEventCursorViewState]

    public init(
        activeTasks: [HealthTaskViewState] = [],
        recentTasks: [HealthTaskViewState] = [],
        recentEvents: [HealthEventViewState] = [],
        metricSummaries: [HealthMetricViewState] = [],
        memorySummary: String = "Memory unavailable",
        memoryPolicy: MemoryPolicyViewState? = nil,
        recoveryItems: [RecoveryItemViewState] = [],
        recoverySummary: String? = nil,
        recoveryWarning: String? = nil,
        diagnosticsExport: DiagnosticsExportViewState? = nil,
        configStatus: ConfigStatusViewState = ConfigStatusViewState(),
        durableEventCursors: [DurableEventCursorViewState] = []
    ) {
        self.activeTasks = activeTasks
        self.recentTasks = recentTasks
        self.recentEvents = recentEvents
        self.metricSummaries = metricSummaries
        self.memorySummary = memorySummary
        self.memoryPolicy = memoryPolicy
        self.recoveryItems = recoveryItems
        self.recoverySummary = recoverySummary ?? RecoveryFormatting.summary(items: recoveryItems)
        self.recoveryWarning = recoveryWarning
        self.diagnosticsExport = diagnosticsExport
        self.configStatus = configStatus
        self.durableEventCursors = durableEventCursors
    }

    public var recentFailures: [HealthEventViewState] {
        recentEvents.filter { $0.severity == .error }
    }
}

public struct DurableEventCursorViewState: Identifiable, Sendable, Equatable, Codable {
    public var id: String
    public var title: String
    public var streamID: String
    public var sequence: Int64
    public var replayedEventCount: Int
    public var isTruncated: Bool

    public init(
        id: String,
        title: String,
        streamID: String,
        sequence: Int64,
        replayedEventCount: Int,
        isTruncated: Bool = false
    ) {
        self.id = id
        self.title = title
        self.streamID = streamID
        self.sequence = max(0, sequence)
        self.replayedEventCount = max(0, replayedEventCount)
        self.isTruncated = isTruncated
    }

    public var summary: String {
        let suffix = isTruncated ? " · truncated" : ""
        return "\(streamID) · cursor \(sequence) · \(replayedEventCount) replayed\(suffix)"
    }
}

public struct DiagnosticsExportViewState: Sendable, Equatable, Codable {
    public var path: String
    public var exportedAt: Date
    public var includeFullPaths: Bool

    public init(path: String, exportedAt: Date = Date(), includeFullPaths: Bool = false) {
        self.path = path
        self.exportedAt = exportedAt
        self.includeFullPaths = includeFullPaths
    }

    public var summary: String {
        "Last export: \(path)"
    }
}

public struct MemoryPolicyViewState: Sendable, Equatable, Codable {
    public var requestedProfile: ResourceProfile
    public var resolvedProfile: ResourceProfile
    public var usedFraction: Double
    public var processBytes: Int
    public var totalBytes: Int
    public var gpuActiveBytes: Int
    public var gpuCacheBytes: Int
    public var activeActions: [String]

    public init(
        requestedProfile: ResourceProfile = .automatic,
        resolvedProfile: ResourceProfile = .balanced,
        usedFraction: Double = 0,
        processBytes: Int = 0,
        totalBytes: Int = 0,
        gpuActiveBytes: Int = 0,
        gpuCacheBytes: Int = 0,
        activeActions: [String] = []
    ) {
        self.requestedProfile = requestedProfile
        self.resolvedProfile = resolvedProfile
        self.usedFraction = usedFraction
        self.processBytes = processBytes
        self.totalBytes = totalBytes
        self.gpuActiveBytes = gpuActiveBytes
        self.gpuCacheBytes = gpuCacheBytes
        self.activeActions = activeActions
    }

    public var summary: String {
        let used = HealthFormatting.format(usedFraction, unit: "ratio")
        let process = HealthFormatting.format(Double(processBytes), unit: "bytes")
        let total = HealthFormatting.format(Double(totalBytes), unit: "bytes")
        return "\(resolvedProfile.label) · \(used) · \(process) / \(total)"
    }
}

public enum HealthFormatting {
    public static func format(_ value: Double, unit: String) -> String {
        switch unit {
        case "milliseconds":
            return "\(Int(value.rounded())) ms"
        case "bytes":
            return ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .memory)
        case "ratio":
            return "\(Int((value * 100).rounded()))%"
        default:
            return value == floor(value) ? "\(Int(value))" : String(format: "%.2f", value)
        }
    }
}

public struct WorkspaceActivity: Identifiable, Sendable, Equatable, Codable {
    public var id: WorkspaceActivityKind { kind }
    public var kind: WorkspaceActivityKind
    public var title: String
    public var canCancel: Bool

    public init(kind: WorkspaceActivityKind, title: String, canCancel: Bool = false) {
        self.kind = kind
        self.title = title
        self.canCancel = canCancel
    }
}

public enum WorkspaceFocusTarget: String, Sendable, Equatable, Codable {
    case none
    case chat
    case search
}

public struct WorkspaceLayoutPreferences: Sendable, Equatable, Codable {
    public var sidebarWidth: Double
    public var editorWidth: Double
    public var chatWidth: Double

    public init(sidebarWidth: Double = 280, editorWidth: Double = 560, chatWidth: Double = 480) {
        self.sidebarWidth = sidebarWidth
        self.editorWidth = editorWidth
        self.chatWidth = chatWidth
    }
}

public struct FileTreeNode: Identifiable, Sendable, Equatable, Codable {
    public var id: String { path.isEmpty ? "/" : path }
    public var name: String
    public var path: String
    public var isDirectory: Bool
    public var children: [FileTreeNode]

    public init(name: String, path: String, isDirectory: Bool, children: [FileTreeNode] = []) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.children = children
    }

    public var listChildren: [FileTreeNode]? {
        children.isEmpty ? nil : children
    }

    public static func grouped(paths: [String]) -> [FileTreeNode] {
        var root: [String: TreeBuilder] = [:]
        for path in paths.sorted() {
            let parts = path.split(separator: "/").map(String.init)
            guard !parts.isEmpty else { continue }
            insert(parts: parts, fullPath: path, parentPath: "", into: &root)
        }
        return root.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }.map(\.node)
    }

    public static func filtered(nodes: [FileTreeNode], query: String) -> [FileTreeNode] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nodes }
        let lowercased = trimmed.lowercased()
        return nodes.compactMap { $0.filtered(matching: lowercased) }
    }

    private func filtered(matching lowercasedQuery: String) -> FileTreeNode? {
        let childMatches = children.compactMap { $0.filtered(matching: lowercasedQuery) }
        let matchesSelf = name.lowercased().contains(lowercasedQuery) || path.lowercased().contains(lowercasedQuery)
        if matchesSelf || !childMatches.isEmpty {
            return FileTreeNode(name: name, path: path, isDirectory: isDirectory, children: childMatches)
        }
        return nil
    }

    private static func insert(parts: [String], fullPath: String, parentPath: String, into builders: inout [String: TreeBuilder]) {
        let name = parts[0]
        let nodePath = parentPath.isEmpty ? name : "\(parentPath)/\(name)"
        if parts.count == 1 {
            builders[name] = TreeBuilder(name: name, path: fullPath, isDirectory: false)
            return
        }
        var builder = builders[name] ?? TreeBuilder(name: name, path: nodePath, isDirectory: true)
        insert(parts: Array(parts.dropFirst()), fullPath: fullPath, parentPath: nodePath, into: &builder.children)
        builders[name] = builder
    }
}

public struct FileTreeVisibleRow: Identifiable, Sendable, Equatable, Codable {
    public var id: String { path }
    public var node: FileTreeNode
    public var depth: Int
    public var isExpanded: Bool

    public init(node: FileTreeNode, depth: Int, isExpanded: Bool) {
        self.node = node
        self.depth = depth
        self.isExpanded = isExpanded
    }

    public var accessibilityLabel: String {
        node.isDirectory ? "Folder \(node.name)" : "File \(node.name)"
    }

    public var path: String { node.path }
}

public enum FileTreeModel {
    public static func visibleRows(
        nodes: [FileTreeNode],
        expandedPaths: Set<String>,
        filter: String = "",
        limit: Int = 5_000
    ) -> [FileTreeVisibleRow] {
        let filtered = FileTreeNode.filtered(nodes: nodes, query: filter)
        var rows: [FileTreeVisibleRow] = []
        func walk(_ node: FileTreeNode, depth: Int) {
            guard rows.count < limit else { return }
            let expanded = expandedPaths.contains(node.path) || !filter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            rows.append(.init(node: node, depth: depth, isExpanded: expanded))
            if node.isDirectory && expanded {
                for child in node.children {
                    walk(child, depth: depth + 1)
                }
            }
        }
        for node in filtered {
            walk(node, depth: 0)
        }
        return rows
    }
}

private struct TreeBuilder {
    var name: String
    var path: String
    var isDirectory: Bool
    var children: [String: TreeBuilder] = [:]

    var node: FileTreeNode {
        FileTreeNode(
            name: name,
            path: path,
            isDirectory: isDirectory,
            children: children.values
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                .map(\.node))
    }
}

public enum DiffLineKind: String, Sendable, Equatable, Codable {
    case addition
    case deletion
    case hunk
    case file
    case context
}

public struct DiffLine: Identifiable, Sendable, Equatable, Codable {
    public var id: Int
    public var kind: DiffLineKind
    public var text: String

    public init(id: Int, kind: DiffLineKind, text: String) {
        self.id = id
        self.kind = kind
        self.text = text
    }
}

public struct DiffHunk: Identifiable, Sendable, Equatable, Codable {
    public var id: Int
    public var header: String
    public var lines: [DiffLine]
    public var additions: Int
    public var deletions: Int

    public init(id: Int, header: String, lines: [DiffLine], additions: Int = 0, deletions: Int = 0) {
        self.id = id
        self.header = header
        self.lines = lines
        self.additions = additions
        self.deletions = deletions
    }
}

public struct DiffFile: Identifiable, Sendable, Equatable, Codable {
    public var id: String { newPath.isEmpty ? oldPath : newPath }
    public var oldPath: String
    public var newPath: String
    public var header: String
    public var hunks: [DiffHunk]
    public var leadingLines: [DiffLine]
    public var additions: Int
    public var deletions: Int

    public init(
        oldPath: String,
        newPath: String,
        header: String,
        hunks: [DiffHunk] = [],
        leadingLines: [DiffLine] = [],
        additions: Int = 0,
        deletions: Int = 0
    ) {
        self.oldPath = oldPath
        self.newPath = newPath
        self.header = header
        self.hunks = hunks
        self.leadingLines = leadingLines
        self.additions = additions
        self.deletions = deletions
    }
}

public enum PatchLineKind: String, Sendable, Equatable, Codable {
    case context
    case addition
    case deletion
}

public struct PatchLine: Identifiable, Sendable, Equatable, Codable {
    public var id: Int
    public var kind: PatchLineKind
    public var text: String

    public init(id: Int, kind: PatchLineKind, text: String) {
        self.id = id
        self.kind = kind
        self.text = text
    }
}

public struct PatchHunk: Identifiable, Sendable, Equatable, Codable {
    public var id: Int
    public var header: String
    public var oldStart: Int
    public var oldCount: Int
    public var newStart: Int
    public var newCount: Int
    public var lines: [PatchLine]
    public var isAccepted: Bool

    public init(
        id: Int,
        header: String,
        oldStart: Int,
        oldCount: Int,
        newStart: Int,
        newCount: Int,
        lines: [PatchLine],
        isAccepted: Bool = true
    ) {
        self.id = id
        self.header = header
        self.oldStart = oldStart
        self.oldCount = oldCount
        self.newStart = newStart
        self.newCount = newCount
        self.lines = lines
        self.isAccepted = isAccepted
    }

    public var additions: Int { lines.filter { $0.kind == .addition }.count }
    public var deletions: Int { lines.filter { $0.kind == .deletion }.count }
}

public struct PatchFile: Identifiable, Sendable, Equatable, Codable {
    public var id: String { newPath == "/dev/null" ? oldPath : newPath }
    public var oldPath: String
    public var newPath: String
    public var hunks: [PatchHunk]
    public var diagnostics: [String]

    public init(oldPath: String, newPath: String, hunks: [PatchHunk] = [], diagnostics: [String] = []) {
        self.oldPath = oldPath
        self.newPath = newPath
        self.hunks = hunks
        self.diagnostics = diagnostics
    }

    public var acceptedHunks: [PatchHunk] {
        hunks.filter(\.isAccepted)
    }

    public var additions: Int {
        hunks.reduce(0) { $0 + $1.additions }
    }

    public var deletions: Int {
        hunks.reduce(0) { $0 + $1.deletions }
    }
}

public struct PatchProposal: Identifiable, Sendable, Equatable, Codable {
    public var id: UUID
    public var title: String
    public var files: [PatchFile]
    public var diagnostics: [String]

    public init(id: UUID = UUID(), title: String = "Patch Proposal", files: [PatchFile], diagnostics: [String] = []) {
        self.id = id
        self.title = title
        self.files = files
        self.diagnostics = diagnostics
    }

    public var acceptedHunkCount: Int {
        files.reduce(0) { $0 + $1.acceptedHunks.count }
    }

    public var hunkCount: Int {
        files.reduce(0) { $0 + $1.hunks.count }
    }

    public var additions: Int {
        files.reduce(0) { $0 + $1.additions }
    }

    public var deletions: Int {
        files.reduce(0) { $0 + $1.deletions }
    }

    public var summary: String {
        "\(files.count) files · \(acceptedHunkCount)/\(hunkCount) hunks accepted · +\(additions) -\(deletions)"
    }

    public var canApply: Bool {
        acceptedHunkCount > 0 && diagnostics.isEmpty && files.allSatisfy { $0.diagnostics.isEmpty }
    }

    public mutating func setHunkAccepted(fileID: String, hunkID: Int, isAccepted: Bool) {
        guard let fileIndex = files.firstIndex(where: { $0.id == fileID }),
              let hunkIndex = files[fileIndex].hunks.firstIndex(where: { $0.id == hunkID }) else {
            return
        }
        files[fileIndex].hunks[hunkIndex].isAccepted = isAccepted
    }
}

public enum PatchReviewModel {
    public static func disabledApplyReason(proposal: PatchProposal?, writesAllowed: Bool) -> String? {
        guard writesAllowed else { return "Enable write tools in Model Settings before applying patches." }
        guard let proposal else { return "No patch proposal loaded." }
        if proposal.acceptedHunkCount == 0 { return "No hunks are accepted." }
        if !proposal.diagnostics.isEmpty { return proposal.diagnostics.joined(separator: " ") }
        let fileDiagnostics = proposal.files.flatMap(\.diagnostics)
        if !fileDiagnostics.isEmpty { return fileDiagnostics.joined(separator: " ") }
        return nil
    }
}

public enum DiffFormatter {
    public static func classify(_ diff: String) -> [DiffLine] {
        diff.split(separator: "\n", omittingEmptySubsequences: false).enumerated().map { index, line in
            let text = String(line)
            let kind: DiffLineKind
            if text.hasPrefix("+++") || text.hasPrefix("---") || text.hasPrefix("diff --git") {
                kind = .file
            } else if text.hasPrefix("@@") {
                kind = .hunk
            } else if text.hasPrefix("+") {
                kind = .addition
            } else if text.hasPrefix("-") {
                kind = .deletion
            } else {
                kind = .context
            }
            return DiffLine(id: index, kind: kind, text: text)
        }
    }

    public static func files(_ diff: String) -> [DiffFile] {
        var files: [DiffFile] = []
        var currentFile: DiffFile?
        var currentHunk: DiffHunk?
        var lineID = 0
        var hunkID = 0

        func finishHunk() {
            guard let hunk = currentHunk else { return }
            currentFile?.hunks.append(hunk)
            currentHunk = nil
        }

        func finishFile() {
            finishHunk()
            guard let file = currentFile else { return }
            files.append(file)
            currentFile = nil
        }

        for rawLine in diff.split(separator: "\n", omittingEmptySubsequences: false) {
            let text = String(rawLine)
            if text.hasPrefix("diff --git") {
                finishFile()
                let parsed = parseDiffHeader(text)
                currentFile = DiffFile(oldPath: parsed.oldPath, newPath: parsed.newPath, header: text)
                lineID += 1
                continue
            }

            if currentFile == nil {
                currentFile = DiffFile(oldPath: "", newPath: "", header: "Working Tree")
            }

            if text.hasPrefix("--- ") {
                currentFile?.oldPath = stripDiffPath(String(text.dropFirst(4)))
            } else if text.hasPrefix("+++ ") {
                currentFile?.newPath = stripDiffPath(String(text.dropFirst(4)))
            }

            let line = classifyLine(text, id: lineID)
            lineID += 1

            if text.hasPrefix("@@") {
                finishHunk()
                currentHunk = DiffHunk(id: hunkID, header: text, lines: [line])
                hunkID += 1
                continue
            }

            let isAddition = text.hasPrefix("+") && !text.hasPrefix("+++")
            let isDeletion = text.hasPrefix("-") && !text.hasPrefix("---")
            if isAddition {
                currentFile?.additions += 1
                currentHunk?.additions += 1
            } else if isDeletion {
                currentFile?.deletions += 1
                currentHunk?.deletions += 1
            }

            if currentHunk != nil {
                currentHunk?.lines.append(line)
            } else {
                currentFile?.leadingLines.append(line)
            }
        }

        finishFile()
        return files.filter { !$0.header.isEmpty || !$0.leadingLines.isEmpty || !$0.hunks.isEmpty }
    }

    private static func classifyLine(_ text: String, id: Int) -> DiffLine {
        let kind: DiffLineKind
        if text.hasPrefix("+++") || text.hasPrefix("---") || text.hasPrefix("diff --git") {
            kind = .file
        } else if text.hasPrefix("@@") {
            kind = .hunk
        } else if text.hasPrefix("+") {
            kind = .addition
        } else if text.hasPrefix("-") {
            kind = .deletion
        } else {
            kind = .context
        }
        return DiffLine(id: id, kind: kind, text: text)
    }

    private static func parseDiffHeader(_ text: String) -> (oldPath: String, newPath: String) {
        let parts = text.split(separator: " ").map(String.init)
        guard parts.count >= 4 else { return ("", "") }
        return (stripDiffPath(parts[2]), stripDiffPath(parts[3]))
    }

    private static func stripDiffPath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "/dev/null" { return trimmed }
        if trimmed.hasPrefix("a/") || trimmed.hasPrefix("b/") {
            return String(trimmed.dropFirst(2))
        }
        return trimmed
    }
}

public enum ModelLoadStatus: Sendable, Equatable, Codable {
    case idle
    case loading
    case cancelling
    case loaded
    case failed(String)

    public var label: String {
        switch self {
        case .idle: return "Not loaded"
        case .loading: return "Loading"
        case .cancelling: return "Cancelling"
        case .loaded: return "Loaded"
        case .failed(let message): return "Failed: \(message)"
        }
    }

    public var isBusy: Bool {
        self == .loading || self == .cancelling
    }
}

public struct ModelDownloadProgressViewState: Sendable, Equatable, Codable {
    public var modelID: String
    public var roleLabel: String
    public var fractionCompleted: Double

    public init(modelID: String, roleLabel: String, fractionCompleted: Double) {
        self.modelID = modelID
        self.roleLabel = roleLabel
        self.fractionCompleted = min(1, max(0, fractionCompleted))
    }

    public var percent: Int {
        Int((fractionCompleted * 100).rounded())
    }

    public var statusText: String {
        "Downloading model - \(percent)%"
    }
}

public struct ModelSettingsViewState: Sendable, Equatable, Codable {
    public var orchestratorModelID: String
    public var utilityModelID: String
    public var embeddingsModelID: String
    public var orchestratorQuantization: QuantizationLevel
    public var utilityQuantization: QuantizationLevel
    public var embeddingsQuantization: QuantizationLevel
    public var toolCallFormat: ModelToolCallFormat?
    public var allowWrites: Bool
    public var allowNetworkTools: Bool
    public var persistPromptHistory: Bool
    public var maxToolIterations: Int
    public var resourceProfile: ResourceProfile
    /// Speculative decoding (large-RAM only): a small draft model proposing
    /// tokens the orchestrator verifies. Both models must share a tokenizer.
    public var enableSpeculativeDecoding: Bool
    public var speculativeDraftModelID: String

    public init(
        orchestratorModelID: String = "",
        utilityModelID: String = "",
        embeddingsModelID: String = "",
        orchestratorQuantization: QuantizationLevel = .defaultFor(.orchestrator),
        utilityQuantization: QuantizationLevel = .defaultFor(.utility),
        embeddingsQuantization: QuantizationLevel = .defaultFor(.embeddings),
        toolCallFormat: ModelToolCallFormat? = nil,
        allowWrites: Bool = false,
        allowNetworkTools: Bool = false,
        persistPromptHistory: Bool = true,
        maxToolIterations: Int = 4,
        resourceProfile: ResourceProfile = .automatic,
        enableSpeculativeDecoding: Bool = false,
        speculativeDraftModelID: String = ""
    ) {
        self.orchestratorModelID = orchestratorModelID
        self.utilityModelID = utilityModelID
        self.embeddingsModelID = embeddingsModelID
        self.orchestratorQuantization = orchestratorQuantization
        self.utilityQuantization = utilityQuantization
        self.embeddingsQuantization = embeddingsQuantization
        self.toolCallFormat = toolCallFormat
        self.allowWrites = allowWrites
        self.allowNetworkTools = allowNetworkTools
        self.persistPromptHistory = persistPromptHistory
        self.maxToolIterations = max(0, maxToolIterations)
        self.resourceProfile = resourceProfile
        self.enableSpeculativeDecoding = enableSpeculativeDecoding
        self.speculativeDraftModelID = speculativeDraftModelID
    }

    public func usesSingleAgentMode(
        physicalMemoryBytes: Int = Int(ProcessInfo.processInfo.physicalMemory)
    ) -> Bool {
        ResourceProfile.resolvedProfile(
            for: resourceProfile,
            physicalMemoryBytes: physicalMemoryBytes) == .smallRAM
    }

    public func validationErrors(
        physicalMemoryBytes: Int = Int(ProcessInfo.processInfo.physicalMemory)
    ) -> [String] {
        var errors: [String] = []
        if orchestratorModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(usesSingleAgentMode(physicalMemoryBytes: physicalMemoryBytes)
                ? "Chat model ID is required."
                : "Orchestrator model ID is required.")
        } else if let reason = ModelCompatibility.unsupportedReason(for: orchestratorModelID) {
            errors.append(usesSingleAgentMode(physicalMemoryBytes: physicalMemoryBytes)
                ? "Chat model is unsupported: \(reason)"
                : "Orchestrator model is unsupported: \(reason)")
        }
        if !usesSingleAgentMode(physicalMemoryBytes: physicalMemoryBytes),
           utilityModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Utility model ID is required.")
        } else if !usesSingleAgentMode(physicalMemoryBytes: physicalMemoryBytes),
                  let reason = ModelCompatibility.unsupportedReason(for: utilityModelID) {
            errors.append("Utility model is unsupported: \(reason)")
        }
        if !embeddingsModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           embeddingsQuantization != .defaultFor(.embeddings) {
            errors.append("Embedding models must use q\(QuantizationLevel.defaultFor(.embeddings).bitWidth).")
        }
        return errors
    }

    public var validationErrors: [String] {
        validationErrors()
    }

    public var writeWarning: String? {
        allowWrites ? "Write tools are enabled for agent runs in this workspace." : nil
    }

    public var networkToolWarning: String? {
        allowNetworkTools ? "Trusted process/network tools can execute workspace scripts and commands." : nil
    }
}

public struct RecommendedModel: Identifiable, Sendable, Equatable, Codable {
    public var id: ModelRole { role }
    public var role: ModelRole
    public var modelID: String
    public var quantization: QuantizationLevel
    public var memoryNote: String
    public var purpose: String

    public init(role: ModelRole, modelID: String, quantization: QuantizationLevel, memoryNote: String, purpose: String) {
        self.role = role
        self.modelID = modelID
        self.quantization = quantization
        self.memoryNote = memoryNote
        self.purpose = purpose
    }
}

public struct ModelOnboardingViewState: Sendable, Equatable, Codable {
    public var isDismissed: Bool
    public var recommendations: [RecommendedModel]

    public init(isDismissed: Bool = false, recommendations: [RecommendedModel] = Self.defaultRecommendations) {
        self.isDismissed = isDismissed
        self.recommendations = recommendations
    }

    public static let defaultRecommendations: [RecommendedModel] = [
        RecommendedModel(
            role: .orchestrator,
            modelID: "Qwen3.6-35B-A3B",
            quantization: .q4,
            memoryNote: "Use on high-memory Apple Silicon; architecture target is around 64 GB unified memory.",
            purpose: "Planning, architecture, and multi-file reasoning."),
        RecommendedModel(
            role: .utility,
            modelID: "Qwen3.5-2B",
            quantization: .q4,
            memoryNote: "Small utility model for fast local tasks.",
            purpose: "Search, summaries, lint/test interpretation, and simple questions."),
        RecommendedModel(
            role: .embeddings,
            modelID: "nomic-ai/nomic-embed-text-v1.5",
            quantization: .q8,
            memoryNote: "Optional semantic search model; unloads first under memory pressure.",
            purpose: "Semantic and hybrid workspace retrieval.")
    ]

    public var guidanceText: String {
        "Models load only after you explicitly press Load. Choose role-specific models, quantization, and a native tool-call format compatible with the model."
    }
}

public enum ChatComposerModel {
    public static func availableModelIDs(
        settings: ModelSettingsViewState,
        localModelIDs: [String] = []
    ) -> [String] {
        guard !localModelIDs.isEmpty else { return [] }
        let configured = settings.orchestratorModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let local = uniqueNonEmpty(ModelCompatibility.supportedModelIDs(localModelIDs))
        guard !configured.isEmpty, ModelCompatibility.isSupported(configured), local.contains(configured) else {
            return local
        }
        return uniqueNonEmpty([configured] + local)
    }

    public static func shouldLoadSelectedModel(
        currentModelID: String,
        selectedModelID: String,
        status: ModelLoadStatus
    ) -> Bool {
        let current = currentModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let selected = selectedModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selected.isEmpty else { return false }
        return current != selected || status != .loaded
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
}

public enum AccessibilityCopy {
    public static func patchHunkLabel(_ hunk: PatchHunk) -> String {
        "\(hunk.isAccepted ? "Accepted" : "Rejected") hunk, \(hunk.additions) additions, \(hunk.deletions) deletions"
    }

    public static func modelStatusLabel(_ status: ModelLoadStatus) -> String {
        "Model status: \(status.label)"
    }
}

public enum FilePreviewKind: String, Sendable, Equatable, Codable {
    case empty
    case text
    case binary
    case error
}

public struct FilePreviewViewState: Sendable, Equatable, Codable {
    public var path: String?
    public var kind: FilePreviewKind
    public var text: String
    public var syntaxTokens: [CodeSyntaxToken]
    public var byteCount: Int
    public var isTruncated: Bool
    public var message: String

    public init(
        path: String? = nil,
        kind: FilePreviewKind = .empty,
        text: String = "",
        syntaxTokens: [CodeSyntaxToken] = [],
        byteCount: Int = 0,
        isTruncated: Bool = false,
        message: String = "Select a file to preview its contents."
    ) {
        self.path = path
        self.kind = kind
        self.text = text
        self.syntaxTokens = syntaxTokens
        self.byteCount = byteCount
        self.isTruncated = isTruncated
        self.message = message
    }

    public static let empty = FilePreviewViewState()
}

public enum CodeSyntaxTokenKind: String, Sendable, Equatable, Codable, CaseIterable {
    case keyword
    case string
    case comment
    case number
}

public struct CodeSyntaxToken: Sendable, Equatable, Codable, Identifiable {
    public var id: String { "\(range.location):\(range.length):\(kind.rawValue)" }
    public var range: NSRange
    public var kind: CodeSyntaxTokenKind

    public init(range: NSRange, kind: CodeSyntaxTokenKind) {
        self.range = range
        self.kind = kind
    }
}

public struct WorkspaceViewState: Sendable, Equatable {
    public var chrome: WorkspaceChromeViewState
    public var workspacePath: String?
    public var indexingSummary: String
    public var fileTree: [FileTreeNode]
    public var fileTreeFilter: String
    public var selectedFilePath: String?
    public var selectedFileText: String
    public var selectedFilePreview: FilePreviewViewState
    public var searchHits: [SearchHit]
    public var gitSummary: String
    public var diffLines: [DiffLine]
    public var diffFiles: [DiffFile]
    public var chatMessages: [ChatMessageViewState]
    public var chatThreads: [ChatThreadViewState]
    public var globalChatThreads: [ChatThreadViewState]
    public var modelStatus: ModelLoadStatus
    public var modelDownloadProgress: ModelDownloadProgressViewState?
    public var isIndexing: Bool
    public var notices: [AppNotice]
    public var activities: [WorkspaceActivity]
    public var focusTarget: WorkspaceFocusTarget
    public var layout: WorkspaceLayoutPreferences
    public var patchProposal: PatchProposal?
    public var isPatchReviewPresented: Bool
    public var fileTreeRows: [FileTreeVisibleRow]
    public var expandedFileTreePaths: Set<String>
    public var modelOnboarding: ModelOnboardingViewState
    public var availableChatModelIDs: [String]
    public var health: HealthStatusViewState
    public var configStatus: ConfigStatusViewState
    public var effectiveSettings: ModelSettingsViewState?
    public var isHealthPresented: Bool
    public var permissionPrompt: PermissionPromptViewState?
    public var questionPrompt: QuestionPromptViewState?
    public var todoPanel: TodoPanelViewState
    public var backgroundToolJobs: [BackgroundToolJobViewState]
    public var sessionTimelineItems: [SessionTimelineItemViewState]
    public var workspaceHistory: [WorkspaceHistoryItemViewState]
    public var mcpSettings: MCPSettingsViewState
    public var agentSwitcherItems: [AgentSwitcherItemViewState]
    public var selectedAgentID: String?
    public var queuedPrompts: [QueuedPromptViewState]
    public var selectedReasoningEffort: ReasoningEffort
    public var reasoningOptions: [ReasoningOptionViewState]
    public var chatSurfacePreferences: ChatSurfacePreferences
    public var modelContextSettings: ModelContextSettingsViewState
    public var inspectorGit: InspectorGitViewState
    public var inspectorDiff: InspectorDiffViewState
    public var settingsSectionAvailability: [SettingsSectionAvailability]

    public init(
        chrome: WorkspaceChromeViewState = WorkspaceChromeViewState(),
        workspacePath: String? = nil,
        indexingSummary: String = "No workspace",
        fileTree: [FileTreeNode] = [],
        fileTreeFilter: String = "",
        selectedFilePath: String? = nil,
        selectedFileText: String = "",
        selectedFilePreview: FilePreviewViewState = .empty,
        searchHits: [SearchHit] = [],
        gitSummary: String = "Git status unavailable",
        diffLines: [DiffLine] = [],
        diffFiles: [DiffFile] = [],
        chatMessages: [ChatMessageViewState] = [],
        chatThreads: [ChatThreadViewState] = [],
        globalChatThreads: [ChatThreadViewState] = [],
        modelStatus: ModelLoadStatus = .idle,
        modelDownloadProgress: ModelDownloadProgressViewState? = nil,
        isIndexing: Bool = false,
        notices: [AppNotice] = [],
        activities: [WorkspaceActivity] = [],
        focusTarget: WorkspaceFocusTarget = .none,
        layout: WorkspaceLayoutPreferences = WorkspaceLayoutPreferences(),
        patchProposal: PatchProposal? = nil,
        isPatchReviewPresented: Bool = false,
        fileTreeRows: [FileTreeVisibleRow] = [],
        expandedFileTreePaths: Set<String> = [],
        modelOnboarding: ModelOnboardingViewState = ModelOnboardingViewState(),
        availableChatModelIDs: [String] = [],
        health: HealthStatusViewState = HealthStatusViewState(),
        configStatus: ConfigStatusViewState = ConfigStatusViewState(),
        effectiveSettings: ModelSettingsViewState? = nil,
        isHealthPresented: Bool = false,
        permissionPrompt: PermissionPromptViewState? = nil,
        questionPrompt: QuestionPromptViewState? = nil,
        todoPanel: TodoPanelViewState = TodoPanelViewState(),
        backgroundToolJobs: [BackgroundToolJobViewState] = [],
        sessionTimelineItems: [SessionTimelineItemViewState] = [],
        workspaceHistory: [WorkspaceHistoryItemViewState] = [],
        mcpSettings: MCPSettingsViewState = MCPSettingsViewState(),
        agentSwitcherItems: [AgentSwitcherItemViewState] = [],
        selectedAgentID: String? = nil,
        queuedPrompts: [QueuedPromptViewState] = [],
        selectedReasoningEffort: ReasoningEffort = .none,
        reasoningOptions: [ReasoningOptionViewState] = ReasoningOptionViewState.options(for: "", selected: .none),
        chatSurfacePreferences: ChatSurfacePreferences = ChatSurfacePreferences(),
        modelContextSettings: ModelContextSettingsViewState = ModelContextSettingsViewState(),
        inspectorGit: InspectorGitViewState? = nil,
        inspectorDiff: InspectorDiffViewState? = nil,
        settingsSectionAvailability: [SettingsSectionAvailability] = []
    ) {
        self.chrome = chrome
        self.workspacePath = workspacePath
        self.indexingSummary = indexingSummary
        self.fileTree = fileTree
        self.fileTreeFilter = fileTreeFilter
        self.selectedFilePath = selectedFilePath
        self.selectedFileText = selectedFileText
        self.selectedFilePreview = selectedFilePreview
        self.searchHits = searchHits
        self.gitSummary = gitSummary
        self.diffLines = diffLines
        self.diffFiles = diffFiles
        self.chatMessages = chatMessages
        self.chatThreads = chatThreads
        self.globalChatThreads = globalChatThreads
        self.modelStatus = modelStatus
        self.modelDownloadProgress = modelDownloadProgress
        self.isIndexing = isIndexing
        self.notices = notices
        self.activities = activities
        self.focusTarget = focusTarget
        self.layout = layout
        self.patchProposal = patchProposal
        self.isPatchReviewPresented = isPatchReviewPresented
        self.fileTreeRows = fileTreeRows
        self.expandedFileTreePaths = expandedFileTreePaths
        self.modelOnboarding = modelOnboarding
        self.availableChatModelIDs = availableChatModelIDs
        self.health = health
        self.configStatus = configStatus
        self.effectiveSettings = effectiveSettings
        self.isHealthPresented = isHealthPresented
        self.permissionPrompt = permissionPrompt
        self.questionPrompt = questionPrompt
        self.todoPanel = todoPanel
        self.backgroundToolJobs = backgroundToolJobs
        self.sessionTimelineItems = sessionTimelineItems
        self.workspaceHistory = workspaceHistory
        self.mcpSettings = mcpSettings
        self.agentSwitcherItems = agentSwitcherItems
        self.selectedAgentID = selectedAgentID
        self.queuedPrompts = queuedPrompts
        self.selectedReasoningEffort = selectedReasoningEffort
        self.reasoningOptions = reasoningOptions
        self.chatSurfacePreferences = chatSurfacePreferences
        self.modelContextSettings = modelContextSettings
        self.inspectorGit = inspectorGit ?? InspectorGitViewState(
            summary: gitSummary,
            diffFiles: diffFiles,
            fallbackLines: diffLines)
        self.inspectorDiff = inspectorDiff ?? InspectorDiffViewState(
            files: diffFiles,
            fallbackLines: diffLines,
            viewMode: chatSurfacePreferences.diffViewMode)
        self.settingsSectionAvailability = settingsSectionAvailability
    }
}
