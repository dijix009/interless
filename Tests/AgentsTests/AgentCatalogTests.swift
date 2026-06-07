import Foundation
import Testing
import Agents
import Core
import Shared

struct AgentCatalogTests {
    @Test func catalogMergesConfigAndRoutesExplicitAgents() {
        let denyWrites = PolicyStatement(effect: .deny, action: "tool.write", resource: "*")
        let catalog = AgentCatalog(configured: [
            "general": AgentDefinition(
                id: "",
                model: "local-general",
                system: "Custom general prompt.",
                permissions: [denyWrites]),
            "disabled": AgentDefinition(id: "disabled", disabled: true),
        ])

        #expect(catalog.definition(id: "general")?.id == "general")
        #expect(catalog.definition(id: "disabled") == nil)
        #expect(catalog.systemPrompt(agentID: "general", fallback: "fallback") == "Custom general prompt.")
        #expect(catalog.modelID(agentID: "general") == "local-general")
        #expect(catalog.permissionOverlay(agentID: "general") == [denyWrites])
        #expect(catalog.primaryAgents.map(\.id).contains("build"))
        #expect(catalog.subagents.map(\.id).contains("title"))

        let router = AgentRouter(catalog: catalog)
        #expect(router.route(for: AgentTask(prompt: "x", agentID: "plan")) == .orchestrator)
        #expect(router.route(for: AgentTask(prompt: "x", agentID: "general")) == .utility)
    }

    @Test func subagentDispatcherRequiresSubagentDefinition() async throws {
        let catalog = AgentCatalog(configured: [
            "worker": AgentDefinition(id: "worker", mode: .subagent),
        ])
        let agent = RecordingAgent()
        let dispatcher = SubagentDispatcher(catalog: catalog, agent: agent)

        let result = try await dispatcher.dispatch(prompt: "Summarize", agentID: "worker", parentTaskID: UUID())

        #expect(result.text == "worker: Summarize")
        #expect(await agent.tasks.map(\.agentID) == ["worker"])
        await #expect(throws: AgentCatalogError.notSubagent("general")) {
            _ = try await dispatcher.dispatch(prompt: "Nope", agentID: "general")
        }
    }

    @Test func modelAgentUsesCatalogSystemPrompt() async throws {
        let catalog = AgentCatalog(configured: [
            "general": AgentDefinition(id: "general", system: "Catalog prompt."),
        ])
        let model = RecordingModelClient()
        let agent = UtilityAgent(model: model, agentCatalog: catalog, defaultAgentID: "general")

        _ = try await agent.execute(task: AgentTask(prompt: "hello"))
        let request = try #require(await model.requests.first)

        guard case let .messages(messages) = request.input else {
            Issue.record("expected chat messages")
            return
        }
        #expect(messages.first?.role == .system)
        #expect(messages.first?.content == "Catalog prompt.")
    }
}

private actor RecordingAgent: Agent {
    private(set) var tasks: [AgentTask] = []

    func execute(task: AgentTask) async throws -> AgentResult {
        tasks.append(task)
        return AgentResult(taskID: task.id, route: .utility, text: "\(task.agentID ?? "none"): \(task.prompt)")
    }
}

private actor RecordingModelClient: AgentModelClient {
    private(set) var requests: [GenerationRequest] = []

    func stream(request: GenerationRequest) async -> AsyncThrowingStream<TokenChunk, Error> {
        requests.append(request)
        return AsyncThrowingStream { continuation in
            continuation.yield(TokenChunk(text: "ok", index: 0, isFinal: false))
            continuation.yield(TokenChunk(text: "", index: 1, isFinal: true))
            continuation.finish()
        }
    }
}
