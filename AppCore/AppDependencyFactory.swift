import Foundation
import Agents
import CloudInference
import Core
import MLXEngine
import Persistence
import Shared
import Tooling
import UI
import Workspace

public enum AppRuntimeError: Error, Sendable, Equatable {
    case workspaceNotOpen
    case invalidModelSettings([String])
}

public typealias ModelLoadProgressReporter = @Sendable (
    _ modelID: String,
    _ role: ModelRole,
    _ fractionCompleted: Double
) -> Void

public struct WorkspaceEnvironment: Sendable {
    public var root: URL
    public var reindex: @Sendable () async -> AsyncStream<IndexingProgress>
    public var watch: @Sendable () async -> AsyncStream<IndexingProgress>
    public var search: @Sendable (_ query: String, _ limit: Int) async throws -> [SearchHit]
    public var previewFile: @Sendable (_ relativePath: String) async throws -> FilePreviewViewState
    public var fileTree: @Sendable () async throws -> [FileTreeNode]
    public var gitStatus: @Sendable () async -> GitStatus
    public var gitDiff: @Sendable (_ path: String?) async throws -> String
    public var revertSnapshot: @Sendable (_ snapshotID: String) async throws -> WorkspaceMutationRevertResult
    public var executeTool: @Sendable (_ request: ToolRequest, _ settings: ModelSettingsViewState, _ runtimeHooks: ToolRuntimeHooks?) async throws -> ToolResult
    public var runAgent: @Sendable (_ task: AgentTask, _ settings: ModelSettingsViewState, _ runtimeHooks: ToolRuntimeHooks?) async -> AsyncThrowingStream<AgentEvent, Error>
    /// Runs a read-only sub-agent (e.g. `explore`/`review`) synchronously in an
    /// isolated context and returns its summary. Used by the `task` tool.
    public var runSubagent: @Sendable (_ prompt: String, _ agent: String?, _ settings: ModelSettingsViewState) async throws -> String
    public var embedTexts: @Sendable (_ texts: [String]) async throws -> [EmbeddingVector]?
    public var loadModels: @Sendable (_ settings: ModelSettingsViewState, _ progressReporter: ModelLoadProgressReporter?) async throws -> Void
    public var unloadModels: @Sendable () async -> Void
    public var memoryPolicy: @Sendable () async -> MemoryPolicyState

    public init(
        root: URL,
        reindex: @escaping @Sendable () async -> AsyncStream<IndexingProgress>,
        watch: @escaping @Sendable () async -> AsyncStream<IndexingProgress>,
        search: @escaping @Sendable (_ query: String, _ limit: Int) async throws -> [SearchHit],
        previewFile: @escaping @Sendable (_ relativePath: String) async throws -> FilePreviewViewState,
        fileTree: @escaping @Sendable () async throws -> [FileTreeNode],
        gitStatus: @escaping @Sendable () async -> GitStatus,
        gitDiff: @escaping @Sendable (_ path: String?) async throws -> String,
        revertSnapshot: @escaping @Sendable (_ snapshotID: String) async throws -> WorkspaceMutationRevertResult = { _ in
            throw AppRuntimeError.workspaceNotOpen
        },
        executeTool: @escaping @Sendable (_ request: ToolRequest, _ settings: ModelSettingsViewState, _ runtimeHooks: ToolRuntimeHooks?) async throws -> ToolResult = { _, _, _ in
            throw AppRuntimeError.workspaceNotOpen
        },
        runAgent: @escaping @Sendable (_ task: AgentTask, _ settings: ModelSettingsViewState, _ runtimeHooks: ToolRuntimeHooks?) async -> AsyncThrowingStream<AgentEvent, Error>,
        runSubagent: @escaping @Sendable (_ prompt: String, _ agent: String?, _ settings: ModelSettingsViewState) async throws -> String = { _, _, _ in
            throw AppRuntimeError.workspaceNotOpen
        },
        embedTexts: @escaping @Sendable (_ texts: [String]) async throws -> [EmbeddingVector]? = { _ in nil },
        loadModels: @escaping @Sendable (_ settings: ModelSettingsViewState, _ progressReporter: ModelLoadProgressReporter?) async throws -> Void,
        unloadModels: @escaping @Sendable () async -> Void,
        memoryPolicy: @escaping @Sendable () async -> MemoryPolicyState = {
            MemoryPolicyState()
        }
    ) {
        self.root = root
        self.reindex = reindex
        self.watch = watch
        self.search = search
        self.previewFile = previewFile
        self.fileTree = fileTree
        self.gitStatus = gitStatus
        self.gitDiff = gitDiff
        self.revertSnapshot = revertSnapshot
        self.executeTool = executeTool
        self.runAgent = runAgent
        self.runSubagent = runSubagent
        self.embedTexts = embedTexts
        self.loadModels = loadModels
        self.unloadModels = unloadModels
        self.memoryPolicy = memoryPolicy
    }
}

