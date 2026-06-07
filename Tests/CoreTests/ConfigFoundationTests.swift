import Foundation
import Testing
import Core

struct ConfigFoundationTests {
    @Test func policyEvaluatorUsesLastMatchingStatement() {
        let evaluator = PolicyEvaluator(statements: [
            PolicyStatement(effect: .deny, action: "provider.use", resource: "*"),
            PolicyStatement(effect: .allow, action: "provider.use", resource: "anthropic"),
            PolicyStatement(effect: .deny, action: "provider.use", resource: "anthropic-beta"),
        ])

        #expect(evaluator.evaluate(action: "provider.use", resource: "openai").effect == .deny)
        #expect(evaluator.evaluate(action: "provider.use", resource: "anthropic").effect == .allow)
        #expect(evaluator.evaluate(action: "provider.use", resource: "anthropic-beta").effect == .deny)
        #expect(evaluator.evaluate(action: "tool.read", resource: "README.md").effect == .allow)
    }

    @Test func configLoaderMergesSourcesAndRejectsJavaScriptPlugins() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let global = root.appendingPathComponent("global.json")
        let workspace = root.appendingPathComponent("workspace.json")
        try """
        {
          "model": "global-model",
          "instructions": ["GLOBAL.md"],
          "experimental": {
            "policies": [
              { "effect": "deny", "action": "provider.use", "resource": "*" }
            ]
          }
        }
        """.write(to: global, atomically: true, encoding: .utf8)
        try """
        {
          "model": "workspace-model",
          "instructions": ["AGENTS.md"],
          "plugins": [
            { "package": "legacy-plugin.js" }
          ],
          "agents": {
            "plan": { "system": "Read-only planning.", "mode": "primary" }
          },
          "experimental": {
            "policies": [
              { "effect": "allow", "action": "provider.use", "resource": "anthropic" }
            ]
          }
        }
        """.write(to: workspace, atomically: true, encoding: .utf8)

        let loaded = InterlessConfigLoader.load(urls: [
            (global, .global),
            (workspace, .workspace),
        ])

        #expect(loaded.effective.model == "workspace-model")
        #expect(loaded.effective.instructions == ["GLOBAL.md", "AGENTS.md"])
        #expect(loaded.effective.agents["plan"]?.id == "plan")
        #expect(loaded.effective.policyStatements.map(\.effect) == [.deny, .allow])
        #expect(loaded.diagnostics.contains { $0.severity == .error && $0.message.contains("JavaScript") })
    }

    @Test func extensionRegistryPublishesRegistrationAndRemoval() async {
        let registry = ExtensionRegistry()
        var events = await registry.stream().makeAsyncIterator()
        let record = NativeExtensionRecord(id: "local-docs", kind: .reference, name: "Docs", source: "/tmp/docs")

        await registry.register(record)
        #expect(await events.next() == .registered(record))
        #expect(await registry.all(kind: .reference, enabledOnly: true) == [record])

        await registry.remove(id: record.id)
        #expect(await events.next() == .removed(record.id))
        #expect(await registry.all().isEmpty)
    }
}

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("interless-config-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
