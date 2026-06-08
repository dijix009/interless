import Foundation
import Shared
import UI

@MainActor
public final class AppPreferences {
    private enum Key {
        static let restoreLastWorkspaceOnLaunch = "restoreLastWorkspaceOnLaunch"
        static let lastWorkspacePath = "lastWorkspacePath"
        static let recentWorkspacePaths = "recentWorkspacePaths"
        static let lastSelectedFilePath = "lastSelectedFilePath"
        static let lastSearchQuery = "lastSearchQuery"
        static let layoutPreferences = "layoutPreferences"
        static let expandedFileTreePaths = "expandedFileTreePaths"
        static let modelOnboardingDismissed = "modelOnboardingDismissed"
        static let orchestratorModelID = "orchestratorModelID"
        static let utilityModelID = "utilityModelID"
        static let embeddingsModelID = "embeddingsModelID"
        static let orchestratorQuantization = "orchestratorQuantization"
        static let utilityQuantization = "utilityQuantization"
        static let embeddingsQuantization = "embeddingsQuantization"
        static let toolCallFormat = "toolCallFormat"
        static let allowWrites = "allowWrites"
        static let allowNetworkTools = "allowNetworkTools"
        static let persistPromptHistory = "persistPromptHistory"
        static let maxToolIterations = "maxToolIterations"
        static let resourceProfile = "resourceProfile"
        static let reasoningEffort = "reasoningEffort"
        static let plainChatMaxAnswerTokens = "plainChatMaxAnswerTokens"
        static let codeChatMaxAnswerTokens = "codeChatMaxAnswerTokens"
        static let maxContextWindowTokens = "maxContextWindowTokens"
        static let plainChatMaxContextWindowTokens = "plainChatMaxContextWindowTokens"
        static let codeChatMaxContextWindowTokens = "codeChatMaxContextWindowTokens"
        static let plainChatContextMode = "plainChatContextMode"
        static let codeChatContextMode = "codeChatContextMode"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var restoreLastWorkspaceOnLaunch: Bool {
        get {
            guard defaults.object(forKey: Key.restoreLastWorkspaceOnLaunch) != nil else { return true }
            return defaults.bool(forKey: Key.restoreLastWorkspaceOnLaunch)
        }
        set { defaults.set(newValue, forKey: Key.restoreLastWorkspaceOnLaunch) }
    }

    public var lastWorkspacePath: String? {
        get { defaults.string(forKey: Key.lastWorkspacePath) }
        set { defaults.set(newValue, forKey: Key.lastWorkspacePath) }
    }

    public var recentWorkspacePaths: [String] {
        get { defaults.stringArray(forKey: Key.recentWorkspacePaths) ?? [] }
        set { defaults.set(Array(newValue.prefix(10)), forKey: Key.recentWorkspacePaths) }
    }

    public var lastSelectedFilePath: String? {
        get { defaults.string(forKey: Key.lastSelectedFilePath) }
        set { defaults.set(newValue, forKey: Key.lastSelectedFilePath) }
    }

    public var lastSearchQuery: String {
        get { defaults.string(forKey: Key.lastSearchQuery) ?? "" }
        set { defaults.set(newValue, forKey: Key.lastSearchQuery) }
    }

    public var layoutPreferences: WorkspaceLayoutPreferences {
        get {
            guard let data = defaults.data(forKey: Key.layoutPreferences),
                  let decoded = try? JSONDecoder().decode(WorkspaceLayoutPreferences.self, from: data) else {
                return WorkspaceLayoutPreferences()
            }
            return decoded
        }
        set {
            defaults.set(try? JSONEncoder().encode(newValue), forKey: Key.layoutPreferences)
        }
    }