public struct ToolRuntimeHooks: Sendable {
    public var permissionAuthorizer: ToolPermissionAuthorizer?
    public var settlementHandlers: ToolSettlementHandlers

    public init(
        permissionAuthorizer: ToolPermissionAuthorizer? = nil,
        settlementHandlers: ToolSettlementHandlers = .empty
    ) {
        self.permissionAuthorizer = permissionAuthorizer
        self.settlementHandlers = settlementHandlers
    }
}

public protocol AppDependencyFactory: Sendable {
    func makeWorkspaceEnvironment(
        root: URL,
        settings: ModelSettingsViewState,
        metricsRecorder: MetricsRecorder,
        eventBus: EventBus,
        config: LoadedInterlessConfig?
    ) async throws -> WorkspaceEnvironment
}

public struct LiveAppDependencyFactory: AppDependencyFactory {
    public init() {}

    public func makeWorkspaceEnvironment(
        root: URL,
        settings: ModelSettingsViewState,
        metricsRecorder: MetricsRecorder,
        eventBus: EventBus,
        config: LoadedInterlessConfig? = nil
    ) async throws -> WorkspaceEnvironment {
        let budget = ResourceBudget.resolved(for: settings.resourceProfile)
        let agentCatalog = AgentCatalog(configured: config?.effective.agents ?? [:])
        let coordinator = MemoryBudgetCoordinator(
            requestedProfile: settings.resourceProfile,
            metrics: metricsRecorder,
            events: eventBus)
        let store = try PersistenceBootstrap.liveStore(forWorkspaceRoot: root)
        let workspaceConfig = WorkspaceConfig(maxFileSizeBytes: budget.maxIndexedFileSizeBytes)
        let scanner = FileSystemScanner(config: workspaceConfig)
        let git = LibGit2Repository()
        let loader = DiskFileContentLoader()
        let previewLoader = SafeFilePreviewLoader()
        let indexer = WorkspaceIndexer(
            root: root,
            scanner: scanner,
            store: store,
            git: git,
            loader: loader,
            config: workspaceConfig,
            resourceBudget: budget,
            metrics: metricsRecorder)
        let watcher = WorkspaceWatcher(
            root: root,
            eventStream: FSEventsWorkspaceEventStream(),
            indexer: indexer)
        let snapshotStore = WorkspaceSnapshotStore(
            root: root,
            maxEntryBytes: budget.maxIndexedFileSizeBytes)
        let controller = LazyInferenceController(
            resourceProfile: settings.resourceProfile,
            memoryCoordinator: coordinator)

        return WorkspaceEnvironment(
            root: root,
            reindex: {
                await indexer.reindex()
            },
            watch: {
                await watcher.start()
            },
            search: { query, limit in
                let lexical = try await indexer.search(query, limit: limit)
                guard await controller.loadedRoles().contains(.embeddings) else {
                    return lexical
                }
                let vectors = try await controller.embed(texts: ["search_query: \(query)"])
                guard let queryVector = vectors.first else { return lexical }
                let semantic = try await store.semanticSearch(vector: queryVector, limit: limit)
                return Self.mergeSearchHits(lexical: lexical, semantic: semantic, limit: limit)
            },
            previewFile: { relativePath in
                try await previewLoader.preview(root: root, relativePath: relativePath)
            },
            fileTree: {
                let stream = try await scanner.scan(root: root)
                var paths: [String] = []
                for await entry in stream where !entry.isDirectory {
                    guard paths.count < budget.fileTreePathLimit else { break }
                    paths.append(entry.relativePath)
                }
                return FileTreeNode.grouped(paths: paths)
            },
            gitStatus: {
                await git.snapshot(root: root)
            },
            gitDiff: { path in
                try await git.diff(root: root, path: path)
            },
            revertSnapshot: { snapshotID in
                guard let id = UUID(uuidString: snapshotID) else {
                    throw WorkspaceSnapshotError.snapshotNotFound(UUID())
                }
                return try await snapshotStore.revert(id)
            },
            executeTool: { request, currentSettings, runtimeHooks in
                let budget = ResourceBudget.resolved(for: currentSettings.resourceProfile)
                let runtime = RuntimeConfigMapper.resolve(
                    config: config?.effective,
                    settings: currentSettings,
                    resourceBudget: budget)
                let policy = runtime.toolPolicy
                let loop = try ToolExecutionLoop(
                    root: root,
                    policy: policy,
                    mutationRecorder: Self.mutationRecorder(snapshotStore: snapshotStore),
                    managedOutputStore: ManagedToolOutputStore(maxBytesPerStream: policy.maxOutputBytes),
                    permissionAuthorizer: runtimeHooks?.permissionAuthorizer,
                    settlementHandlers: runtimeHooks?.settlementHandlers ?? .empty)
                return try await loop.execute(request)
            },
            runAgent: { task, currentSettings, runtimeHooks in
                let resolvedController = await controller.resolve()
                let plainChat = Self.isPlainChatTask(task)
                let runtime = RuntimeConfigMapper.resolve(
                    config: config?.effective,
                    settings: currentSettings,
                    resourceBudget: ResourceBudget.resolved(for: currentSettings.resourceProfile))
                let canAdvertiseNativeTools = runtime.settings.toolCallFormat != nil
                return await Self.makeAgent(
                    root: root,
                    store: store,
                    controller: resolvedController,
                    settings: runtime.settings,
                    metricsRecorder: metricsRecorder,
                    includesWorkspaceContext: !plainChat,
                    advertisesTools: !plainChat && canAdvertiseNativeTools,
                    snapshotStore: snapshotStore,
                    agentCatalog: agentCatalog,
                    runtimeConfig: config?.effective,
                    runtimeHooks: runtimeHooks
                ).run(task: task)
            },
            runSubagent: { prompt, agent, currentSettings in
                let resolvedController = await controller.resolve()
                let runtime = RuntimeConfigMapper.resolve(
                    config: config?.effective,
                    settings: currentSettings,
                    resourceBudget: ResourceBudget.resolved(for: currentSettings.resourceProfile))
                let trimmedAgent = agent?.trimmingCharacters(in: .whitespacesAndNewlines)
                // Only public (non-hidden) subagents like explore/review are delegable;
                // anything else (incl. hidden internal agents, unknown ids) → explore.
                let agentID = (trimmedAgent.map { agentCatalog.isDelegableSubagent($0) } ?? false) ? trimmedAgent! : "explore"
                // Safe no-throw stubs for session/agent tools a sub-agent shouldn't use:
                // the task tool isn't advertised, but the scoped registry can still
                // decode a hallucinated call — graceful guidance keeps the sub-agent
                // (and the parent turn) from crashing on a missing handler.
                let subagentHooks = ToolRuntimeHooks(settlementHandlers: ToolSettlementHandlers(
                    askQuestion: { _ in
                        ToolQuestionResponse(answer: "No user is available to a sub-agent; proceed with your best judgment.")
                    },
                    spawnSubagent: { _, _ in
                        "Nested sub-agents are not allowed. Use read-only tools and report your findings."
                    },
                    recallHistory: { _, _ in
                        "Conversation recall is unavailable to sub-agents."
                    }))
                // Read-only sub-agent in its own context: same workspace tools minus
                // writes/network and the task tool (no recursion). Synchronous, so it
                // reuses the orchestrator gate and stays serial / 8GB-safe.
                let subagent = await Self.makeAgent(
                    root: root,
                    store: store,
                    controller: resolvedController,
                    settings: runtime.settings,
                    metricsRecorder: metricsRecorder,
                    includesWorkspaceContext: true,
                    advertisesTools: runtime.settings.toolCallFormat != nil,
                    explorationOnly: true,
                    readOnly: true,
                    snapshotStore: snapshotStore,
                    agentCatalog: agentCatalog,
                    runtimeConfig: config?.effective,
                    runtimeHooks: subagentHooks)
                let dispatcher = SubagentDispatcher(catalog: agentCatalog, agent: subagent)
                let result = try await dispatcher.dispatch(prompt: prompt, agentID: agentID)
                return result.text
            },
            embedTexts: { texts in
                guard !texts.isEmpty else { return [] }
                let resolvedController = await controller.resolve()
                guard await resolvedController.loadedRoles.contains(.embeddings) else { return nil }
                return try await resolvedController.embed(texts: texts)
            },
            loadModels: { currentSettings, progressReporter in
                let resolvedController = await controller.resolve()
                let runtime = RuntimeConfigMapper.resolve(
                    config: config?.effective,
                    settings: currentSettings,
                    resourceBudget: ResourceBudget.resolved(for: currentSettings.resourceProfile))
                let runtimeSettings = runtime.settings
                let errors = runtimeSettings.validationErrors()
                guard errors.isEmpty else { throw AppRuntimeError.invalidModelSettings(errors) }
                let singleAgentMode = Self.usesSingleAgentMode(runtimeSettings)
                let orchestratorModelID = Self.agentModelID(agentCatalog: agentCatalog, agentIDs: ["build", "plan"], fallback: runtimeSettings.orchestratorModelID)
                let utilityModelID = Self.agentModelID(agentCatalog: agentCatalog, agentIDs: ["general"], fallback: runtimeSettings.utilityModelID)
                let singleModelID = Self.agentModelID(agentCatalog: agentCatalog, agentIDs: ["general", "build"], fallback: runtimeSettings.orchestratorModelID)
                try Self.validateCloudUsage(
                    orchestrator: singleAgentMode ? singleModelID : orchestratorModelID,
                    utility: singleAgentMode ? "" : utilityModelID,
                    embeddings: runtimeSettings.embeddingsModelID,
                    allowCloudModels: runtimeSettings.allowCloudModels)
                await resolvedController.unload(role: .orchestrator)
                await resolvedController.unload(role: .utility)
                await resolvedController.unload(role: .embeddings)
                // Opt-in speculative decoding: best-effort draft load after the
                // orchestrator. The controller gates on largeRAM + memory headroom
                // and a tokenizer-compat probe; failure never blocks chat.
                func loadDraftIfEnabled() async {
                    let draftID = runtimeSettings.speculativeDraftModelID
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    guard runtimeSettings.enableSpeculativeDecoding, !draftID.isEmpty else { return }
                    _ = try? await resolvedController.loadDraftModel(id: draftID)
                }
                if singleAgentMode {
                    try await resolvedController.loadModel(
                        id: singleModelID,
                        role: .orchestrator,
                        quantization: runtimeSettings.orchestratorQuantization,
                        toolCallFormat: runtimeSettings.toolCallFormat,
                        progressHandler: progressReporter)
                    await loadDraftIfEnabled()
                    return
                }
                try await resolvedController.loadModel(
                    id: orchestratorModelID,
                    role: .orchestrator,
                    quantization: runtimeSettings.orchestratorQuantization,
                    toolCallFormat: runtimeSettings.toolCallFormat,
                    progressHandler: progressReporter)
                await loadDraftIfEnabled()
                try await resolvedController.loadModel(
                    id: utilityModelID,
                    role: .utility,
                    quantization: runtimeSettings.utilityQuantization,
                    toolCallFormat: runtimeSettings.toolCallFormat,
                    progressHandler: progressReporter)
                let embeddingID = runtimeSettings.embeddingsModelID.trimmingCharacters(in: .whitespacesAndNewlines)
                if !embeddingID.isEmpty {
                    try await resolvedController.loadModel(
                        id: embeddingID,
                        role: .embeddings,
                        quantization: runtimeSettings.embeddingsQuantization,
                        progressHandler: progressReporter)
                    await Self.backfillEmbeddings(
                        root: root,
                        scanner: scanner,
                        previewLoader: previewLoader,
                        controller: resolvedController,
                        store: store,
                        budget: budget,
                        metricsRecorder: metricsRecorder)
                }
            },
            unloadModels: {
                await controller.unloadAll()
            },
            memoryPolicy: {
                await controller.memoryPolicyState()
            })
    }

