import Testing
import Foundation
import Shared
import Workspace

struct FileSystemScannerTests {

    @Test func scansFilesAndAppliesNestedIgnore() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        try TempDir.write("keep", to: "keep.txt", in: root)
        try TempDir.write("*.log\n", to: ".gitignore", in: root)
        try TempDir.write("x", to: "debug.log", in: root)              // ignored (root *.log)
        try TempDir.write("!special.log\n", to: "sub/.gitignore", in: root) // re-include in sub
        try TempDir.write("x", to: "sub/special.log", in: root)        // re-included
        try TempDir.write("x", to: "sub/other.log", in: root)          // still ignored
        try TempDir.write("code", to: "sub/main.swift", in: root)

        let entries = await collect(try await FileSystemScanner().scan(root: root))
        let paths = Set(entries.map(\.relativePath))

        #expect(paths.contains("keep.txt"))
        #expect(paths.contains("sub/main.swift"))
        #expect(paths.contains("sub/special.log"))   // nested .gitignore re-include
        #expect(!paths.contains("debug.log"))         // root *.log
        #expect(!paths.contains("sub/other.log"))     // root *.log, not re-included
        #expect(entries.allSatisfy { !$0.isDirectory }) // scanner yields files only
    }

    @Test func gitDirectoryIsAlwaysSkipped() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        try TempDir.write("[core]", to: ".git/config", in: root)
        try TempDir.write("code", to: "main.swift", in: root)

        let paths = Set(await collect(try await FileSystemScanner().scan(root: root)).map(\.relativePath))
        #expect(paths.contains("main.swift"))
        #expect(!paths.contains { $0.hasPrefix(".git/") })
    }

    @Test func oversizedIgnoreFilesAreSkipped() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        try TempDir.write("ignored.txt\n", to: ".gitignore", in: root)
        try TempDir.write("visible", to: "ignored.txt", in: root)
        let scanner = FileSystemScanner(config: WorkspaceConfig(maxIgnoreFileSizeBytes: 4))

        let paths = Set(await collect(try await scanner.scan(root: root)).map(\.relativePath))
        let entry = try await scanner.entry(root: root, relativePath: "ignored.txt")

        #expect(paths.contains("ignored.txt"))
        #expect(entry?.relativePath == "ignored.txt")
    }

    @Test func missingRootThrows() async {
        await #expect(throws: WorkspaceError.self) {
            _ = try await FileSystemScanner().scan(root: URL(fileURLWithPath: "/nonexistent/iftest/xyz"))
        }
    }

    @Test func fileAsRootThrows() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        try TempDir.write("x", to: "afile", in: root)
        await #expect(throws: WorkspaceError.self) {
            _ = try await FileSystemScanner().scan(root: root.appendingPathComponent("afile"))
        }
    }

    private func collect(_ stream: AsyncStream<FileEntry>) async -> [FileEntry] {
        var out: [FileEntry] = []
        for await entry in stream { out.append(entry) }
        return out
    }
}
