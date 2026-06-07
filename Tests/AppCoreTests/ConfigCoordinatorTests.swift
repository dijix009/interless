import Foundation
import Testing
import AppCore
import Core
import Shared
import Tooling
import UI
import Workspace

@MainActor
struct ConfigCoordinatorTests {
    @Test func coordinatorLoadsWorkspaceConfigStatus() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try """
        {
          "model": "configured-model",
          "experimental": {
            "policies": [
              { "effect": "deny", "action": "provider.use", "resource": "*" }
            ]
          }
        }
        """.write(to: root.appendingPathComponent("interless.json"), atomically: true, encoding: .utf8)
        let coordinator = ConfigCoordinator()

        let snapshot = await coordinator.load(workspaceRoot: root)

        #expect(snapshot.presentation.loadedSourceCount == 1)
        #expect(snapshot.presentation.policyCount == 1)
        #expect(snapshot.loaded.effective.model == "configured-model")
    }

    @Test func coordinatorWatchesWorkspaceConfigChanges() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let stream = FakeConfigEventStream()
        let coordinator = ConfigCoordinator()
        var snapshots = await coordinator.watch(
            workspaceRoot: root,
            eventStream: stream,
            debounce: .milliseconds(1)).makeAsyncIterator()

        try """
        { "model": "reloaded-model" }
        """.write(to: root.appendingPathComponent("interless.json"), atomically: true, encoding: .utf8)
        stream.emit([WorkspaceEvent(relativePath: "interless.json", kind: .modified)])

        let snapshot = try #require(await snapshots.next())
        #expect(snapshot.loaded.effective.model == "reloaded-model")
        stream.finish()
    }

    @Test func runtimeConfigMapperAppliesModelsPoliciesAndNativeSettingsSurfaces() {
        let config = InterlessConfig(
            model: "fallback-model",
            agents: [
                "build": AgentDefinition(id: "build", model: "builder-model", steps: 7),
                "general": AgentDefinition(id: "general", model: "general-model"),
            ],
            permissions: [
                PolicyStatement(effect: .allow, action: "tool.write", resource: "*"),
                PolicyStatement(effect: .allow, action: "tool.network", resource: "*"),
            ],
            mcp: MCPConfig(timeout: 12, servers: [
                "local-docs": MCPServerConfig(type: .local, command: ["interless-mcp"]),
                "remote-docs": MCPServerConfig(type: .remote, url: "https://mcp.example.invalid"),
            ]))
        var configured = config
        configured.formatter = .entries([
            "swift-format": ConfiguredCommand(command: ["swift-format"], extensions: ["swift"]),
        ])
        configured.lsp = .entries([
            "sourcekit": ConfiguredCommand(command: ["sourcekit-lsp"], extensions: ["swift"]),
        ])
        configured.toolOutput = ToolOutputConfig(maxBytes: 2048)

        let application = RuntimeConfigMapper.resolve(
            config: configured,
            settings: ModelSettingsViewState(resourceProfile: .balanced),
            resourceBudget: ResourceBudget.resolved(for: .balanced))

        #expect(application.settings.orchestratorModelID == "builder-model")
        #expect(application.settings.utilityModelID == "general-model")
        #expect(application.settings.maxToolIterations == 7)
        #expect(application.toolPolicy.allowsWrites)
        #expect(application.toolPolicy.networkEnabled)
        #expect(application.toolPolicy.maxOutputBytes == 2048)
        #expect(application.formatterRegistry.command(for: "Sources/App.swift") == ["swift-format"])
        #expect(application.languageServers.map { $0.id } == ["sourcekit"])
        #expect(application.mcpSettings.activeCount == 2)
    }

    @Test func runtimeConfigMapperPreservesAskPolicyEffects() {
        let config = InterlessConfig(
            permissions: [
                PolicyStatement(effect: .ask, action: "tool.write", resource: "*"),
                PolicyStatement(effect: .ask, action: "tool.network", resource: "*"),
            ])

        let application = RuntimeConfigMapper.resolve(
            config: config,
            settings: ModelSettingsViewState(),
            resourceBudget: ResourceBudget.resolved(for: .balanced))

        #expect(application.settings.allowWrites)
        #expect(application.settings.allowNetworkTools)
        #expect(!application.toolPolicy.allowsWrites)
        #expect(!application.toolPolicy.networkEnabled)
        #expect(application.toolPolicy.writePermission == .ask)
        #expect(application.toolPolicy.networkPermission == .ask)
    }
}

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("interless-appcore-config-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private final class FakeConfigEventStream: WorkspaceEventStream, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<[WorkspaceEvent]>.Continuation?

    func events(root: URL) -> AsyncStream<[WorkspaceEvent]> {
        AsyncStream { continuation in
            lock.withLock {
                self.continuation = continuation
            }
        }
    }

    func emit(_ events: [WorkspaceEvent]) {
        lock.withLock { continuation }?.yield(events)
    }

    func finish() {
        lock.withLock { continuation }?.finish()
    }
}
