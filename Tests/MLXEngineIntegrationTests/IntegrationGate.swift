// Opt-in gate for the real-MLX integration suite.
//
// Enabled ONLY when compiled with `-D RUN_MLX_INTEGRATION`, which is passed
// exclusively by `scripts/test-integration.sh` (an `xcodebuild test` run).
//
// Why a compile flag rather than an env var: real MLX inference requires building
// with xcodebuild — `swift build`/`swift test` does not compile mlx-swift's Metal
// library ("PrepareMetalShaders"), so under a plain `swift test` MLX would abort
// with "Failed to load the default metallib". Gating on the flag guarantees these
// tests run only under the xcodebuild path that actually builds the metallib, and
// always skip under `swift test`.
enum IntegrationGate {
    static var isEnabled: Bool {
        #if RUN_MLX_INTEGRATION
        true
        #else
        false
        #endif
    }
}

enum ModelFixtures {
    /// Two *distinct* tiny 4-bit models (~695 MB + ~278 MB) — small enough to run
    /// two concurrently on an 8 GB machine, so Success Criterion §21.1 ("load two
    /// local quantized models concurrently") is exercised with genuinely different
    /// models. NOT production models.
    static let tinyOrchestrator = "mlx-community/Llama-3.2-1B-Instruct-4bit"
    static let tinyUtility = "mlx-community/Qwen2.5-0.5B-Instruct-4bit"
}
