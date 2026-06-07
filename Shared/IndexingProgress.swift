/// Progress pushed on the indexer's stream (ARCHITECTURE.md §11 — push, never poll).
public struct IndexingProgress: Sendable, Equatable, Codable {
    public enum Phase: String, Sendable, Equatable, Codable, CaseIterable {
        case scanning, indexing, pruning, completed, cancelled, failed
    }

    public var phase: Phase
    public var scanned: Int   // entries seen by the scanner so far
    public var indexed: Int   // files (re)indexed this run
    public var skipped: Int   // unchanged files skipped
    public var removed: Int   // deleted files pruned
    public var lastPath: String?

    public init(
        phase: Phase,
        scanned: Int = 0,
        indexed: Int = 0,
        skipped: Int = 0,
        removed: Int = 0,
        lastPath: String? = nil
    ) {
        self.phase = phase
        self.scanned = scanned
        self.indexed = indexed
        self.skipped = skipped
        self.removed = removed
        self.lastPath = lastPath
    }
}
