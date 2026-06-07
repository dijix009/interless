import Foundation
import Testing
import Shared
import Workspace

struct LibGit2RepositoryTests {
    @Test(.enabled(if: gitAvailable()))
    func repositoryStatusMatchesProcessProviderAndDiffsTrackedFiles() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        try runGit(["init", "-q", "-b", "main"], in: root)
        try runGit(["config", "user.email", "t@example.com"], in: root)
        try runGit(["config", "user.name", "Tester"], in: root)
        try TempDir.write("one\n", to: "tracked.txt", in: root)
        try runGit(["add", "tracked.txt"], in: root)
        try runGit(["commit", "-q", "-m", "init"], in: root)
        try TempDir.write("two\n", to: "tracked.txt", in: root)
        try TempDir.write("new\n", to: "untracked.txt", in: root)

        let repository = LibGit2Repository()
        let libgitStatus = await repository.snapshot(root: root)
        let processStatus = await ProcessGitMetadata().snapshot(root: root)
        let diff = try await repository.diff(root: root, path: "tracked.txt")

        #expect(repository.backend == .processFallback)
        #expect(libgitStatus.branch == processStatus.branch)
        #expect(Set(libgitStatus.entries.map(\.path)) == Set(processStatus.entries.map(\.path)))
        #expect(diff.contains("-one"))
        #expect(diff.contains("+two"))
    }

    @Test(.enabled(if: gitAvailable()))
    func repositoryDiffRejectsEscapingPaths() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        try runGit(["init", "-q", "-b", "main"], in: root)
        let repository = LibGit2Repository()

        await #expect(throws: GitRepositoryError.pathOutsideRepository("../outside.txt")) {
            _ = try await repository.diff(root: root, path: "../outside.txt")
        }
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

private func gitAvailable() -> Bool {
    FileManager.default.isExecutableFile(atPath: "/usr/bin/git")
}
