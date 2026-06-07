import Foundation
import Testing
import AgentCLI
import Agents
import Shared

struct AgentCLITests {
    @Test func parsesPromptKindAndDefaultsToFakeWithoutModel() throws {
        let options = try AgentCLIOptions.parse([
            "--prompt", "summarize this",
            "--kind", "summarize",
        ])

        #expect(options.prompt == "summarize this")
        #expect(options.kind == .summarize)
        #expect(options.fake)
    }

    @Test func parsesTrailingPromptAndRealModelFlags() throws {
        let options = try AgentCLIOptions.parse([
            "--model", "org/model-4bit",
            "--quantization", "q4",
            "--tool-call-format", "llama3",
            "hello", "world",
        ])

        #expect(options.prompt == "hello world")
        #expect(!options.fake)
        #expect(options.sharedModelID == "org/model-4bit")
        #expect(options.quantization == .q4)
        #expect(options.toolCallFormat == .llama3)
    }

    @Test func parsesAllowWritesAndMaxIterations() throws {
        let options = try AgentCLIOptions.parse([
            "--fake",
            "--allow-writes",
            "--allow-network-tools",
            "--max-tool-iterations", "2",
            "--prompt", "write",
        ])

        #expect(options.fake)
        #expect(options.allowWrites)
        #expect(options.allowNetworkTools)
        #expect(options.maxToolIterations == 2)
    }

    @Test func parsesOptionalEmbeddingModelWithoutForcingRealMode() throws {
        let options = try AgentCLIOptions.parse([
            "--embedding-model", "nomic-ai/nomic-embed-text-v1.5",
            "--prompt", "hello",
        ])

        #expect(options.fake)
        #expect(options.embeddingsModelID == "nomic-ai/nomic-embed-text-v1.5")
    }

    @Test func fakeExecutionProducesStableEventOutput() async throws {
        let temp = try TempCLIWorkspace()
        let options = try AgentCLIOptions.parse([
            "--workspace", temp.url.path,
            "--prompt", "hello",
            "--kind", "simpleQuestion",
        ])

        let output = try await AgentCLI.execute(options: options)

        #expect(output.contains("route utility"))
        #expect(output.contains("iteration 1"))
        #expect(output.contains("token fake response"))
        #expect(output.contains("completed fake response"))
    }
}

private final class TempCLIWorkspace {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("if-cli-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
