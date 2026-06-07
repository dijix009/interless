import Foundation
import Shared

/// In-process seam for workspace traversal (ARCHITECTURE.md §9).
///
/// NOT a service boundary. The real implementation (`FileSystemScanner`) is the
/// only file using `FileManager`'s directory enumerator and applies nested
/// `.gitignore`/`.opencodeignore` rules itself; tests use a `FakeScanner`.
public protocol WorkspaceScanner: Sendable {
    /// Validate `root` (throws `WorkspaceError.rootNotFound`/`.rootNotDirectory`),
    /// then stream non-ignored entries **lazily** (pull-based, O(1) memory — the
    /// producer advances one entry per consumer demand, so nothing is buffered or
    /// dropped). `.git/` and ignored directories are pruned (never descended).
    func scan(root: URL) async throws -> AsyncStream<FileEntry>
}