    /// Gates hosted (cloud) model usage: cloud orchestrator/utility roles require
    /// explicit consent, and cloud embedding models are unsupported. Reuses the
    /// `invalidModelSettings` surface so the message reaches the UI like any other
    /// settings problem.
    static func validateCloudUsage(
        orchestrator: String,
        utility: String,
        embeddings: String,
        allowCloudModels: Bool
    ) throws {
        var errors: [String] = []
        if CloudModelResolver.isCloud(embeddings) {
            errors.append("Cloud embedding models are not supported; use a local embeddings model.")
        }
        if !allowCloudModels {
            for id in [orchestrator, utility] where CloudModelResolver.isCloud(id) {
                errors.append("\"\(id)\" is a cloud model. Enable \"Allow cloud models\" in Settings to use it.")
            }
        }
        guard errors.isEmpty else { throw AppRuntimeError.invalidModelSettings(errors) }
    }

    private static func makeAgent(
        root: URL,
        store: any WorkspaceIndexStore,
        controller: InferenceController,
        settings: ModelSettingsViewState,
        metricsRecorder: MetricsRecorder,
        includesWorkspaceContext: Bool = true,
        advertisesTools: Bool = true,
        explorationOnly: Bool = false,
        readOnly: Bool = false,
        snapshotStore: WorkspaceSnapshotStore? = nil,
        agentCatalog: AgentCatalog = .default,
        runtimeConfig: InterlessConfig? = nil,
        runtimeHooks: ToolRuntimeHooks? = nil
    ) async -> AgentOrchestrator {
        let budget = ResourceBudget.resolved(for: settings.resourceProfile)
        let runtime = RuntimeConfigMapper.resolve(
            config: runtimeConfig,
            settings: settings,
            resourceBudget: budget)
        let runtimeSettings = runtime.settings
        let singleAgentMode = usesSingleAgentMode(runtimeSettings)
        var policy = runtime.toolPolicy
        if readOnly {
            // Sub-agents are read-only regardless of workspace config: deny writes,
            // network/shell, and the verify loop so only read/search tools advertise.
            policy.writePermission = .deny
            policy.networkPermission = .deny
            policy.verifyPermission = .deny
        }
        let toolLoop = includesWorkspaceContext
            ? (try? ToolExecutionLoop(
                root: root,
                policy: policy,
                mutationRecorder: mutationRecorder(snapshotStore: snapshotStore),
                managedOutputStore: ManagedToolOutputStore(maxBytesPerStream: policy.maxOutputBytes),
                permissionAuthorizer: runtimeHooks?.permissionAuthorizer,
                settlementHandlers: runtimeHooks?.settlementHandlers ?? .empty))
            : nil
        // Advertise recall_history only in workspace context with an embeddings model
        // loaded — otherwise there are no message embeddings to search and the tool
        // would always return empty.
        let embeddingsLoaded = await controller.loadedRoles.contains(.embeddings)
        let advertisesRecall = includesWorkspaceContext && embeddingsLoaded
        let registry = WorkspaceToolRegistry(
            policy: policy, advertisesTools: advertisesTools, advertisesRecall: advertisesRecall, explorationOnly: explorationOnly)
        // Autonomous verify→fix: wire a build/test verifier only when writes are
        // authorized (code mode) and verification is enabled in config.
        let verificationEnabled = runtimeConfig?.verification?.enabled ?? true
        let canVerify = verificationEnabled
            && toolLoop != nil
            && policy.writePermission != .deny
            && policy.verifyPermission != .deny
        let verifier: WorkspaceVerifier?
        if canVerify, let loop = toolLoop {
            verifier = { paths in await loop.verify(changedPaths: paths) }
        } else {
            verifier = nil
        }
        let loopPolicy = AgentLoopPolicy(
            maxToolIterations: runtimeSettings.maxToolIterations,
            maxVerifyAttempts: canVerify ? max(0, runtimeConfig?.verification?.maxAttempts ?? 2) : 0)
        let contextBuilder = ContextBuilder(
            searchProvider: includesWorkspaceContext ? WorkspaceIndexSearchProvider(store: store) : nil,
            budget: budget,
            metrics: metricsRecorder)
        let orchestratorAgent = OrchestratorAgent(
            model: controller,
            toolLoop: toolLoop,
            verifier: verifier,
            toolRegistry: registry,
            loopPolicy: loopPolicy,
            resourceBudget: budget,
            systemPrompt: singleAgentMode
                ? agentCatalog.systemPrompt(agentID: "general", fallback: "You are the local chat agent. Answer directly, use tools only when useful, and keep memory use bounded.")
                : agentCatalog.systemPrompt(agentID: "build", fallback: "You are the orchestrator agent. Reason about architecture, planning, refactors, and multi-file changes. Be precise and actionable."),
            agentCatalog: agentCatalog,
            defaultAgentID: singleAgentMode ? "general" : "build")
        let utilityAgent = UtilityAgent(
            model: controller,
            toolLoop: toolLoop,
            verifier: verifier,
            toolRegistry: registry,
            loopPolicy: loopPolicy,
            resourceBudget: budget,
            systemPrompt: agentCatalog.systemPrompt(agentID: "general", fallback: "You are the utility agent. Prefer concise answers for search, lint, summaries, tests, and lightweight code analysis."),
            agentCatalog: agentCatalog,
            defaultAgentID: "general")
        let routedUtilityAgent: any StreamingAgent = singleAgentMode ? orchestratorAgent : utilityAgent
        return AgentOrchestrator(
            orchestrator: orchestratorAgent,
            utility: routedUtilityAgent,
            contextBuilder: contextBuilder,
            toolLoop: toolLoop,
            router: AgentRouter(forcedRoute: singleAgentMode ? .orchestrator : nil, catalog: agentCatalog))
    }

