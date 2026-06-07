/// A ranked workspace search result (ARCHITECTURE.md §9).
public struct SearchHit: Sendable, Equatable, Codable {
    public var relativePath: String
    /// bm25 relevance — **lower is more relevant** (SQLite FTS5 convention).
    public var score: Double
    /// A short excerpt around the match, filled on demand from disk (the index is
    /// contentless); `nil` if the file can't be read at query time.
    public var snippet: String?

    public init(relativePath: String, score: Double, snippet: String? = nil) {
        self.relativePath = relativePath
        self.score = score
        self.snippet = snippet
    }
}
