import Testing
import Workspace

struct FormatterAndLSPTests {
    @Test func formatterRegistryResolvesEnabledFormatterByExtension() {
        let registry = FormatterRegistry(formatters: [
            FormatterDefinition(id: "swift-format", extensions: ["swift"], command: ["swift-format"]),
            FormatterDefinition(id: "disabled-json", extensions: ["json"], command: ["jq"], isEnabled: false),
        ])

        #expect(registry.command(for: "Sources/App.swift") == ["swift-format"])
        #expect(registry.command(for: "package.json") == nil)
        #expect(registry.allowedFormatterIDs() == ["swift-format"])
    }

    @Test func languageServerCoordinatorStoresDiagnosticsAndFailures() async {
        let coordinator = LanguageServerCoordinator(servers: [
            LanguageServerDefinition(id: "sourcekit", extensions: ["swift"], command: ["sourcekit-lsp"]),
            LanguageServerDefinition(id: "disabled", extensions: ["json"], command: ["json-lsp"], isEnabled: false),
        ])
        let diagnostic = LanguageDiagnostic(
            path: "Sources/App.swift",
            line: 3,
            column: 5,
            severity: .warning,
            message: "Unused value",
            source: "sourcekit")

        #expect(await coordinator.server(for: "Sources/App.swift")?.id == "sourcekit")
        #expect(await coordinator.server(for: "package.json") == nil)
        await coordinator.replaceDiagnostics([diagnostic], for: "Sources/App.swift")
        await coordinator.recordFailure(serverID: "sourcekit", message: "not running")

        #expect(await coordinator.diagnostics(for: "Sources/App.swift") == [diagnostic])
        #expect(await coordinator.failure(serverID: "sourcekit") == "not running")
    }
}
