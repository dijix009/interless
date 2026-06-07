import Foundation
import Shared

public enum ConfigDiagnosticSeverity: String, Sendable, Equatable, Codable, CaseIterable {
    case info
    case warning
    case error
}

public struct ConfigDiagnostic: Sendable, Equatable, Codable, Identifiable {
    public var id: UUID
    public var severity: ConfigDiagnosticSeverity
    public var message: String
    public var sourcePath: String?

    public init(
        id: UUID = UUID(),
        severity: ConfigDiagnosticSeverity,
        message: String,
        sourcePath: String? = nil
    ) {
        self.id = id
        self.severity = severity
        self.message = message
        self.sourcePath = sourcePath
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case severity
        case message
        case sourcePath
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        severity = try container.decode(ConfigDiagnosticSeverity.self, forKey: .severity)
        message = try container.decode(String.self, forKey: .message)
        sourcePath = try container.decodeIfPresent(String.self, forKey: .sourcePath)
    }
}

public struct ConfigSource: Sendable, Equatable, Codable, Identifiable {
    public var id: String { path }
    public var path: String
    public var scope: ConfigScope
    public var exists: Bool
    public var modifiedAt: Date?

    public init(path: String, scope: ConfigScope, exists: Bool, modifiedAt: Date? = nil) {
        self.path = path
        self.scope = scope
        self.exists = exists
        self.modifiedAt = modifiedAt
    }
}

public enum ConfigScope: String, Sendable, Equatable, Codable, CaseIterable {
    case global
    case user
    case workspace
}

public enum AutoUpdateMode: Sendable, Equatable, Codable {
    case enabled
    case disabled
    case notify

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let bool = try? container.decode(Bool.self) {
            self = bool ? .enabled : .disabled
            return
        }
        let value = try container.decode(String.self)
        switch value {
        case "notify":
            self = .notify
        case "true", "enabled":
            self = .enabled
        case "false", "disabled":
            self = .disabled
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported autoupdate value '\(value)'")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .enabled:
            try container.encode(true)
        case .disabled:
            try container.encode(false)
        case .notify:
            try container.encode("notify")
        }
    }
}

public enum EntryState: String, Sendable, Equatable, Codable, CaseIterable {
    case enabled
    case disabled
}

public struct ConfiguredCommand: Sendable, Equatable, Codable {
    public var command: [String]
    public var extensions: [String]
    public var disabled: Bool

    public init(command: [String] = [], extensions: [String] = [], disabled: Bool = false) {
        self.command = command
        self.extensions = extensions
        self.disabled = disabled
    }
}

public enum BooleanOrMap<Value: Sendable & Equatable & Codable>: Sendable, Equatable, Codable {
    case enabled(Bool)
    case entries([String: Value])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let bool = try? container.decode(Bool.self) {
            self = .enabled(bool)
            return
        }
        self = .entries(try container.decode([String: Value].self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .enabled(let value):
            try container.encode(value)
        case .entries(let values):
            try container.encode(values)
        }
    }
}

public struct ReferenceDefinition: Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, Equatable, Codable, CaseIterable {
        case local
        case git
    }

    public var kind: Kind
    public var path: String?
    public var url: String?
    public var branch: String?

    public init(kind: Kind, path: String? = nil, url: String? = nil, branch: String? = nil) {
        self.kind = kind
        self.path = path
        self.url = url
        self.branch = branch
    }
}

public struct ExtensionDeclaration: Sendable, Equatable, Codable, Identifiable {
    public var id: String { package }
    public var package: String
    public var options: [String: JSONValue]
    public var disabled: Bool

    public init(package: String, options: [String: JSONValue] = [:], disabled: Bool = false) {
        self.package = package
        self.options = options
        self.disabled = disabled
    }

    private enum CodingKeys: String, CodingKey {
        case package
        case options
        case disabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        package = try container.decode(String.self, forKey: .package)
        options = try container.decodeIfPresent([String: JSONValue].self, forKey: .options) ?? [:]
        disabled = try container.decodeIfPresent(Bool.self, forKey: .disabled) ?? false
    }
}

public struct WatcherConfig: Sendable, Equatable, Codable {
    public var ignore: [String]

    public init(ignore: [String] = []) {
        self.ignore = ignore
    }
}

public struct AttachmentConfig: Sendable, Equatable, Codable {
    public struct Image: Sendable, Equatable, Codable {
        public var autoResize: Bool?
        public var maxWidth: Int?
        public var maxHeight: Int?
        public var maxBase64Bytes: Int?

