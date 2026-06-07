import Testing
import Foundation
import Shared
import Core
import Workspace
import Persistence

/// End-to-end: the real scanner + GRDB store + git CLI over a temp repo. Fast
/// (temp dir + in-memory SQLite + local git), so it runs under `./scripts/test.sh`
/// — no Metal/xcodebuild, no gating. This is the wiring App/ will own in Phase 4.
struct WorkspaceEndToEndTests {

    @Test func indexThenSearchRespectingGitignoreThenIncremental() async throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/git") else { return }
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        try write("func authenticate() {}", "Auth.swift", root)
        try write("nested code beta token", "sub/Beta.swift", root)
        try write("ignored secret value", "skip.log", root)
        try write("*.log\n", ".gitignore", root)
        try runGit(["init", "-q", "-b", "main"], root)
        try runGit(["config", "user.email", "t@example.com"], root)
        try runGit(["config", "user.name", "Tester"], root)
        try runGit(["add", "."], root)
        try runGit(["commit", "-q", "-m", "init"], root)

        let store = try PersistenceBootstrap.inMemoryStore()
        let indexer = WorkspaceIndexer(
            root: root,
            scanner: FileSystemScanner(),
            store: store,
            git: ProcessGitMetadata(),
            loader: DiskFileContentLoader())

        let first = await drain(indexer)
        #expect(first.phase == .completed)
        #expect(first.indexed >= 2) // at least Auth.swift + sub/Beta.swift

        // Content search + snippet enrichment from disk.
        let authHits = try await indexer.search("authenticate", limit: 10)
        #expect(authHits.contains { $0.relativePath == "Auth.swift" })
        #expect(authHits.first(where: { $0.relativePath == "Auth.swift" })?.snippet?.contains("authenticate") == true)

        #expect(try await indexer.search("beta", limit: 10).contains { $0.relativePath == "sub/Beta.swift" })

        // .gitignore'd file is not indexed.
        #expect(try await indexer.search("secret", limit: 10).isEmpty)

        // Git metadata captured.
        #expect(try await store.metadata(key: "git.branch") == "main")

        // Re-index with no changes ⇒ nothing re-indexed, everything skipped.
        let second = await drain(indexer)
        #expect(second.indexed == 0)
        #expect(second.skipped == first.indexed)

        // Delete a file ⇒ pruned on next re-index.
        try FileManager.default.removeItem(at: root.appendingPathComponent("Auth.swift"))
        let third = await drain(indexer)
        #expect(third.removed == 1)
        #expect(try await indexer.search("authenticate", limit: 10).isEmpty)
    }

    // MARK: helpers

    private func drain(_ indexer: WorkspaceIndexer) async -> IndexingProgress {
        let stream = await indexer.reindex()
        var last = IndexingProgress(phase: .scanning)
        for await progress in stream { last = progress }
        return last
    }

    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ife2e-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ contents: String, _ relativePath: String, _ root: URL) throws {
        let fileURL = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private func runGit(_ args: [String], _ root: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", root.path] + args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
    }
}
