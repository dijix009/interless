import Testing
import Foundation
import Shared
import Workspace

/// Real `git` against a temp repo — fast + deterministic, so not gated (unlike the
/// MLX integration tests). Skipped only if `git` is somehow absent.
private func gitAvailable() -> Bool {
    FileManager.default.isExecutableFile(atPath: "/usr/bin/git")
}

struct ProcessGitMetadataTests {

    @Test(.enabled(if: gitAvailable()))
    func reportsRepositoryMetadata() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        try runGit(["init", "-q", "-b", "main"], in: root)
        try runGit(["config", "user.email", "t@example.com"], in: root)
        try runGit(["config", "user.name", "Tester"], in: root)
        try TempDir.write("hello", to: "a.txt", in: root)
        try runGit(["add", "a.txt"], in: root)
        try runGit(["commit", "-q", "-m", "init"], in: root)
        try TempDir.write("dirty", to: "b.txt", in: root) // untracked

        let status = await ProcessGitMetadata().snapshot(root: root)
        #expect(status.isRepository)
        #expect(status.branch == "main")
        #expect((status.headSHA?.count ?? 0) >= 7)
        #expect(status.entries.contains { $0.path == "b.txt" && $0.xy == "??" })
    }

    @Test(.enabled(if: gitAvailable()))
    func nonRepositoryReportsNotARepository() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let status = await ProcessGitMetadata().snapshot(root: root)
        #expect(!status.isRepository)
    }

    private func runGit(_ args: [String], in root: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", root.path] + args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
    }
}