    private static func agentModelID(agentCatalog: AgentCatalog, agentIDs: [String], fallback: String) -> String {
        for agentID in agentIDs {
            if let modelID = agentCatalog.modelID(agentID: agentID) {
                return modelID
            }
        }
        return fallback
    }

    private static func mutationRecorder(
        snapshotStore: WorkspaceSnapshotStore?
    ) -> ToolExecutionLoop.MutationRecorder? {
        guard let snapshotStore else { return nil }
        return { paths, reason in
            let filtered = paths.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            guard !filtered.isEmpty else { return nil }
            let snapshot = try await snapshotStore.createSnapshot(paths: filtered, reason: reason)
            return snapshot.id.uuidString
        }
    }

    private static func isPlainChatTask(_ task: AgentTask) -> Bool {
        task.observations.contains("interless.mode=plainChat")
    }

    private static func usesSingleAgentMode(_ settings: ModelSettingsViewState) -> Bool {
        settings.usesSingleAgentMode()
    }

    private static func mergeSearchHits(
        lexical: [SearchHit],
        semantic: [SearchHit],
        limit: Int
    ) -> [SearchHit] {
        var byPath: [String: SearchHit] = [:]
        for hit in lexical {
            byPath[hit.relativePath] = hit
        }
        for hit in semantic {
            if var existing = byPath[hit.relativePath] {
                existing.score = min(existing.score, hit.score)
                existing.snippet = existing.snippet ?? hit.snippet
                byPath[hit.relativePath] = existing
            } else {
                byPath[hit.relativePath] = hit
            }
        }
        return byPath.values
            .sorted { lhs, rhs in
                if lhs.score == rhs.score { return lhs.relativePath < rhs.relativePath }
                return lhs.score < rhs.score
            }
            .prefix(max(0, limit))
            .map { $0 }
    }

