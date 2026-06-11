import Foundation
import Agents
import Tooling
import MLXEngine
import Shared

public struct AgentCLIOptions: Sendable, Equatable {
    public var workspace: URL
    public var prompt: String
    public var kind: AgentTaskKind
    public var fake: Bool
    public var sharedModelID: String?
    public var orchestratorModelID: String?
    public var utilityModelID: String?
    public var embeddingsModelID: String?
    public var quantization: QuantizationLevel?
    public var toolCallFormat: ModelToolCallFormat?
    public var allowWrites: Bool
    public var allowNetworkTools: Bool
    public var maxToolIterations: Int

    public static func parse(_ arguments: [String], currentDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)) throws -> AgentCLIOptions {
        var workspace = currentDirectory
        var prompt: String?
        var trailing: [String] = []
        var kind: AgentTaskKind = .auto
        var fake = false
        var sharedModelID: String?
        var orchestratorModelID: String?
        var utilityModelID: String?
        var embeddingsModelID: String?
        var quantization: QuantizationLevel?
        var toolCallFormat: ModelToolCallFormat?
        var allowWrites = false
        var allowNetworkTools = false
        var maxToolIterations = AgentLoopPolicy.default.maxToolIterations

        var index = 0
        while index < arguments.count {
            let arg = arguments[index]
            switch arg {
            case "--workspace":
                workspace = URL(fileURLWithPath: try value(after: arg, in: arguments, index: &index))
            case "--prompt":
                prompt = try value(after: arg, in: arguments, index: &index)
            case "--kind":
                let raw = try value(after: arg, in: arguments, index: &index)
                guard let parsed = AgentTaskKind(rawValue: raw) else { throw AgentCLIError.invalidValue("--kind", raw) }
                kind = parsed
            case "--fake":
                fake = true
            case "--model":
                sharedModelID = try value(after: arg, in: arguments, index: &index)
            case "--orchestrator-model":
                orchestratorModelID = try value(after: arg, in: arguments, index: &index)
            case "--utility-model":
                utilityModelID = try value(after: arg, in: arguments, index: &index)
            case "--embedding-model", "--embeddings-model":
                embeddingsModelID = try value(after: arg, in: arguments, index: &index)
            case "--quantization":
                let raw = try value(after: arg, in: arguments, index: &index)
                guard let parsed = parseQuantization(raw) else { throw AgentCLIError.invalidValue("--quantization", raw) }
                quantization = parsed
            case "--tool-call-format":
                let raw = try value(after: arg, in: arguments, index: &index)
                guard let parsed = ModelToolCallFormat(rawValue: raw) else { throw AgentCLIError.invalidValue("--tool-call-format", raw) }
                toolCallFormat = parsed
            case "--allow-writes":
                allowWrites = true
            case "--allow-network-tools":
                allowNetworkTools = true
            case "--max-tool-iterations":
                let raw = try value(after: arg, in: arguments, index: &index)
                guard let parsed = Int(raw), parsed >= 0 else { throw AgentCLIError.invalidValue("--max-tool-iterations", raw) }
                maxToolIterations = parsed
            default:
                trailing.append(arg)
            }
            index += 1
        }

        let resolvedPrompt = prompt ?? trailing.joined(separator: " ")
        guard !resolvedPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentCLIError.missingPrompt
        }
        let hasModel = sharedModelID != nil || orchestratorModelID != nil || utilityModelID != nil
        return AgentCLIOptions(
            workspace: workspace,
            prompt: resolvedPrompt,
            kind: kind,
            fake: fake || !hasModel,
            sharedModelID: sharedModelID,
            orchestratorModelID: orchestratorModelID,
            utilityModelID: utilityModelID,
            embeddingsModelID: embeddingsModelID,
            quantization: quantization,
            toolCallFormat: toolCallFormat,
            allowWrites: allowWrites,
            allowNetworkTools: allowNetworkTools,
            maxToolIterations: maxToolIterations)
    }
}

public enum AgentCLIError: Error, Sendable, Equatable, CustomStringConvertible {
    case missingPrompt
    case missingValue(String)
    case invalidValue(String, String)

    public var description: String {
        switch self {
        case .missingPrompt:
            return "missing prompt; pass --prompt <text> or trailing prompt text"
        case .missingValue(let flag):
            return "missing value for \(flag)"
        case .invalidValue(let flag, let value):
            return "invalid value for \(flag): \(value)"
        }
    }
}

public enum AgentCLI {
    public static func run(arguments: [String]) async -> Int32 {
        do {
            let options = try AgentCLIOptions.parse(arguments)
            let text = try await execute(options: options)
            print(text, terminator: text.hasSuffix("\n") ? "" : "\n")
            return 0
        } catch {
            fputs("error: \(error)\n", stderr)
            return 1
        }
    }

