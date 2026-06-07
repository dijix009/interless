import Foundation
import Shared
import Core
import Tooling

public protocol WorkspaceSearchProviding: Sendable {
    func search(_ query: String, limit: Int) async throws -> [SearchHit]
}

public struct WorkspaceIndexSearchProvider: WorkspaceSearchProviding {
    private let store: any WorkspaceIndexStore

    public init(store: any WorkspaceIndexStore) {
        self.store = store
    }

    public func search(_ query: String, limit: Int) async throws -> [SearchHit] {
        try await store.search(query, limit: limit)
    }
}

public struct AgentContext: Sendable, Equatable, Codable {
    public var rendered: String
    public var hits: [SearchHit]
    public var truncated: Bool

    public init(rendered: String, hits: [SearchHit] = [], truncated: Bool = false) {
        self.rendered = rendered
        self.hits = hits
        self.truncated = truncated
    }
}

public struct ContextBuilder: Sendable {
    public var searchProvider: (any WorkspaceSearchProviding)?
    public var maxSearchResults: Int
    public var maxContextCharacters: Int
    public var maxSnippetCharacters: Int
    public var metrics: MetricsRecorder?

    public init(
        searchProvider: (any WorkspaceSearchProviding)? = nil,
        maxSearchResults: Int = 8,
        maxContextCharacters: Int = 24_000,
        maxSnippetCharacters: Int = 1_500,
        metrics: MetricsRecorder? = nil
    ) {
        self.searchProvider = searchProvider
        self.maxSearchResults = max(0, maxSearchResults)
        self.maxContextCharacters = max(0, maxContextCharacters)
        self.maxSnippetCharacters = max(0, maxSnippetCharacters)
        self.metrics = metrics
    }

    public init(
        searchProvider: (any WorkspaceSearchProviding)? = nil,
        budget: ResourceBudget,
        metrics: MetricsRecorder? = nil
    ) {
        self.init(
            searchProvider: searchProvider,
            maxSearchResults: budget.maxSearchResults,
            maxContextCharacters: budget.maxContextCharacters,
            maxSnippetCharacters: budget.maxSnippetCharacters,
            metrics: metrics)
    }

    public func build(task: AgentTask, toolResults: [ToolResult] = []) async throws -> AgentContext {
        let hits = try await searchProvider?.search(task.prompt, limit: maxSearchResults) ?? []
        var sections: [String] = []
        sections.append("Task:\n\(task.prompt)")

        if !hits.isEmpty {
            let renderedHits = hits.enumerated().map { index, hit in
                var lines = ["[\(index + 1)] \(hit.relativePath) score=\(hit.score)"]
                if let snippet = hit.snippet, !snippet.isEmpty {
                    lines.append(truncate(snippet, limit: maxSnippetCharacters))
                }
                return lines.joined(separator: "\n")
            }
            sections.append("Workspace Search:\n" + renderedHits.joined(separator: "\n\n"))
        }

        if !task.observations.isEmpty {
            sections.append("Observations:\n" + task.observations.joined(separator: "\n"))
        }

        if !toolResults.isEmpty {
            let renderedTools = toolResults.map { result in
                """
                \(result.request.displayName) exit=\(result.exitCode.map(String.init) ?? "n/a")
                stdout:
                \(truncate(result.stdout, limit: maxSnippetCharacters))
                stderr:
                \(truncate(result.stderr, limit: maxSnippetCharacters))
                """
            }
            sections.append("Tool Results:\n" + renderedTools.joined(separator: "\n\n"))
        }

        let rendered = sections.joined(separator: "\n\n---\n\n")
        let truncated = rendered.count > maxContextCharacters
        let final = AgentContext(
            rendered: truncated ? truncate(rendered, limit: maxContextCharacters) : rendered,
            hits: hits,
            truncated: truncated)
        await metrics?.record(.init(
            kind: .contextCharacters,
            unit: .count,
            value: Double(final.rendered.count),
            metadata: ["truncated": truncated ? "true" : "false"]))
        return final
    }

    private func truncate(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        guard limit > 16 else { return String(text.prefix(limit)) }
        return String(text.prefix(limit - 16)) + "\n[truncated]\n"
    }
}