    private static func backfillEmbeddings(
        root: URL,
        scanner: FileSystemScanner,
        previewLoader: SafeFilePreviewLoader,
        controller: InferenceController,
        store: any WorkspaceIndexStore,
        budget: ResourceBudget,
        metricsRecorder: MetricsRecorder
    ) async {
        do {
            let stream = try await scanner.scan(root: root)
            var batch: [(path: String, text: String)] = []
            var processed = 0
            for await entry in stream where !entry.isDirectory {
                guard !Task.isCancelled else { return }
                guard processed < budget.fileTreePathLimit else { break }
                guard let preview = try? await previewLoader.preview(root: root, relativePath: entry.relativePath),
                      preview.kind == .text,
                      !preview.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    continue
                }
                let text = String(preview.text.prefix(max(budget.maxSnippetCharacters * 2, budget.maxSnippetCharacters)))
                batch.append((entry.relativePath, "search_document: \(entry.relativePath)\n\(text)"))
                processed += 1
                if batch.count >= 8 {
                    guard !Task.isCancelled else { return }
                    await embedBatch(batch, controller: controller, store: store, metricsRecorder: metricsRecorder)
                    batch.removeAll(keepingCapacity: true)
                }
            }
            if !batch.isEmpty, !Task.isCancelled {
                await embedBatch(batch, controller: controller, store: store, metricsRecorder: metricsRecorder)
            }
        } catch {
            await metricsRecorder.record(.init(
                kind: .failureCount,
                unit: .count,
                value: 1,
                metadata: ["source": "embeddingBackfill"]))
        }
    }

    private static func embedBatch(
        _ batch: [(path: String, text: String)],
        controller: InferenceController,
        store: any WorkspaceIndexStore,
        metricsRecorder: MetricsRecorder
    ) async {
        guard !Task.isCancelled else { return }
        do {
            let vectors = try await controller.embed(texts: batch.map(\.text))
            guard !Task.isCancelled else { return }
            for (item, vector) in zip(batch, vectors) {
                guard !Task.isCancelled else { return }
                try await store.upsertEmbedding(path: item.path, vector: vector)
                await metricsRecorder.record(.init(
                    kind: .contextCharacters,
                    unit: .count,
                    value: Double(item.text.count),
                    metadata: ["source": "embeddingBackfill"]))
            }
        } catch {
            await metricsRecorder.record(.init(
                kind: .failureCount,
                unit: .count,
                value: 1,
                metadata: ["source": "embeddingBackfill"]))
        }
    }
}

