import Foundation
import os
import GRDB
import Core
import Shared

/// GRDB-backed `WorkspaceIndexStore` (ARCHITECTURE.md §9, §12). The **only** file
/// in the project that imports GRDB.
///
/// Not an actor: GRDB serializes database access internally (and honors `Task`
/// cancellation), so wrapping it in an actor would only add a redundant hop and
/// serialize otherwise-concurrent reads. Sendable via its immutable Sendable
/// members (`DatabaseWriter` is Sendable).
public final class GRDBWorkspaceIndexStore: WorkspaceIndexStore {

    private let dbWriter: any DatabaseWriter
    private let log = Logger(subsystem: "dev.interless", category: "indexing")

    public init(dbWriter: any DatabaseWriter) {
        self.dbWriter = dbWriter
    }

    public func upsert(_ file: IndexedFile) async throws {
        try await dbWriter.write { db in
            try db.execute(sql: """
                INSERT INTO indexed_file (path, size, mtime, contentHash, indexedAt)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(path) DO UPDATE SET
                    size = excluded.size, mtime = excluded.mtime,
                    contentHash = excluded.contentHash, indexedAt = excluded.indexedAt
                """, arguments: [
                    file.relativePath, file.sizeBytes, file.modifiedAtEpoch,
                    file.contentHash, Int(Date().timeIntervalSince1970),
                ])
            guard let rowid = try Int64.fetchOne(
                db, sql: "SELECT id FROM indexed_file WHERE path = ?", arguments: [file.relativePath])
            else { return }
            // Refresh the FTS row (contentless: delete by rowid, then re-insert).
            try db.execute(sql: "DELETE FROM file_fts WHERE rowid = ?", arguments: [rowid])
            try db.execute(
                sql: """
                    INSERT INTO file_fts (rowid, filename, body, symbols, comments, "references")
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    rowid,
                    file.fileName,
                    file.content ?? "",
                    file.symbols.map { "\($0.kind) \($0.name)" }.joined(separator: " "),
                    file.comments.joined(separator: " "),
                    file.references.map { "\($0.kind) \($0.name)" }.joined(separator: " "),
                ])
            try db.execute(sql: "DELETE FROM file_symbol WHERE fileID = ?", arguments: [rowid])
            for symbol in file.symbols {
                try db.execute(sql: """
                    INSERT INTO file_symbol (fileID, path, name, kind, line, column)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """, arguments: [rowid, file.relativePath, symbol.name, symbol.kind, symbol.line, symbol.column])
            }
            try db.execute(sql: "DELETE FROM file_reference WHERE fileID = ?", arguments: [rowid])
            for reference in file.references {
                try db.execute(sql: """
                    INSERT INTO file_reference (fileID, path, name, kind, line, column)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """, arguments: [rowid, file.relativePath, reference.name, reference.kind, reference.line, reference.column])
            }
        }
    }

    public func updateState(_ state: FileIndexState) async throws {
        try await dbWriter.write { db in
            try db.execute(sql: """
                UPDATE indexed_file
                SET size = ?, mtime = ?, contentHash = ?, indexedAt = ?
                WHERE path = ?
                """, arguments: [
                    state.sizeBytes,
                    state.modifiedAtEpoch,
                    state.contentHash,
                    Int(Date().timeIntervalSince1970),
                    state.relativePath,
                ])
        }
    }

    public func removeFile(path: String) async throws {
        try await dbWriter.write { db in
            guard let rowid = try Int64.fetchOne(
                db, sql: "SELECT id FROM indexed_file WHERE path = ?", arguments: [path])
            else { return }
            try db.execute(sql: "DELETE FROM file_fts WHERE rowid = ?", arguments: [rowid])
            try db.execute(sql: "DELETE FROM file_symbol WHERE fileID = ?", arguments: [rowid])
            try db.execute(sql: "DELETE FROM file_reference WHERE fileID = ?", arguments: [rowid])
            try db.execute(sql: "DELETE FROM indexed_file WHERE id = ?", arguments: [rowid])
            try db.execute(sql: "DELETE FROM file_embedding WHERE path = ?", arguments: [path])
        }
    }

    public func knownFileStates() async throws -> [FileIndexState] {
        try await dbWriter.read { db in
            try Row.fetchAll(db, sql: "SELECT path, size, mtime, contentHash FROM indexed_file")
                .map { row in
                    FileIndexState(
                        relativePath: row["path"],
                        sizeBytes: row["size"],
                        modifiedAtEpoch: row["mtime"],
                        contentHash: row["contentHash"])
                }
        }
    }

    public func fileState(path: String) async throws -> FileIndexState? {
        try await dbWriter.read { db in
            try Row.fetchOne(db, sql: """
                SELECT path, size, mtime, contentHash
                FROM indexed_file
                WHERE path = ?
                """, arguments: [path]).map { row in
                    FileIndexState(
                        relativePath: row["path"],
                        sizeBytes: row["size"],
                        modifiedAtEpoch: row["mtime"],
                        contentHash: row["contentHash"])
                }
        }
    }

    public func search(_ query: String, limit: Int) async throws -> [SearchHit] {
        // An empty/invalid query produces no pattern → no results (no error).
        guard let pattern = FTS5Pattern(matchingAllTokensIn: query)?.rawPattern else { return [] }
        return try await dbWriter.read { db in
            try Row.fetchAll(db, sql: """
                SELECT f.path AS path, bm25(file_fts, 8.0, 1.0, 5.0, 3.0, 2.0) AS score
                FROM file_fts
                JOIN indexed_file f ON f.id = file_fts.rowid
                WHERE file_fts MATCH ?
                ORDER BY score
                LIMIT ?
                """, arguments: [pattern, limit])
                .map { row in
                    SearchHit(relativePath: row["path"], score: row["score"], snippet: nil)
                }
        }
    }

    public func upsertEmbedding(path: String, vector: EmbeddingVector) async throws {
        guard !vector.isEmpty else { return }
        let data = Self.encode(vector.values)
        try await dbWriter.write { db in
            try db.execute(sql: """
                INSERT INTO file_embedding (path, dimensions, vector, updatedAt)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(path) DO UPDATE SET
                    dimensions = excluded.dimensions,
                    vector = excluded.vector,
                    updatedAt = excluded.updatedAt
                """, arguments: [
                    path,
                    vector.dimensions,
                    data,
                    Int(Date().timeIntervalSince1970),
                ])
        }
    }

    public func semanticSearch(vector: EmbeddingVector, limit: Int) async throws -> [SearchHit] {
        guard !vector.isEmpty, limit > 0 else { return [] }
        let query = vector.values
        let dimensions = vector.dimensions
        return try await dbWriter.read { db in
            // Stream rows one vector at a time and keep only the top-`limit` hits, so
            // peak memory is O(limit) rather than O(repo). Stored vectors are already
            // normalized, so a raw dot product over the BLOB equals cosine similarity
            // — avoiding a per-row [Float]/EmbeddingVector allocation and re-normalize.
            let cursor = try Row.fetchCursor(db, sql: "SELECT path, dimensions, vector FROM file_embedding")
            var top: [SearchHit] = []   // ascending score; best (lowest score = most similar) first
            top.reserveCapacity(limit + 1)
            while let row = try cursor.next() {
                let rowDimensions: Int = row["dimensions"]
                guard rowDimensions == dimensions else { continue }
                let data: Data = row["vector"]
                guard let similarity = Self.dotProduct(data, query) else { continue }
                let score = -Double(similarity)
                if top.count >= limit, let worst = top.last, score >= worst.score { continue }
                let path: String = row["path"]
                Self.insertSorted(&top, SearchHit(relativePath: path, score: score))
                if top.count > limit { top.removeLast() }
            }
            return top
        }
    }

    public func metadata(key: String) async throws -> String? {
        try await dbWriter.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM metadata WHERE key = ?", arguments: [key])
        }
    }

    public func setMetadata(key: String, value: String?) async throws {
        try await dbWriter.write { db in
            try db.execute(sql: """
                INSERT INTO metadata (key, value) VALUES (?, ?)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value
                """, arguments: [key, value])
        }
    }

    private static func encode(_ values: [Float]) -> Data {
        values.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private static func decode(_ data: Data) -> [Float] {
        let count = data.count / MemoryLayout<Float>.stride
        guard count > 0 else { return [] }
        return data.withUnsafeBytes { buffer in
            guard let base = buffer.bindMemory(to: Float.self).baseAddress else { return [] }
            return Array(UnsafeBufferPointer(start: base, count: count))
        }
    }

    /// Dot product of a stored (already-normalized) Float BLOB with the normalized
    /// query, without materializing a `[Float]` per row. nil on dimension mismatch.
    private static func dotProduct(_ data: Data, _ query: [Float]) -> Float? {
        let count = data.count / MemoryLayout<Float>.stride
        guard count == query.count, count > 0 else { return nil }
        return data.withUnsafeBytes { raw -> Float in
            let stored = raw.bindMemory(to: Float.self)
            var sum: Float = 0
            for index in 0..<count { sum += stored[index] * query[index] }
            return sum
        }
    }

    /// Insert into an array kept sorted ascending by `score` (binary search). Used
    /// for the bounded top-`limit` set in `semanticSearch`.
    private static func insertSorted(_ array: inout [SearchHit], _ hit: SearchHit) {
        var low = 0
        var high = array.count
        while low < high {
            let mid = (low + high) / 2
            if array[mid].score < hit.score { low = mid + 1 } else { high = mid }
        }
        array.insert(hit, at: low)
    }
}