        public init(autoResize: Bool? = nil, maxWidth: Int? = nil, maxHeight: Int? = nil, maxBase64Bytes: Int? = nil) {
            self.autoResize = autoResize
            self.maxWidth = maxWidth
            self.maxHeight = maxHeight
            self.maxBase64Bytes = maxBase64Bytes
        }

        private enum CodingKeys: String, CodingKey {
            case autoResize = "auto_resize"
            case maxWidth = "max_width"
            case maxHeight = "max_height"
            case maxBase64Bytes = "max_base64_bytes"
        }
    }

    public var image: Image?

    public init(image: Image? = nil) {
        self.image = image
    }
}

public struct ToolOutputConfig: Sendable, Equatable, Codable {
    public var maxLines: Int?
    public var maxBytes: Int?

    public init(maxLines: Int? = nil, maxBytes: Int? = nil) {
        self.maxLines = maxLines
        self.maxBytes = maxBytes
    }

    private enum CodingKeys: String, CodingKey {
        case maxLines = "max_lines"
        case maxBytes = "max_bytes"
    }
}

public struct ProviderDefinition: Sendable, Equatable, Codable {
    public struct Model: Sendable, Equatable, Codable {
        public var api: [String: JSONValue]
        public var limit: [String: JSONValue]
        public var cost: JSONValue?
        public var variants: [ModelVariant]
        public var disabled: Bool

        public init(
            api: [String: JSONValue] = [:],
            limit: [String: JSONValue] = [:],
            cost: JSONValue? = nil,
            variants: [ModelVariant] = [],
            disabled: Bool = false
        ) {
            self.api = api
            self.limit = limit
            self.cost = cost
            self.variants = variants
            self.disabled = disabled
        }
    }

    public var env: [String]
    public var options: [String: JSONValue]
    public var models: [String: Model]
    public var disabled: Bool

    public init(env: [String] = [], options: [String: JSONValue] = [:], models: [String: Model] = [:], disabled: Bool = false) {
        self.env = env
        self.options = options
        self.models = models
        self.disabled = disabled
    }
}

public struct ModelVariant: Sendable, Equatable, Codable, Identifiable {
    public var id: String
    public var options: [String: JSONValue]

    public init(id: String, options: [String: JSONValue] = [:]) {
        self.id = id
        self.options = options
    }
}

public struct AgentDefinition: Sendable, Equatable, Codable, Identifiable {
    public enum Mode: String, Sendable, Equatable, Codable, CaseIterable {
        case primary
        case subagent
        case all
    }

    public var id: String
    public var model: String?
    public var variant: String?
    public var description: String?
    public var system: String?
    public var mode: Mode
    public var color: String?
    public var steps: Int?
    public var hidden: Bool
    public var disabled: Bool
    public var permissions: [PolicyStatement]
    public var options: [String: JSONValue]

    public init(
        id: String,
        model: String? = nil,
        variant: String? = nil,
        description: String? = nil,
        system: String? = nil,
        mode: Mode = .primary,
        color: String? = nil,
        steps: Int? = nil,
        hidden: Bool = false,
        disabled: Bool = false,
        permissions: [PolicyStatement] = [],
        options: [String: JSONValue] = [:]
    ) {
        self.id = id
        self.model = model
        self.variant = variant
        self.description = description
        self.system = system
        self.mode = mode
        self.color = color
        self.steps = steps
        self.hidden = hidden
        self.disabled = disabled
        self.permissions = permissions
        self.options = options
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case model
        case variant
        case description
        case system
        case prompt
        case mode
        case color
        case steps
        case hidden
        case disabled
        case permissions
        case options
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        model = try container.decodeIfPresent(String.self, forKey: .model)
        variant = try container.decodeIfPresent(String.self, forKey: .variant)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        system = try container.decodeIfPresent(String.self, forKey: .system)
            ?? container.decodeIfPresent(String.self, forKey: .prompt)
        mode = try container.decodeIfPresent(Mode.self, forKey: .mode) ?? .primary
        color = try container.decodeIfPresent(String.self, forKey: .color)
        steps = try container.decodeIfPresent(Int.self, forKey: .steps)
        hidden = try container.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
        disabled = try container.decodeIfPresent(Bool.self, forKey: .disabled) ?? false
        permissions = try container.decodeIfPresent([PolicyStatement].self, forKey: .permissions) ?? []
        options = try container.decodeIfPresent([String: JSONValue].self, forKey: .options) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(model, forKey: .model)
        try container.encodeIfPresent(variant, forKey: .variant)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(system, forKey: .system)
        try container.encode(mode, forKey: .mode)
        try container.encodeIfPresent(color, forKey: .color)
        try container.encodeIfPresent(steps, forKey: .steps)
        try container.encode(hidden, forKey: .hidden)
        try container.encode(disabled, forKey: .disabled)
        try container.encode(permissions, forKey: .permissions)
        try container.encode(options, forKey: .options)
    }
}