private actor LazyInferenceController {
    private let gpuCacheLimitBytes: Int?
    private let resourceProfile: ResourceProfile
    private let memoryCoordinator: MemoryBudgetCoordinator
    private var controller: InferenceController?

    init(
        gpuCacheLimitBytes: Int? = nil,
        resourceProfile: ResourceProfile,
        memoryCoordinator: MemoryBudgetCoordinator
    ) {
        self.gpuCacheLimitBytes = gpuCacheLimitBytes
        self.resourceProfile = resourceProfile
        self.memoryCoordinator = memoryCoordinator
    }

    func resolve() async -> InferenceController {
        if let controller {
            return controller
        }
        let newController = await EngineBootstrap.liveController(
            gpuCacheLimitBytes: gpuCacheLimitBytes,
            resourceProfile: resourceProfile,
            memoryCoordinator: memoryCoordinator)
        controller = newController
        return newController
    }

    func loadedRoles() async -> Set<ModelRole> {
        guard let controller else { return [] }
        return await controller.loadedRoles
    }

    func embed(texts: [String]) async throws -> [EmbeddingVector] {
        guard let controller else { return [] }
        return try await controller.embed(texts: texts)
    }

    func unloadAll() async {
        guard let controller else { return }
        await controller.unload(role: .orchestrator)
        await controller.unload(role: .utility)
        await controller.unload(role: .embeddings)
    }

    func memoryPolicyState() async -> MemoryPolicyState {
        guard let controller else {
            return await memoryCoordinator.currentState()
        }
        return await controller.memoryPolicyState()
    }
}
