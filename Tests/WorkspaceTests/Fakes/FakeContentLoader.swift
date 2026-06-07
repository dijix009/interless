import Foundation
import Shared
import Workspace

/// Scripted content loader for coordinator tests, keyed by filename (last path
/// component). Configurable so incremental tests can change content between runs.
actor FakeContentLoader: FileContentLoader {
    private var byFileName: [String: LoadedContent]

    init(map: [String: LoadedContent]) { self.byFileName = map }

    func setMap(_ map: [String: LoadedContent]) { self.byFileName = map }

    func load(fileAt url: URL, config: WorkspaceConfig) async -> LoadedContent {
        byFileName[url.lastPathComponent]
            ?? .unreadable(reason: "no fake content for \(url.lastPathComponent)")
    }
}
