import Foundation
import Testing
@testable import Workspace

private func worktreeGitAvailable() -> Bool {
    FileManager.default.isExecutableFile(atPath: "/usr/bin/git")
}

struct WorktreeCoordinatorTests {
    @Test(.enabled(if: worktreeGitAvailable()))
    func worktreeListAddAndRemoveRoundTrips() async throws {
        let root = try TempDir.make()
        let worktree = root.deletingLastPathComponent().appendingPathComponent("wt-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: worktree)
        }
        try runGit(["init", "-q", "-b", "main"], in: root)
        try runGit(["config", "user.email", "t@example.com"], in: root)
        try runGit(["config", "user.name", "Tester"], in: root)
        try TempDir.write("hello\n", to: "README.md", in: root)
        try runGit(["add", "README.md"], in: root)
        try runGit(["commit", "-q", "-m", "init"], in: root)

        let coordinator = WorktreeCoordinator(root: root)
        let initial = try await coordinator.list()
        #expect(initial.contains { $0.path.hasSuffix(root.lastPathComponent) })

        _ = try await coordinator.add(path: worktree, newBranch: "feature/worktree-test")
        let added = try await coordinator.list()
        #expect(added.contains { $0.path.hasSuffix(worktree.lastPathComponent) })

        try await coordinator.remove(path: worktree, force: true)
        let removed = try await coordinator.list()
        #expect(!removed.contains { $0.path.hasSuffix(worktree.lastPathComponent) })
    }

    @Test func parsePorcelainListExtractsBranchAndHead() {
        let worktrees = WorktreeCoordinator.parsePorcelainList("""
        worktree /tmp/project
        HEAD abc123
        branch refs/heads/main

        worktree /tmp/project-feature
        HEAD def456
        branch refs/heads/feature/worktree-test

        """)

        #expect(worktrees == [
            WorkspaceWorktree(path: "/tmp/project", branch: "main", headSHA: "abc123"),
            WorkspaceWorktree(path: "/tmp/project-feature", branch: "feature/worktree-test", headSHA: "def456"),
        ])
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