public struct MCPServerConfig: Sendable, Equatable, Codable {
    public enum ServerType: String, Sendable, Equatable, Codable, CaseIterable {
        case local
        case remote
    }

    public struct OAuth: Sendable, Equatable, Codable {
        public var clientID: String?
        public var clientSecret: String?
        public var scope: String?
        public var callbackPort: Int?
        public var redirectURI: String?

        public init(clientID: String? = nil, clientSecret: String? = nil, scope: String? = nil, callbackPort: Int? = nil, redirectURI: String? = nil) {
            self.clientID = clientID
            self.clientSecret = clientSecret
            self.scope = scope
            self.callbackPort = callbackPort
            self.redirectURI = redirectURI
        }

        private enum CodingKeys: String, CodingKey {
            case clientID = "client_id"
            case clientSecret = "client_secret"
            case scope
            case callbackPort = "callback_port"
            case redirectURI = "redirect_uri"
        }
    }

    public var type: ServerType
    public var command: [String]
    public var environment: [String: String]
    public var url: String?
    public var headers: [String: String]
    public var oauth: OAuth?
    public var disabled: Bool
    public var timeout: Int?

    public init(
        type: ServerType,
        command: [String] = [],
        environment: [String: String] = [:],
        url: String? = nil,
        headers: [String: String] = [:],
        oauth: OAuth? = nil,
        disabled: Bool = false,
        timeout: Int? = nil
    ) {
        self.type = type
        self.command = command
        self.environment = environment
        self.url = url
        self.headers = headers
        self.oauth = oauth
        self.disabled = disabled
        self.timeout = timeout
    }
}

public struct MCPConfig: Sendable, Equatable, Codable {
    public var timeout: Int?
    public var servers: [String: MCPServerConfig]

    public init(timeout: Int? = nil, servers: [String: MCPServerConfig] = [:]) {
        self.timeout = timeout
        self.servers = servers
    }
}

public struct CompactionConfig: Sendable, Equatable, Codable {
    public struct Keep: Sendable, Equatable, Codable {
        public var tokens: Int?

        public init(tokens: Int? = nil) {
            self.tokens = tokens
        }
    }

    public var auto: Bool?
    public var prune: Bool?
    public var keep: Keep?
    public var buffer: Int?

    public init(auto: Bool? = nil, prune: Bool? = nil, keep: Keep? = nil, buffer: Int? = nil) {
        self.auto = auto
        self.prune = prune
        self.keep = keep
        self.buffer = buffer
    }
}

public struct ExperimentalConfig: Sendable, Equatable, Codable {
    public var policies: [PolicyStatement]

    public init(policies: [PolicyStatement] = []) {
        self.policies = policies
    }
}

public struct InterlessConfig: Sendable, Equatable, Codable {
    public var schema: String?
    public var shell: String?
    public var autoupdate: AutoUpdateMode?
    public var instructions: [String]
    public var skills: [String]
    public var references: [String: ReferenceDefinition]
    public var plugins: [ExtensionDeclaration]
    public var watcher: WatcherConfig?
    public var formatter: BooleanOrMap<ConfiguredCommand>?
    public var lsp: BooleanOrMap<ConfiguredCommand>?
    public var attachments: AttachmentConfig?
    public var toolOutput: ToolOutputConfig?
    public var share: String?
    public var enterprise: [String: JSONValue]
    public var username: String?
    public var providers: [String: ProviderDefinition]
    public var model: String?
    public var agents: [String: AgentDefinition]
    public var permissions: [PolicyStatement]
    public var experimental: ExperimentalConfig?
    public var mcp: MCPConfig?
    public var compaction: CompactionConfig?
    public var nativeExtensions: [NativeExtensionRecord]

