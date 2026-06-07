import Foundation
import Testing
import Core
import Persistence

struct ConfigStoreTests {
    @Test func configStorePersistsLatestSnapshot() async throws {
        let store = try PersistenceBootstrap.inMemoryConfigStore()
        let first = LoadedInterlessConfig(
            effective: InterlessConfig(model: "first"),
            sources: [ConfigSource(path: "/tmp/interless.json", scope: .workspace, exists: true)],
            diagnostics: [],
            loadedAt: Date(timeIntervalSince1970: 1))
        let second = LoadedInterlessConfig(
            effective: InterlessConfig(model: "second"),
            sources: [ConfigSource(path: "/tmp/interless.json", scope: .workspace, exists: true)],
            diagnostics: [ConfigDiagnostic(severity: .warning, message: "remote mcp")],
            loadedAt: Date(timeIntervalSince1970: 2))

        try await store.save(first, workspacePath: "/tmp/work")
        try await store.save(second, workspacePath: "/tmp/work")

        let latest = try #require(try await store.latest(workspacePath: "/tmp/work"))
        #expect(latest.workspacePath == "/tmp/work")
        #expect(latest.sourceCount == 1)
        #expect(latest.diagnosticCount == 1)
        #expect(latest.effectiveJSON.contains("second"))
    }
}
