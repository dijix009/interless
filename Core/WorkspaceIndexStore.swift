import Foundation
import Shared

/// In-process seam between the Workspace engine and the SQLite/FTS5 index
/// (ARCHITECTURE.md §9, §12).
///
/// NOT a service boundary — no IPC, no transport. The concrete conformer
/// (`GRDBWorkspaceIndexStore`, in the `Persistence` module) is the only file in
/// the project that imports GRDB; tests use an in-memory conformer. Placing the
/// protocol in `Core` keeps `Workspace → Core` (the scanner/git module never
/// imports GRDB), mirroring how `MemorySnapshotProvider` lets `Core` drive
/// `MLXEngine` without depending on it.
public protocol WorkspaceIndexStore: Sendable {
    /// Insert or replace a file's index entry. `file.content` is tokenized into the
    /// FTS5 index and **not** stored verbatim; `nil` content indexes the filename only.
    func upsert(_ file: IndexedFile) async throws

    /// Update only the incremental state for a file whose content hash is
    /// unchanged. This avoids retokenizing FTS content for a `touch` while still
    /// refreshing size/mtime so future scans can take the fast path.
    func updateState(_ state: FileIndexState) async throws

    /// Remove a file's index entry (e.g. it was deleted on disk).
    func removeFile(path: String) async throws

    /// Per-file state already in the index, for incremental skipping.
    func knownFileStates() async throws -> [FileIndexState]

    /// Per-file state lookup for path-scoped incremental indexing.
    func fileState(path: String) async throws -> FileIndexState?

    /// Extracted symbols for one indexed file, ordered by line. Lets search
    /// results carry their enclosing symbol (repo-map-style labels).
    func symbols(path: String) async throws -> [CodeSymbol]

    /// Ranked matches (path + bm25 score). Snippets are filled by the caller from
    /// disk, since the index stores no content.
    func search(_ query: String, limit: Int) async throws -> [SearchHit]

    /// Store a normalized embedding vector for one indexed file. The concrete
    /// store owns encoding details; callers pass MLX-free values.
    func upsertEmbedding(path: String, vector: EmbeddingVector) async throws

    /// Bounded semantic search over stored normalized vectors. Higher cosine
    /// similarity is converted to a lower `SearchHit.score` so callers can merge
    /// with FTS results using the same ordering convention.
    func semanticSearch(vector: EmbeddingVector, limit: Int) async throws -> [SearchHit]

    /// Begin a full scan: returns a seen-epoch strictly greater than every stamp
    /// already in the index (and ≥ wall-clock seconds), so a scan started in the
    /// same second as earlier writes still prunes correctly.
    func beginScan() async throws -> Int

    /// Insert or replace many files inside one transaction (bounds the per-file
    /// transaction storm during full reindex), stamping each row with `seenAt`.
    func upsertBatch(_ files: [IndexedFile], seenAt: Int) async throws

    /// Stamp existing rows as visited by the scan that started at `seenAt`.
    /// Used by the full-scan fast path so unchanged files survive `pruneUnseen`
    /// without a row rewrite.
    func markSeen(paths: [String], seenAt: Int) async throws

    /// Delete every index row whose seen-epoch predates `scanStart`, returning
    /// the number of files removed. Only valid after a COMPLETE full scan (every
    /// surviving file must have been stamped via upsert/updateState/markSeen).
    func pruneUnseen(olderThan scanStart: Int) async throws -> Int

    /// Generic workspace metadata (last scan time, branch, HEAD, schema version, …).
    func metadata(key: String) async throws -> String?
    func setMetadata(key: String, value: String?) async throws
}

public extension WorkspaceIndexStore {
    func fileState(path: String) async throws -> FileIndexState? {
        try await knownFileStates().first { $0.relativePath == path }
    }

    func upsertEmbedding(path: String, vector: EmbeddingVector) async throws {}

    func symbols(path: String) async throws -> [CodeSymbol] { [] }

    func semanticSearch(vector: EmbeddingVector, limit: Int) async throws -> [SearchHit] {
        []
    }

    func beginScan() async throws -> Int {
        Int(Date().timeIntervalSince1970)
    }

    func upsertBatch(_ files: [IndexedFile], seenAt: Int) async throws {
        for file in files { try await upsert(file) }
    }

    /// Default no-op: stores without seen-epoch tracking keep all rows…
    func markSeen(paths: [String], seenAt: Int) async throws {}

    /// …and consequently never prune. Conformers used with the full-scan
    /// indexer must override the seen-epoch family for deletion pruning to work.
    func pruneUnseen(olderThan scanStart: Int) async throws -> Int { 0 }
}