    public init(
        schema: String? = nil,
        shell: String? = nil,
        autoupdate: AutoUpdateMode? = nil,
        instructions: [String] = [],
        skills: [String] = [],
        references: [String: ReferenceDefinition] = [:],
        plugins: [ExtensionDeclaration] = [],
        watcher: WatcherConfig? = nil,
        formatter: BooleanOrMap<ConfiguredCommand>? = nil,
        lsp: BooleanOrMap<ConfiguredCommand>? = nil,
        attachments: AttachmentConfig? = nil,
        toolOutput: ToolOutputConfig? = nil,
        share: String? = nil,
        enterprise: [String: JSONValue] = [:],
        username: String? = nil,
        providers: [String: ProviderDefinition] = [:],
        model: String? = nil,
        agents: [String: AgentDefinition] = [:],
        permissions: [PolicyStatement] = [],
        experimental: ExperimentalConfig? = nil,
        mcp: MCPConfig? = nil,
        compaction: CompactionConfig? = nil,
        nativeExtensions: [NativeExtensionRecord] = []
    ) {
        self.schema = schema
        self.shell = shell
        self.autoupdate = autoupdate
        self.instructions = instructions
        self.skills = skills
        self.references = references
        self.plugins = plugins
        self.watcher = watcher
        self.formatter = formatter
        self.lsp = lsp
        self.attachments = attachments
        self.toolOutput = toolOutput
        self.share = share
        self.enterprise = enterprise
        self.username = username
        self.providers = providers
        self.model = model
        self.agents = agents.mapValues { agent in
            var copy = agent
            if copy.id.isEmpty { copy.id = agents.first(where: { $0.value == agent })?.key ?? "" }
            return copy
        }
        self.permissions = permissions
        self.experimental = experimental
        self.mcp = mcp
        self.compaction = compaction
        self.nativeExtensions = nativeExtensions
    }

    public var policyStatements: [PolicyStatement] {
        permissions + (experimental?.policies ?? [])
    }

    public func merged(with override: InterlessConfig) -> InterlessConfig {
        var copy = self
        copy.schema = override.schema ?? schema
        copy.shell = override.shell ?? shell
        copy.autoupdate = override.autoupdate ?? autoupdate
        copy.instructions = orderedUnique(instructions + override.instructions)
        copy.skills = orderedUnique(skills + override.skills)
        copy.references.merge(override.references) { _, new in new }
        copy.plugins = mergeExtensions(copy.plugins, override.plugins)
        copy.watcher = override.watcher ?? watcher
        copy.formatter = override.formatter ?? formatter
        copy.lsp = override.lsp ?? lsp
        copy.attachments = override.attachments ?? attachments
        copy.toolOutput = override.toolOutput ?? toolOutput
        copy.share = override.share ?? share
        copy.enterprise.merge(override.enterprise) { _, new in new }
        copy.username = override.username ?? username
        copy.providers.merge(override.providers) { _, new in new }
        copy.model = override.model ?? model
        copy.agents.merge(override.agents) { _, new in new }
        copy.permissions += override.permissions
        if let experimental = override.experimental {
            let mergedPolicies = (copy.experimental?.policies ?? []) + experimental.policies
            copy.experimental = ExperimentalConfig(policies: mergedPolicies)
        }
        copy.mcp = mergeMCP(copy.mcp, override.mcp)
        copy.compaction = override.compaction ?? compaction
        copy.nativeExtensions = mergeNativeExtensions(copy.nativeExtensions, override.nativeExtensions)
        return copy
    }

