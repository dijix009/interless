import Foundation
import Shared
import Workspace

/// Scripted scanner for coordinator tests. Yields a configurable set of entries.
actor FakeScanner: WorkspaceScanner {
    private var entries: [FileEntry]

    init(entries: [FileEntry]) { self.entries = entries }

    func setEntries(_ entries: [FileEntry]) { self.entries = entries }

    func scan(root: URL) async throws -> AsyncStream<FileEntry> {
        let snapshot = entries
        return AsyncStream { continuation in
            for entry in snapshot { continuation.yield(entry) }
            continuation.finish()
        }
    }
}