    public static func execute(options: AgentCLIOptions) async throws -> String {
        let policy = ToolExecutionPolicy(
            allowsWrites: options.allowWrites,
            networkEnabled: options.allowNetworkTools)
        let toolLoop = try ToolExecutionLoop(root: options.workspace, policy: policy)
        let registry = WorkspaceToolRegistry(policy: policy)
        let loopPolicy = AgentLoopPolicy(
            maxToolIterations: options.maxToolIterations,
            maxToolCallsPerIteration: AgentLoopPolicy.default.maxToolCallsPerIteration)
        let model = try await makeModelClient(options: options)
        let singleAgentMode = usesSingleAgentMode()
        let utilityAgent = UtilityAgent(
            model: model,
            toolLoop: toolLoop,
            toolRegistry: registry,
            loopPolicy: loopPolicy)
        let orchestratorAgent: any StreamingAgent = singleAgentMode
            ? utilityAgent
            : OrchestratorAgent(
                model: model,
                toolLoop: toolLoop,
                toolRegistry: registry,
                loopPolicy: loopPolicy)
        let orchestrator = AgentOrchestrator(
            orchestrator: orchestratorAgent,
            utility: utilityAgent,
            toolLoop: toolLoop,
            router: AgentRouter(forcedRoute: singleAgentMode ? .utility : nil))
        var lines: [String] = []
        let stream = await orchestrator.run(task: AgentTask(prompt: options.prompt, kind: options.kind))
        for try await event in stream {
            switch event {
            case .routeSelected(let route):
                lines.append("route \(route.rawValue)")
            case .toolIterationStarted(let iteration):
                lines.append("iteration \(iteration)")
            case .toolCallRequested(let call):
                lines.append("tool-call \(call.name)")
            case .toolCallRejected(let call, let reason):
                lines.append("tool-rejected \(call.name) \(reason)")
            case .toolStarted(let request):
                lines.append("tool-start \(request.displayName)")
            case .toolFinished(let result):
                lines.append("tool-finish \(result.request.displayName) exit=\(result.exitCode.map(String.init) ?? "n/a")")
            case .contextBuilt:
                lines.append("context")
            case .contextCompacted(let degraded, let dropped):
                lines.append("context-compacted degraded=\(degraded) dropped=\(dropped)")
            case .token(let chunk):
                if !chunk.text.isEmpty { lines.append("token \(chunk.text)") }
            case .completed(let result):
                lines.append("completed \(result.text)")
            case .failed(let reason):
                lines.append("failed \(reason)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

private func makeModelClient(options: AgentCLIOptions) async throws -> any AgentModelClient {
    if options.fake {
        return FakeCLIModelClient()
    }
    let controller = await EngineBootstrap.liveController()
    if usesSingleAgentMode() {
        if let model = options.sharedModelID ?? options.orchestratorModelID ?? options.utilityModelID {
            try await controller.loadModel(
                id: model,
                role: .utility,
                quantization: options.quantization ?? quantizationAdvertised(by: model) ?? .q4,
                toolCallFormat: options.toolCallFormat)
        }
        return controller
    }
    if let shared = options.sharedModelID {
        try await controller.loadModel(
            id: shared,
            role: .orchestrator,
            quantization: options.quantization ?? .defaultFor(.orchestrator),
            toolCallFormat: options.toolCallFormat)
        try await controller.loadModel(
            id: shared,
            role: .utility,
            quantization: options.quantization ?? .defaultFor(.utility),
            toolCallFormat: options.toolCallFormat)
    }
    if let model = options.orchestratorModelID {
        try await controller.loadModel(
            id: model,
            role: .orchestrator,
            quantization: options.quantization ?? .defaultFor(.orchestrator),
            toolCallFormat: options.toolCallFormat)
    }
    if let model = options.utilityModelID {
        try await controller.loadModel(
            id: model,
            role: .utility,
            quantization: options.quantization ?? .defaultFor(.utility),
            toolCallFormat: options.toolCallFormat)
    }
    if let model = options.embeddingsModelID {
        try await controller.loadModel(
            id: model,
            role: .embeddings,
            quantization: .defaultFor(.embeddings))
    }
    return controller
}

private func usesSingleAgentMode() -> Bool {
    ResourceProfile.resolvedProfile(for: .automatic) == .smallRAM
}

private func quantizationAdvertised(by modelID: String) -> QuantizationLevel? {
    QuantizationLevel.advertisedBits(inRepoID: modelID).flatMap(QuantizationLevel.init(rawValue:))
}

private actor FakeCLIModelClient: AgentModelClient {
    func stream(request: GenerationRequest) async -> AsyncThrowingStream<TokenChunk, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(TokenChunk(text: "fake response", index: 0, isFinal: false))
            continuation.yield(TokenChunk(text: "", index: 1, isFinal: true))
            continuation.finish()
        }
    }
}

private func value(after flag: String, in arguments: [String], index: inout Int) throws -> String {
    let next = index + 1
    guard next < arguments.count else { throw AgentCLIError.missingValue(flag) }
    index = next
    return arguments[next]
}

private func parseQuantization(_ raw: String) -> QuantizationLevel? {
    switch raw.lowercased() {
    case "q4", "4": return .q4
    case "q6", "6": return .q6
    case "q8", "8": return .q8
    default: return nil
    }
}
