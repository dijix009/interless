import Foundation
import Shared

/// In-process seam for git repository metadata (ARCHITECTURE.md §9).
///
/// The architecture names libgit2; process-git remains available as the parity
/// fallback behind this seam while the native repository provider is introduced.
public protocol GitMetadataProvider: Sendable {
    /// A git snapshot of the workspace root. Non-repositories and failures degrade
    /// gracefully to `GitStatus.notARepository` / empty status — this never throws
    /// (ARCHITECTURE.md §15).
    func snapshot(root: URL) async -> GitStatus
}
