import Testing
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
}
