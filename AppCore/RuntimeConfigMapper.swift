import Foundation
import Core
import Shared
import Tooling
import UI
import Workspace

public struct RuntimeConfigApplication: Sendable, Equatable {
    public var settings: ModelSettingsViewState
    public var toolPolicy: ToolExecutionPolicy
    public var formatterRegistry: FormatterRegistry
    public var languageServers: [LanguageServerDefinition]
    public var mcpSettings: MCPSettingsViewState

    public init(
        settings: ModelSettingsViewState,
        toolPolicy: ToolExecutionPolicy,
        formatterRegistry: FormatterRegistry = FormatterRegistry(),
        languageServers: [LanguageServerDefinition] = [],
        mcpSettings: MCPSettingsViewState = MCPSettingsViewState()
    ) {
        self.settings = settings
        self.toolPolicy = toolPolicy
        self.formatterRegistry = formatterRegistry
        self.languageServers = languageServers
        self.mcpSettings = mcpSettings
    }
}

public enum RuntimeConfigMapper {
    public static func resolve(
        config: InterlessConfig?,
        settings baseSettings: ModelSettingsViewState,
        resourceBudget: ResourceBudget = ResourceBudget.resolved(for: .automatic)
    ) -> RuntimeConfigApplication {
        guard let config else {
            let writePermission: ToolPermissionEffect = baseSettings.allowWrites ? .allow : .deny
            let networkPermission: ToolPermissionEffect = baseSettings.allowNetworkTools ? .allow : .deny
            let policy = ToolExecutionPolicy(
                allowsWrites: baseSettings.allowWrites,
                resourceBudget: resourceBudget,
                networkEnabled: baseSettings.allowNetworkTools,
                writePermission: writePermission,
                networkPermission: networkPermission)
            return RuntimeConfigApplication(
                settings: baseSettings,
                toolPolicy: policy)
        }

        let settings = resolvedSettings(config: config, base: baseSettings)
        let policy = resolvedPolicy(config: config, settings: settings, resourceBudget: resourceBudget)
        return RuntimeConfigApplication(
            settings: settings,
            toolPolicy: policy,
            formatterRegistry: formatterRegistry(config.formatter),
            languageServers: languageServerDefinitions(config.lsp),
            mcpSettings: mcpSettings(config.mcp, trustedNetworkEnabled: policy.canRequestNetwork))
    }

    public static func formatterRegistry(
        _ config: BooleanOrMap<ConfiguredCommand>?
    ) -> FormatterRegistry {
        FormatterRegistry(formatters: commandDefinitions(config).map { item in
            FormatterDefinition(
                id: item.id,
                extensions: item.command.extensions,
                command: item.command.command,
                isEnabled: !item.command.disabled)
        })
    }

    public static func languageServerDefinitions(
        _ config: BooleanOrMap<ConfiguredCommand>?
    ) -> [LanguageServerDefinition] {
        commandDefinitions(config).map { item in
            LanguageServerDefinition(
                id: item.id,
                extensions: item.command.extensions,
                command: item.command.command,
                isEnabled: !item.command.disabled)
        }
    }

    public static func mcpSettings(
        _ config: MCPConfig?,
        trustedNetworkEnabled: Bool
    ) -> MCPSettingsViewState {
        let servers = (config?.servers ?? [:])
            .map { id, server in
                MCPServerViewState(
                    id: id,
                    name: id,
                    transport: server.type == .remote ? .remote : .local,
                    command: server.command,
                    url: server.url,
                    timeoutSeconds: server.timeout ?? config?.timeout,
                    isEnabled: !server.disabled,
                    isTrusted: server.type == .local || trustedNetworkEnabled)
            }
            .sorted { $0.name < $1.name }
        return MCPSettingsViewState(
            defaultTimeoutSeconds: config?.timeout,
            trustedNetworkEnabled: trustedNetworkEnabled,
            servers: servers)
    }

    private static func resolvedSettings(
        config: InterlessConfig,
        base: ModelSettingsViewState
    ) -> ModelSettingsViewState {
        var settings = base
        if let model = trimmed(config.model) {
            settings.orchestratorModelID = model
            settings.utilityModelID = model
        }
        if let model = firstConfiguredAgentModel(config, ids: ["build", "plan"]) {
            settings.orchestratorModelID = model
        }
        if let model = firstConfiguredAgentModel(config, ids: ["general"]) {
            settings.utilityModelID = model
            if settings.usesSingleAgentMode() {
                settings.orchestratorModelID = model
            }
        }
        if let steps = firstConfiguredAgentSteps(config, ids: ["build", "plan", "general"]) {
            settings.maxToolIterations = max(0, steps)
        }
        settings.allowWrites = policyEffect(
            config: config,
            action: "tool.write",
            fallback: settings.allowWrites) != .deny
        settings.allowNetworkTools = policyEffect(
            config: config,
            action: "tool.network",
            fallback: settings.allowNetworkTools) != .deny
        return settings
    }

    private static func resolvedPolicy(
        config: InterlessConfig,
        settings: ModelSettingsViewState,
        resourceBudget: ResourceBudget
    ) -> ToolExecutionPolicy {
        let writePermission = policyEffect(
            config: config,
            action: "tool.write",
            fallback: settings.allowWrites)
        let networkPermission = policyEffect(
            config: config,
            action: "tool.network",
            fallback: settings.allowNetworkTools)
        return ToolExecutionPolicy(
            allowsWrites: writePermission == .allow,
            networkEnabled: networkPermission == .allow,
            writePermission: toolPermissionEffect(writePermission),
            networkPermission: toolPermissionEffect(networkPermission),
            timeoutSeconds: 30,
            maxOutputBytes: config.toolOutput?.maxBytes ?? resourceBudget.maxToolOutputBytes,
            maxWriteBytes: resourceBudget.maxIndexedFileSizeBytes)
    }

    private static func commandDefinitions(
        _ config: BooleanOrMap<ConfiguredCommand>?
    ) -> [(id: String, command: ConfiguredCommand)] {
        guard case let .entries(entries) = config else { return [] }
        return entries
            .filter { _, command in !command.command.isEmpty && !command.extensions.isEmpty }
            .map { id, command in (id: id, command: command) }
            .sorted { $0.id < $1.id }
    }

    private static func firstConfiguredAgentModel(
        _ config: InterlessConfig,
        ids: [String]
    ) -> String? {
        for id in ids {
            guard let model = trimmed(config.agents[id]?.model) else { continue }
            return model
        }
        return nil
    }

    private static func firstConfiguredAgentSteps(
        _ config: InterlessConfig,
        ids: [String]
    ) -> Int? {
        for id in ids {
            guard let steps = config.agents[id]?.steps else { continue }
            return steps
        }
        return nil
    }

    private static func policyEffect(
        config: InterlessConfig,
        action: String,
        fallback: Bool
    ) -> PolicyEffect {
        let decision = PolicyEvaluator(statements: config.policyStatements).evaluate(
            action: action,
            resource: "*",
            fallback: fallback ? .allow : .deny)
        return decision.effect
    }

    private static func toolPermissionEffect(_ effect: PolicyEffect) -> ToolPermissionEffect {
        switch effect {
        case .allow:
            return .allow
        case .ask:
            return .ask
        case .deny:
            return .deny
        }
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
