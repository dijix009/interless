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

    /// Generic workspace metadata (last scan time, branch, HEAD, schema version, …).
    func metadata(key: String) async throws -> String?
    func setMetadata(key: String, value: String?) async throws
}

public extension WorkspaceIndexStore {
    func fileState(path: String) async throws -> FileIndexState? {
        try await knownFileStates().first { $0.relativePath == path }
    }

    func upsertEmbedding(path: String, vector: EmbeddingVector) async throws {}

    func semanticSearch(vector: EmbeddingVector, limit: Int) async throws -> [SearchHit] {
        []
    }
}
