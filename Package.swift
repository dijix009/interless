// swift-tools-version: 6.0
import PackageDescription

// Interless — native Apple Silicon agent workspace.
// Phase 1 scope (no UI): the Shared value types, Core memory policy, and the
// MLXEngine inference runtime. Target directories map onto the spec's module
// tree (ARCHITECTURE.md §5) via `path:`, so there is a single module tree.
let package = Package(
    name: "Interless",
    platforms: [
        .macOS(.v15) // ARCHITECTURE.md §2 (MLX itself requires only macOS 14).
    ],
    products: [
        .library(name: "Shared", targets: ["Shared"]),
        .library(name: "Core", targets: ["Core"]),
        .library(name: "MLXEngine", targets: ["MLXEngine"]),
        .library(name: "Persistence", targets: ["Persistence"]),
        .library(name: "Workspace", targets: ["Workspace"]),
        .library(name: "Tooling", targets: ["Tooling"]),
        .library(name: "InterlessSecurity", targets: ["InterlessSecurity"]),
        .library(name: "CloudInference", targets: ["CloudInference"]),
        .library(name: "Agents", targets: ["Agents"]),
        .library(name: "AgentCLI", targets: ["AgentCLI"]),
        .library(name: "UI", targets: ["UI"]),
        .library(name: "AppCore", targets: ["AppCore"]),
        .executable(name: "Interless", targets: ["InterlessApp"]),
        .executable(name: "interless-agent", targets: ["InterlessAgentCLI"]),
    ],
    dependencies: [
        // Reusable MLX language-model libraries (moved out of mlx-swift-examples).
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", .upToNextMajor(from: "3.31.3")),
        // Core MLX array/NN framework (Metal kernels live here).
        .package(url: "https://github.com/ml-explore/mlx-swift", .upToNextMinor(from: "0.31.4")),
        // Consumer-supplied Hugging Face Hub client + tokenizers that the
        // MLXHuggingFace macros bridge to (mlx-swift-lm deliberately does not
        // depend on these — see its README "Method 2: Macros").
        .package(url: "https://github.com/huggingface/swift-huggingface", .upToNextMajor(from: "0.9.0")),
        .package(url: "https://github.com/huggingface/swift-transformers", .upToNextMajor(from: "1.3.0")),
        // SQLite toolkit + FTS5 full-text search for the workspace index (Persistence only).
        .package(url: "https://github.com/groue/GRDB.swift", .upToNextMajor(from: "7.11.0")),
        // Swift-first tree-sitter extraction for Phase 2 structured indexing.
        .package(url: "https://github.com/tree-sitter/swift-tree-sitter", .upToNextMajor(from: "0.10.0")),
        // `main` omits generated C parser sources; pin the generated-files tag.
        .package(url: "https://github.com/alex-pinkus/tree-sitter-swift", revision: "31d17fe7e818a2048c808b5c6fdc2dc792f4f5b5"),
    ],
    targets: [
        // MARK: - Shared (value types, no dependencies)
        .target(
            name: "Shared",
            path: "Shared",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // MARK: - Core (cross-cutting infrastructure; depends only on Shared)
        .target(
            name: "Core",
            dependencies: ["Shared"],
            path: "Core",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // MARK: - MLXEngine (Phase 1 deliverable; the only place MLX is imported)
        .target(
            name: "MLXEngine",
            dependencies: [
                "Shared",
                "Core",
                "CloudInference",
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXEmbedders", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ],
            path: "MLXEngine",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),

        // MARK: - Persistence (Phase 2; the only target importing GRDB)
        .target(
            name: "Persistence",
            dependencies: [
                "Shared",
                "Core",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Persistence",
            exclude: ["README.md"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // MARK: - Workspace (Phase 2; scanner/ignore/git; talks to the Core store seam.
        // CryptoKit auto-links from the SDK on import — no product dependency.)
        .target(
            name: "Workspace",
            dependencies: [
                "Shared",
                "Core",
                .product(name: "SwiftTreeSitter", package: "swift-tree-sitter"),
                .product(name: "TreeSitterSwift", package: "tree-sitter-swift"),
            ],
            path: "Workspace",
            exclude: ["README.md"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // MARK: - Tooling (Phase 3; restricted workspace-scoped tool execution)
        .target(
            name: "Tooling",
            dependencies: ["Shared"],
            path: "Tooling",
            exclude: ["README.md"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "InterlessSecurity",
            path: "Security",
            exclude: ["README.md"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // MARK: - CloudInference (optional hosted-model backends, e.g. Anthropic;
        // MLX-free — depends only on Shared value types + Keychain secrets).
        .target(
            name: "CloudInference",
            dependencies: ["Shared", "InterlessSecurity"],
            path: "CloudInference",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // MARK: - Agents (Phase 3; orchestration/runtime; no UI/Persistence imports)
        .target(
            name: "Agents",
            dependencies: ["Shared", "Core", "Tooling", "MLXEngine"],
            path: "Agents",
            exclude: ["README.md"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "AgentCLI",
            dependencies: ["Agents", "Tooling", "MLXEngine", "Shared"],
            path: "AgentCLI",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "UI",
            dependencies: ["Shared"],
            path: "UI",
            exclude: ["README.md"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "AppCore",
            dependencies: [
                "UI", "Shared", "Core", "Agents", "MLXEngine", "InterlessSecurity",
                "Persistence", "Workspace", "Tooling", "CloudInference",
            ],
            path: "AppCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "InterlessApp",
            dependencies: ["AppCore", "UI"],
            path: "App",
            exclude: ["README.md"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "InterlessAgentCLI",
            dependencies: ["AgentCLI"],
            path: "InterlessAgentCLI",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),

        // MARK: - Tests
        .testTarget(
            name: "SharedTests",
            dependencies: ["Shared"],
            path: "Tests/SharedTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "CoreTests",
            dependencies: ["Core", "Shared"],
            path: "Tests/CoreTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Fast, model-free unit tests (default `swift test`).
        .testTarget(
            name: "MLXEngineTests",
            dependencies: ["MLXEngine", "Core", "Shared", "CloudInference"],
            path: "Tests/MLXEngineTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Gated real-MLX integration tests. Run through scripts/test-integration.sh
        // so Xcode builds MLX's Metal shader library and defines RUN_MLX_INTEGRATION.
        .testTarget(
            name: "MLXEngineIntegrationTests",
            dependencies: ["MLXEngine", "Shared"],
            path: "Tests/MLXEngineIntegrationTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Fast Persistence tests: in-memory GRDB (real SQL + FTS5), no files.
        .testTarget(
            name: "PersistenceTests",
            dependencies: [
                "Persistence", "Core", "Shared",
                .product(name: "GRDB", package: "GRDB.swift"), // raw DB inspection in tests
            ],
            path: "Tests/PersistenceTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Fast Workspace tests: pure ignore rules, temp-dir scanner, Fake-driven
        // coordinator, real `git init` repo. No GPU/network; not gated.
        .testTarget(
            name: "WorkspaceTests",
            dependencies: ["Workspace", "Core", "Shared"],
            path: "Tests/WorkspaceTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // End-to-end wiring (the only test target importing both Workspace and
        // Persistence): real scanner + GRDB store + git over a temp repo.
        .testTarget(
            name: "WorkspaceIntegrationTests",
            dependencies: ["Workspace", "Persistence", "Core", "Shared"],
            path: "Tests/WorkspaceIntegrationTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Fast Tooling tests: temp-dir process/file/git wrappers.
        .testTarget(
            name: "ToolingTests",
            dependencies: ["Tooling", "Shared"],
            path: "Tests/ToolingTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "SecurityTests",
            dependencies: ["InterlessSecurity"],
            path: "Tests/SecurityTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Fast CloudInference tests: fake HTTP transport + canned SSE, no network.
        .testTarget(
            name: "CloudInferenceTests",
            dependencies: ["CloudInference", "Shared"],
            path: "Tests/CloudInferenceTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Fast Agent tests: fake model/search + real restricted tooling.
        .testTarget(
            name: "AgentsTests",
            dependencies: ["Agents", "Tooling", "Shared", "Core"],
            path: "Tests/AgentsTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "AgentCLITests",
            dependencies: ["AgentCLI"],
            path: "Tests/AgentCLITests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "UITests",
            dependencies: ["UI", "Shared"],
            path: "Tests/UITests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "AppCoreTests",
            dependencies: ["AppCore", "UI", "Shared", "Agents", "Workspace"],
            path: "Tests/AppCoreTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
