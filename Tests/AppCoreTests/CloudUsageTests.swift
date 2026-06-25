import Testing
import Shared
import UI
@testable import AppCore

struct CloudUsageTests {

    @Test func localRolesNeverRequireConsent() throws {
        // Bare / Hugging Face ids are local — allowed regardless of consent.
        try LiveAppDependencyFactory.validateCloudUsage(
            orchestrator: "mlx-community/orchestrator",
            utility: "mlx-community/utility",
            embeddings: "nomic-embed",
            allowCloudModels: false)
    }

    @Test func cloudRolesAllowedOnlyWithConsent() throws {
        // With consent, cloud orchestrator + cloud sub-agent are fine.
        try LiveAppDependencyFactory.validateCloudUsage(
            orchestrator: "anthropic/claude-opus-4-8",
            utility: "anthropic/claude-haiku-4-5",
            embeddings: "nomic-embed",
            allowCloudModels: true)
    }

    @Test func cloudRoleWithoutConsentThrows() {
        #expect(throws: (any Error).self) {
            try LiveAppDependencyFactory.validateCloudUsage(
                orchestrator: "anthropic/claude-opus-4-8",
                utility: "mlx-community/utility",
                embeddings: "nomic-embed",
                allowCloudModels: false)
        }
    }

    @Test func cloudEmbeddingsUnsupportedEvenWithConsent() {
        #expect(throws: (any Error).self) {
            try LiveAppDependencyFactory.validateCloudUsage(
                orchestrator: "mlx-community/orchestrator",
                utility: "mlx-community/utility",
                embeddings: "anthropic/embed",
                allowCloudModels: true)
        }
    }

    @Test func singleAgentModeIsCloudAware() {
        let small = ModelSettingsViewState(resourceProfile: .smallRAM)
        let large = ModelSettingsViewState(resourceProfile: .largeRAM)
        // Small RAM + both local → collapse to a single agent (two local models won't fit).
        #expect(LiveAppDependencyFactory.effectiveSingleAgentMode(
            settings: small, orchestratorID: "mlx-community/a", utilityID: "mlx-community/b"))
        // Small RAM but a cloud role costs no local RAM → allow mixing (multi-agent).
        #expect(!LiveAppDependencyFactory.effectiveSingleAgentMode(
            settings: small, orchestratorID: "openai/gpt-5.5", utilityID: "mlx-community/b"))
        #expect(!LiveAppDependencyFactory.effectiveSingleAgentMode(
            settings: small, orchestratorID: "mlx-community/a", utilityID: "anthropic/claude-haiku-4-5"))
        // Large RAM → always multi-agent.
        #expect(!LiveAppDependencyFactory.effectiveSingleAgentMode(
            settings: large, orchestratorID: "mlx-community/a", utilityID: "mlx-community/b"))
    }

    @Test func nativeToolAdvertisementIsCloudAware() {
        // Cloud roles get native tools regardless of toolCallFormat.
        #expect(LiveAppDependencyFactory.advertisesNativeTools(modelID: "anthropic/claude-opus-4-8", toolCallFormat: nil))
        #expect(LiveAppDependencyFactory.advertisesNativeTools(modelID: "openai/gpt-4o", toolCallFormat: nil))
        // Local roles still need a configured tool-call format.
        #expect(!LiveAppDependencyFactory.advertisesNativeTools(modelID: "mlx-community/x", toolCallFormat: nil))
        #expect(LiveAppDependencyFactory.advertisesNativeTools(modelID: "mlx-community/x", toolCallFormat: .json))
    }
}
