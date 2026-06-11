import Foundation
import Shared
import Core

/// A dictionary-backed `WorkspaceIndexStore` for coordinator tests (no GRDB).
/// Records upserts/removals for assertions; `search` does a naive substring match.
actor InMemoryIndexStore: WorkspaceIndexStore {
    private(set) var docs: [String: IndexedFile] = [:]
    private var meta: [String: String] = [:]
    private var seenAtByPath: [String: Int] = [:]
    private(set) var upsertCount = 0
    private(set) var updateStateCount = 0
    private(set) var removedPaths: [String] = []

    func upsert(_ file: IndexedFile) async throws {
        docs[file.relativePath] = file
        seenAtByPath[file.relativePath] = Int(Date().timeIntervalSince1970)
        upsertCount += 1
    }

    func beginScan() async throws -> Int {
        let maxSeen = seenAtByPath.values.max() ?? 0
        return max(Int(Date().timeIntervalSince1970), maxSeen + 1)
    }

    func upsertBatch(_ files: [IndexedFile], seenAt: Int) async throws {
        for file in files {
            try await upsert(file)
            seenAtByPath[file.relativePath] = seenAt
        }
    }

    func markSeen(paths: [String], seenAt: Int) async throws {
        for path in paths where docs[path] != nil {
            seenAtByPath[path] = max(seenAtByPath[path] ?? 0, seenAt)
        }
    }

    func pruneUnseen(olderThan scanStart: Int) async throws -> Int {
        let stale = docs.keys.filter { (seenAtByPath[$0] ?? 0) < scanStart }
        for path in stale {
            docs[path] = nil
            seenAtByPath[path] = nil
            removedPaths.append(path)
        }
        return stale.count
    }

    func updateState(_ state: FileIndexState) async throws {
        guard var doc = docs[state.relativePath] else { return }
        doc.sizeBytes = state.sizeBytes
        doc.modifiedAtEpoch = state.modifiedAtEpoch
        doc.contentHash = state.contentHash
        docs[state.relativePath] = doc
        seenAtByPath[state.relativePath] = Int(Date().timeIntervalSince1970)
        updateStateCount += 1
    }

    func removeFile(path: String) async throws {
        docs[path] = nil
        seenAtByPath[path] = nil
        removedPaths.append(path)
    }

    func knownFileStates() async throws -> [FileIndexState] {
        docs.values.map {
            FileIndexState(relativePath: $0.relativePath, sizeBytes: $0.sizeBytes,
                           modifiedAtEpoch: $0.modifiedAtEpoch, contentHash: $0.contentHash)
        }
    }

    func search(_ query: String, limit: Int) async throws -> [SearchHit] {
        let q = query.lowercased()
        return docs.values
            .filter { file in
                file.relativePath.lowercased().contains(q)
                || (file.content ?? "").lowercased().contains(q)
                || file.symbols.contains { $0.name.lowercased().contains(q) || $0.kind.lowercased().contains(q) }
                || file.comments.contains { $0.lowercased().contains(q) }
                || file.references.contains { $0.name.lowercased().contains(q) || $0.kind.lowercased().contains(q) }
            }
            .prefix(limit)
            .map { SearchHit(relativePath: $0.relativePath, score: 0, snippet: nil) }
    }

    func metadata(key: String) async throws -> String? { meta[key] }

    func setMetadata(key: String, value: String?) async throws { meta[key] = value }
}
