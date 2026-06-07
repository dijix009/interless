import Foundation
import Shared
import Workspace

/// Returns a fixed git snapshot for coordinator tests.
struct FakeGitMetadata: GitMetadataProvider {
    let status: GitStatus
    func snapshot(root: URL) async -> GitStatus { status }
}