    private enum CodingKeys: String, CodingKey {
        case schema = "$schema"
        case shell
        case autoupdate
        case instructions
        case skills
        case references
        case plugins
        case watcher
        case formatter
        case lsp
        case attachments
        case attachment
        case toolOutput = "tool_output"
        case share
        case enterprise
        case username
        case providers
        case provider
        case model
        case agents
        case agent
        case permissions
        case permission
        case experimental
        case mcp
        case compaction
        case nativeExtensions = "native_extensions"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schema = try container.decodeIfPresent(String.self, forKey: .schema)
        shell = try container.decodeIfPresent(String.self, forKey: .shell)
        autoupdate = try container.decodeIfPresent(AutoUpdateMode.self, forKey: .autoupdate)
        instructions = try container.decodeIfPresent([String].self, forKey: .instructions) ?? []
        skills = try container.decodeIfPresent([String].self, forKey: .skills) ?? []
        references = try container.decodeIfPresent([String: ReferenceDefinition].self, forKey: .references) ?? [:]
        plugins = try container.decodeIfPresent([ExtensionDeclaration].self, forKey: .plugins) ?? []
        watcher = try container.decodeIfPresent(WatcherConfig.self, forKey: .watcher)
        formatter = try container.decodeIfPresent(BooleanOrMap<ConfiguredCommand>.self, forKey: .formatter)
        lsp = try container.decodeIfPresent(BooleanOrMap<ConfiguredCommand>.self, forKey: .lsp)
        attachments = try container.decodeIfPresent(AttachmentConfig.self, forKey: .attachments)
            ?? container.decodeIfPresent(AttachmentConfig.self, forKey: .attachment)
        toolOutput = try container.decodeIfPresent(ToolOutputConfig.self, forKey: .toolOutput)
        share = try container.decodeIfPresent(String.self, forKey: .share)
        enterprise = try container.decodeIfPresent([String: JSONValue].self, forKey: .enterprise) ?? [:]
        username = try container.decodeIfPresent(String.self, forKey: .username)
        providers = try container.decodeIfPresent([String: ProviderDefinition].self, forKey: .providers)
            ?? container.decodeIfPresent([String: ProviderDefinition].self, forKey: .provider)
            ?? [:]
        model = try container.decodeIfPresent(String.self, forKey: .model)
        let decodedAgents = try container.decodeIfPresent([String: AgentDefinition].self, forKey: .agents)
            ?? container.decodeIfPresent([String: AgentDefinition].self, forKey: .agent)
            ?? [:]
        agents = decodedAgents.mapValues { $0 }
        for key in agents.keys {
            agents[key]?.id = key
        }
        permissions = try container.decodeIfPresent([PolicyStatement].self, forKey: .permissions)
            ?? container.decodeIfPresent([PolicyStatement].self, forKey: .permission)
            ?? []
        experimental = try container.decodeIfPresent(ExperimentalConfig.self, forKey: .experimental)
        mcp = try container.decodeIfPresent(MCPConfig.self, forKey: .mcp)
        compaction = try container.decodeIfPresent(CompactionConfig.self, forKey: .compaction)
        nativeExtensions = try container.decodeIfPresent([NativeExtensionRecord].self, forKey: .nativeExtensions) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(schema, forKey: .schema)
        try container.encodeIfPresent(shell, forKey: .shell)
        try container.encodeIfPresent(autoupdate, forKey: .autoupdate)
        try container.encode(instructions, forKey: .instructions)
        try container.encode(skills, forKey: .skills)
        try container.encode(references, forKey: .references)
        try container.encode(plugins, forKey: .plugins)
        try container.encodeIfPresent(watcher, forKey: .watcher)
        try container.encodeIfPresent(formatter, forKey: .formatter)
        try container.encodeIfPresent(lsp, forKey: .lsp)
        try container.encodeIfPresent(attachments, forKey: .attachments)
        try container.encodeIfPresent(toolOutput, forKey: .toolOutput)
        try container.encodeIfPresent(share, forKey: .share)
        try container.encode(enterprise, forKey: .enterprise)
        try container.encodeIfPresent(username, forKey: .username)
        try container.encode(providers, forKey: .providers)
        try container.encodeIfPresent(model, forKey: .model)
        try container.encode(agents, forKey: .agents)
        try container.encode(permissions, forKey: .permissions)
        try container.encodeIfPresent(experimental, forKey: .experimental)
        try container.encodeIfPresent(mcp, forKey: .mcp)
        try container.encodeIfPresent(compaction, forKey: .compaction)
        try container.encode(nativeExtensions, forKey: .nativeExtensions)
    }
}

public struct LoadedInterlessConfig: Sendable, Equatable, Codable {
    public var effective: InterlessConfig
    public var sources: [ConfigSource]
    public var diagnostics: [ConfigDiagnostic]
    public var loadedAt: Date

    public init(
        effective: InterlessConfig = InterlessConfig(),
        sources: [ConfigSource] = [],
        diagnostics: [ConfigDiagnostic] = [],
        loadedAt: Date = Date()
    ) {
        self.effective = effective
        self.sources = sources
        self.diagnostics = diagnostics
        self.loadedAt = loadedAt
    }

    public var hasErrors: Bool {
        diagnostics.contains { $0.severity == .error }
    }
}

