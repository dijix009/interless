import Foundation
import Core

public enum AgentCatalogError: Error, Sendable, Equatable {
    case missingAgent(String)
    case disabledAgent(String)
    case notSubagent(String)
}

public struct AgentCatalog: Sendable, Equatable {
    public var definitions: [String: AgentDefinition]

    public init(configured: [String: AgentDefinition] = [:]) {
        var merged = Self.builtIns
        for (id, definition) in configured {
            var copy = definition
            if copy.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                copy.id = id
            }
            merged[id] = copy
        }
        definitions = merged.filter { !$0.value.disabled }
    }

    public static let `default` = AgentCatalog()

    public var primaryAgents: [AgentDefinition] {
        orderedAgents.filter { $0.mode == .primary || $0.mode == .all }
    }

    public var subagents: [AgentDefinition] {
        orderedAgents.filter { $0.mode == .subagent || $0.mode == .all }
    }

    public func definition(id: String) -> AgentDefinition? {
        definitions[id]
    }

    public func require(id: String) throws -> AgentDefinition {
        guard let definition = definitions[id] else { throw AgentCatalogError.missingAgent(id) }
        guard !definition.disabled else { throw AgentCatalogError.disabledAgent(id) }
        return definition
    }

    public func route(for task: AgentTask) -> AgentRoute? {
        if let agentID = task.agentID, let definition = definitions[agentID] {
            return route(for: definition)
        }
        return nil
    }

    public func route(for definition: AgentDefinition) -> AgentRoute {
        switch definition.id {
        case "build", "plan":
            return .orchestrator
        default:
            return definition.mode == .subagent ? .utility : .utility
        }
    }

    public func systemPrompt(agentID: String, fallback: String) -> String {
        guard let system = definitions[agentID]?.system?.trimmingCharacters(in: .whitespacesAndNewlines),
              !system.isEmpty else {
            return fallback
        }
        return system
    }

    public func modelID(agentID: String) -> String? {
        guard let model = definitions[agentID]?.model?.trimmingCharacters(in: .whitespacesAndNewlines),
              !model.isEmpty else {
            return nil
        }
        return model
    }

    public func permissionOverlay(agentID: String) -> [PolicyStatement] {
        definitions[agentID]?.permissions ?? []
    }

    private var orderedAgents: [AgentDefinition] {
        definitions.values.sorted { lhs, rhs in lhs.id < rhs.id }
    }

    private static let builtIns: [String: AgentDefinition] = {
        let build = AgentDefinition(
            id: "build",
            description: "Implementation and multi-file coding agent.",
            system: "You are the build agent. Implement native Swift changes with narrow scope, test coverage, and architecture-boundary discipline. After you change files the harness automatically builds and runs tests; if it reports failures, fix the root cause and continue rather than reporting completion.",
            mode: .primary)
        let plan = AgentDefinition(
            id: "plan",
            description: "Read-only planning agent.",
            system: "You are the plan agent. Produce concise implementation plans, identify risks, and do not modify files.",
            mode: .primary)
        let general = AgentDefinition(
            id: "general",
            description: "General utility agent.",
            system: "You are the general agent. Answer directly, use native tools only when useful, and keep context bounded.",
            mode: .primary)
        let title = AgentDefinition(
            id: "title",
            description: "Conversation title agent.",
            system: "Generate short, specific local conversation titles without exposing private context.",
            mode: .subagent,
            hidden: true)
        let todo = AgentDefinition(
            id: "todo",
            description: "Todo extraction agent.",
            system: "Maintain concise task todos from the current session state.",
            mode: .subagent,
            hidden: true)
        let explore = AgentDefinition(
            id: "explore",
            description: "Read-only exploration sub-agent.",
            system: "You are the explore sub-agent. Investigate the workspace to answer the request — locate code, trace usage, and explain how pieces fit together using read-only tools (read_file, grep, glob, git). You cannot modify files. Return a concise, specific summary with file:line references that the calling agent can act on.",
            mode: .subagent)
        let review = AgentDefinition(
            id: "review",
            description: "Read-only code review sub-agent.",
            system: "You are the review sub-agent. Review the described code or change for correctness, edge cases, and clarity using read-only tools. You cannot modify files. Return a concise, prioritized list of concrete findings with file:line references.",
            mode: .subagent)
        return Dictionary(uniqueKeysWithValues: [build, plan, general, title, todo, explore, review].map { ($0.id, $0) })
    }()
}
