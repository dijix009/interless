import Testing
import UI

struct ConfigStatusViewTests {
    @Test func configStatusSummarizesLoadedCapabilitiesAndDiagnostics() {
        let state = ConfigStatusViewState(
            loadedSourceCount: 2,
            candidateSourceCount: 5,
            diagnostics: [
                ConfigDiagnosticViewState(severity: .warning, message: "Remote MCP requires trust"),
                ConfigDiagnosticViewState(severity: .error, message: "Unsupported plugin"),
            ],
            policyCount: 3,
            agentCount: 1,
            providerCount: 2,
            formatterCount: 1,
            languageServerCount: 1,
            mcpServerCount: 1,
            extensionCount: 4)

        #expect(state.hasLoadedConfig)
        #expect(state.warningCount == 1)
        #expect(state.errorCount == 1)
        #expect(state.summary.contains("2/5 files"))
        #expect(state.summary.contains("3 policies"))
        #expect(state.summary.contains("1 formatters"))
        #expect(state.summary.contains("1 LSP servers"))
        #expect(state.summary.contains("1 errors"))
    }

    @Test func mcpSettingsPresentationCountsTrustedServers() {
        let state = MCPSettingsViewState(trustedNetworkEnabled: false, servers: [
            MCPServerViewState(id: "local", name: "local", transport: .local, command: ["mcp"], isTrusted: true),
            MCPServerViewState(id: "remote", name: "remote", transport: .remote, url: "https://example.invalid", isTrusted: false),
            MCPServerViewState(id: "disabled", name: "disabled", transport: .local, isEnabled: false, isTrusted: true),
        ])

        #expect(state.enabledCount == 2)
        #expect(state.activeCount == 1)
        #expect(state.untrustedRemoteCount == 1)
    }
}
