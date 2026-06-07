import Foundation

public actor SubagentDispatcher {
    private let catalog: AgentCatalog
    private let agent: any Agent

    public init(catalog: AgentCatalog = .default, agent: any Agent) {
        self.catalog = catalog
        self.agent = agent
    }

    public func dispatch(
        prompt: String,
        agentID: String,
        parentTaskID: UUID? = nil
    ) async throws -> AgentResult {
        let definition = try catalog.require(id: agentID)
        guard definition.mode == .subagent || definition.mode == .all else {
            throw AgentCatalogError.notSubagent(agentID)
        }
        let task = AgentTask(
            prompt: prompt,
            kind: .auto,
            observations: [
                "subagent.id=\(agentID)",
                parentTaskID.map { "parent.task.id=\($0.uuidString)" },
            ].compactMap { $0 },
            agentID: agentID)
        return try await agent.execute(task: task)
    }
}