public enum InterlessConfigLoader {
    public static let workspaceFileNames = [
        "interless.json",
        ".interless.json",
        ".interless/config.json",
        ".opencode.json",
        ".opencode/config.json",
    ]

    public static func defaultURLs(workspaceRoot: URL?) -> [(URL, ConfigScope)] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var urls: [(URL, ConfigScope)] = [
            (URL(fileURLWithPath: "/Library/Application Support/Interless/config.json"), .global),
            (home.appendingPathComponent("Library/Application Support/Interless/config.json"), .user),
            (home.appendingPathComponent(".interless/config.json"), .user),
        ]
        if let workspaceRoot {
            urls += workspaceFileNames.map { (workspaceRoot.appendingPathComponent($0), .workspace) }
        }
        return urls
    }

    public static func load(
        workspaceRoot: URL? = nil,
        urls: [(URL, ConfigScope)]? = nil,
        fileManager: FileManager = .default,
        now: Date = Date()
    ) -> LoadedInterlessConfig {
        let candidates = urls ?? defaultURLs(workspaceRoot: workspaceRoot)
        var effective = InterlessConfig()
        var sources: [ConfigSource] = []
        var diagnostics: [ConfigDiagnostic] = []
        let decoder = JSONDecoder()

        for (url, scope) in candidates {
            let path = url.path
            let attributes = try? fileManager.attributesOfItem(atPath: path)
            let exists = attributes != nil
            sources.append(ConfigSource(
                path: path,
                scope: scope,
                exists: exists,
                modifiedAt: attributes?[.modificationDate] as? Date))
            guard exists else { continue }
            do {
                let data = try Data(contentsOf: url)
                let decoded = try decoder.decode(InterlessConfig.self, from: data)
                effective = effective.merged(with: decoded)
            } catch {
                diagnostics.append(ConfigDiagnostic(
                    severity: .error,
                    message: "Failed to load config: \(error)",
                    sourcePath: path))
            }
        }

        diagnostics += validate(effective)
        return LoadedInterlessConfig(
            effective: effective,
            sources: sources,
            diagnostics: diagnostics,
            loadedAt: now)
    }

    public static func validate(_ config: InterlessConfig) -> [ConfigDiagnostic] {
        var diagnostics: [ConfigDiagnostic] = []
        for statement in config.policyStatements {
            if statement.action.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                diagnostics.append(ConfigDiagnostic(severity: .error, message: "Policy action must not be empty."))
            }
            if statement.resource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                diagnostics.append(ConfigDiagnostic(severity: .error, message: "Policy resource must not be empty."))
            }
        }
        for server in config.mcp?.servers.values ?? [String: MCPServerConfig]().values where server.type == .remote && server.disabled == false {
            diagnostics.append(ConfigDiagnostic(
                severity: .warning,
                message: "Remote MCP server '\(server.url ?? "unknown")' requires explicit trusted network enablement before use."))
        }
        for plugin in config.plugins where plugin.package.hasSuffix(".js") || plugin.package.hasSuffix(".ts") {
            diagnostics.append(ConfigDiagnostic(
                severity: .error,
                message: "JavaScript and TypeScript plugins are not supported by native Interless: \(plugin.package)"))
        }
        return diagnostics
    }
}

private func orderedUnique(_ values: [String]) -> [String] {
    var seen = Set<String>()
    var result: [String] = []
    for value in values {
        guard seen.insert(value).inserted else { continue }
        result.append(value)
    }
    return result
}

private func mergeExtensions(_ base: [ExtensionDeclaration], _ override: [ExtensionDeclaration]) -> [ExtensionDeclaration] {
    var byPackage = Dictionary(uniqueKeysWithValues: base.map { ($0.package, $0) })
    for item in override {
        byPackage[item.package] = item
    }
    return byPackage.values.sorted { $0.package < $1.package }
}

private func mergeNativeExtensions(_ base: [NativeExtensionRecord], _ override: [NativeExtensionRecord]) -> [NativeExtensionRecord] {
    var byID = Dictionary(uniqueKeysWithValues: base.map { ($0.id, $0) })
    for item in override {
        byID[item.id] = item
    }
    return byID.values.sorted { $0.id < $1.id }
}

private func mergeMCP(_ base: MCPConfig?, _ override: MCPConfig?) -> MCPConfig? {
    guard let override else { return base }
    guard var result = base else { return override }
    result.timeout = override.timeout ?? result.timeout
    result.servers.merge(override.servers) { _, new in new }
    return result
}