    public var expandedFileTreePaths: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.expandedFileTreePaths) ?? []) }
        set { defaults.set(Array(newValue).sorted(), forKey: Key.expandedFileTreePaths) }
    }

    public var isModelOnboardingDismissed: Bool {
        get { defaults.bool(forKey: Key.modelOnboardingDismissed) }
        set { defaults.set(newValue, forKey: Key.modelOnboardingDismissed) }
    }

    public func recordWorkspace(path: String) {
        lastWorkspacePath = path
        var paths = recentWorkspacePaths.filter { $0 != path }
        paths.insert(path, at: 0)
        recentWorkspacePaths = paths
    }

    public var modelSettings: ModelSettingsViewState {
        get {
            ModelSettingsViewState(
                orchestratorModelID: defaults.string(forKey: Key.orchestratorModelID) ?? "",
                utilityModelID: defaults.string(forKey: Key.utilityModelID) ?? "",
                embeddingsModelID: defaults.string(forKey: Key.embeddingsModelID) ?? "",
                orchestratorQuantization: quantization(forKey: Key.orchestratorQuantization, default: .defaultFor(.orchestrator)),
                utilityQuantization: quantization(forKey: Key.utilityQuantization, default: .defaultFor(.utility)),
                embeddingsQuantization: quantization(forKey: Key.embeddingsQuantization, default: .defaultFor(.embeddings)),
                toolCallFormat: defaults.string(forKey: Key.toolCallFormat).flatMap(ModelToolCallFormat.init(rawValue:)),
                allowWrites: defaults.bool(forKey: Key.allowWrites),
                allowNetworkTools: defaults.bool(forKey: Key.allowNetworkTools),
                persistPromptHistory: defaults.object(forKey: Key.persistPromptHistory) as? Bool ?? true,
                maxToolIterations: defaults.object(forKey: Key.maxToolIterations) as? Int ?? 4,
                resourceProfile: defaults.string(forKey: Key.resourceProfile).flatMap(ResourceProfile.init(rawValue:)) ?? .automatic)
        }
        set {
            defaults.set(newValue.orchestratorModelID, forKey: Key.orchestratorModelID)
            defaults.set(newValue.utilityModelID, forKey: Key.utilityModelID)
            defaults.set(newValue.embeddingsModelID, forKey: Key.embeddingsModelID)
            defaults.set(newValue.orchestratorQuantization.rawValue, forKey: Key.orchestratorQuantization)
            defaults.set(newValue.utilityQuantization.rawValue, forKey: Key.utilityQuantization)
            defaults.set(newValue.embeddingsQuantization.rawValue, forKey: Key.embeddingsQuantization)
            defaults.set(newValue.toolCallFormat?.rawValue, forKey: Key.toolCallFormat)
            defaults.set(newValue.allowWrites, forKey: Key.allowWrites)
            defaults.set(newValue.allowNetworkTools, forKey: Key.allowNetworkTools)
            defaults.set(newValue.persistPromptHistory, forKey: Key.persistPromptHistory)
            defaults.set(newValue.maxToolIterations, forKey: Key.maxToolIterations)
            defaults.set(newValue.resourceProfile.rawValue, forKey: Key.resourceProfile)
        }
    }

    public var reasoningEffort: ReasoningEffort {
        get {
            defaults.string(forKey: Key.reasoningEffort)
                .flatMap(ReasoningEffort.init(rawValue:)) ?? .low
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.reasoningEffort)
        }
    }

    public var modelContextSettings: ModelContextSettingsViewState {
        get {
            ModelContextSettingsViewState(
                plainChatMaxAnswerTokens: defaults.integer(forKey: Key.plainChatMaxAnswerTokens),
                codeChatMaxAnswerTokens: defaults.integer(forKey: Key.codeChatMaxAnswerTokens),
                maxContextWindowTokens: defaults.integer(forKey: Key.maxContextWindowTokens),
                plainChatMaxContextWindowTokens: optionalInteger(forKey: Key.plainChatMaxContextWindowTokens),
                codeChatMaxContextWindowTokens: optionalInteger(forKey: Key.codeChatMaxContextWindowTokens),
                plainChatContextMode: defaults.string(forKey: Key.plainChatContextMode).flatMap(ConversationContextMode.init(rawValue:)) ?? .simple,
                codeChatContextMode: defaults.string(forKey: Key.codeChatContextMode).flatMap(ConversationContextMode.init(rawValue:)) ?? .smart)
        }
        set {
            let normalized = newValue.normalized()
            defaults.set(normalized.plainChatMaxAnswerTokens, forKey: Key.plainChatMaxAnswerTokens)
            defaults.set(normalized.codeChatMaxAnswerTokens, forKey: Key.codeChatMaxAnswerTokens)
            defaults.set(normalized.maxContextWindowTokens, forKey: Key.maxContextWindowTokens)
            defaults.set(normalized.plainChatMaxContextWindowTokens, forKey: Key.plainChatMaxContextWindowTokens)
            defaults.set(normalized.codeChatMaxContextWindowTokens, forKey: Key.codeChatMaxContextWindowTokens)
            defaults.set(normalized.plainChatContextMode.rawValue, forKey: Key.plainChatContextMode)
            defaults.set(normalized.codeChatContextMode.rawValue, forKey: Key.codeChatContextMode)
        }
    }

    private func quantization(forKey key: String, default defaultValue: QuantizationLevel) -> QuantizationLevel {
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        return QuantizationLevel(rawValue: defaults.integer(forKey: key)) ?? defaultValue
    }

    private func optionalInteger(forKey key: String) -> Int? {
        defaults.object(forKey: key) == nil ? nil : defaults.integer(forKey: key)
    }
}
