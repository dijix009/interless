import Foundation

public enum SystemContextVisibility: String, Sendable, Equatable, Codable, CaseIterable {
    case modelVisible
    case internalOnly
}

public struct SystemContextSource: Sendable, Equatable, Codable, Identifiable {
    public var id: String
    public var title: String
    public var body: String
    public var priority: Int
    public var visibility: SystemContextVisibility
    public var metadata: [String: String]

    public init(
        id: String,
        title: String,
        body: String,
        priority: Int = 0,
        visibility: SystemContextVisibility = .modelVisible,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.priority = priority
        self.visibility = visibility
        self.metadata = metadata
    }
}

public actor SystemContextRegistry {
    private var sources: [String: SystemContextSource]

    public init(sources: [SystemContextSource] = []) {
        self.sources = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })
    }

    public func register(_ source: SystemContextSource) {
        sources[source.id] = source
    }

    public func remove(id: String) {
        sources[id] = nil
    }

    public func source(id: String) -> SystemContextSource? {
        sources[id]
    }

    public func all(includeInternal: Bool = false) -> [SystemContextSource] {
        orderedSources(includeInternal: includeInternal)
    }

    public func render(includeInternal: Bool = false, maxCharacters: Int = 16_000) -> String {
        let rendered = orderedSources(includeInternal: includeInternal)
            .filter { !$0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { source in
                """
                [\(source.title)]
                \(source.body)
                """
            }
            .joined(separator: "\n\n")
        return truncate(rendered, limit: max(0, maxCharacters))
    }

    private func orderedSources(includeInternal: Bool) -> [SystemContextSource] {
        sources.values
            .filter { includeInternal || $0.visibility == .modelVisible }
            .sorted { lhs, rhs in
                if lhs.priority == rhs.priority { return lhs.id < rhs.id }
                return lhs.priority < rhs.priority
            }
    }

    private func truncate(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        guard limit > 16 else { return String(text.prefix(limit)) }
        return String(text.prefix(limit - 16)) + "\n[truncated]\n"
    }
}
