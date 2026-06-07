import Foundation
import Core
import InterlessSecurity
import Persistence
import UI
import Workspace

public struct ConfigCoordinatorSnapshot: Sendable, Equatable {
    public var loaded: LoadedInterlessConfig
    public var presentation: ConfigStatusViewState

    public init(loaded: LoadedInterlessConfig, presentation: ConfigStatusViewState) {
        self.loaded = loaded
        self.presentation = presentation
    }
}

public actor ConfigCoordinator {
    private let configStore: (any ConfigStore)?
    private let secretStore: any SecretStore

    public init(
        configStore: (any ConfigStore)? = nil,
        secretStore: any SecretStore = KeychainSecretStore()
    ) {
        self.configStore = configStore
        self.secretStore = secretStore
    }

    public func load(workspaceRoot: URL?) async -> ConfigCoordinatorSnapshot {
        let loaded = InterlessConfigLoader.load(workspaceRoot: workspaceRoot)
        if let configStore {
            try? await configStore.save(loaded, workspacePath: workspaceRoot?.path)
        }
        let presentation = ConfigStatusViewState(
            loadedAt: loaded.loadedAt,
            loadedSourceCount: loaded.sources.filter(\.exists).count,
            candidateSourceCount: loaded.sources.count,
            diagnostics: loaded.diagnostics.map(ConfigDiagnosticViewState.init),
            policyCount: loaded.effective.policyStatements.count,
            agentCount: loaded.effective.agents.values.filter { !$0.disabled }.count,
            providerCount: loaded.effective.providers.values.filter { !$0.disabled }.count,
            formatterCount: Self.enabledCommandCount(loaded.effective.formatter),
            languageServerCount: Self.enabledCommandCount(loaded.effective.lsp),
            mcpServerCount: loaded.effective.mcp?.servers.values.filter { !$0.disabled }.count ?? 0,
            extensionCount: loaded.effective.nativeExtensions.filter(\.enabled).count + loaded.effective.plugins.filter { !$0.disabled }.count)
        return ConfigCoordinatorSnapshot(loaded: loaded, presentation: presentation)
    }

    public func watch(
        workspaceRoot: URL,
        eventStream: any WorkspaceEventStream = FSEventsWorkspaceEventStream(),
        debounce: Duration = .milliseconds(250)
    ) -> AsyncStream<ConfigCoordinatorSnapshot> {
        let watchedPaths = Set(InterlessConfigLoader.workspaceFileNames.map {
            workspaceRoot.appendingPathComponent($0).standardizedFileURL.path
        })
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task {
                for await events in eventStream.events(root: workspaceRoot) {
                    guard Self.eventsAffectConfig(events, root: workspaceRoot, watchedPaths: watchedPaths) else {
                        continue
                    }
                    try? await Task.sleep(for: debounce)
                    guard !Task.isCancelled else { break }
                    continuation.yield(await self.load(workspaceRoot: workspaceRoot))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func resolveInterpolations(in text: String) async -> String {
        var output = text
        output = resolveEnvironmentInterpolations(in: output)
        output = await resolveKeychainInterpolations(in: output)
        return output
    }

    private func resolveEnvironmentInterpolations(in text: String) -> String {
        replaceTokens(in: text, prefix: "env") { key in
            ProcessInfo.processInfo.environment[key] ?? ""
        }
    }

    private func resolveKeychainInterpolations(in text: String) async -> String {
        var result = text
        let matches = tokenMatches(in: text, prefix: "keychain")
        for match in matches.reversed() {
            let value = (try? await secretStore.read(service: InterlessSecrets.service, account: match.key)) ?? nil
            result.replaceSubrange(match.range, with: value ?? "")
        }
        return result
    }

    private func replaceTokens(in text: String, prefix: String, resolver: (String) -> String) -> String {
        var result = text
        for match in tokenMatches(in: text, prefix: prefix).reversed() {
            result.replaceSubrange(match.range, with: resolver(match.key))
        }
        return result
    }

    private func tokenMatches(in text: String, prefix: String) -> [(range: Range<String.Index>, key: String)] {
        let pattern = #"\{\#(prefix):([^}]+)\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsRange = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: nsRange).compactMap { match in
            guard match.numberOfRanges == 2,
                  let range = Range(match.range(at: 0), in: text),
                  let keyRange = Range(match.range(at: 1), in: text) else {
                return nil
            }
            return (range, String(text[keyRange]))
        }
    }

    private static func eventsAffectConfig(
        _ events: [WorkspaceEvent],
        root: URL,
        watchedPaths: Set<String>
    ) -> Bool {
        events.contains { event in
            guard let relativePath = event.relativePath else { return false }
            let path = root.appendingPathComponent(relativePath).standardizedFileURL.path
            return watchedPaths.contains(path)
        }
    }

    private static func enabledCommandCount(_ config: BooleanOrMap<ConfiguredCommand>?) -> Int {
        guard case let .entries(entries) = config else { return 0 }
        return entries.values.filter { !$0.disabled && !$0.command.isEmpty }.count
    }
}

private extension ConfigDiagnosticViewState {
    init(_ diagnostic: ConfigDiagnostic) {
        self.init(
            severity: ConfigDiagnosticViewSeverity(rawValue: diagnostic.severity.rawValue) ?? .info,
            message: diagnostic.message,
            sourcePath: diagnostic.sourcePath)
    }
}
