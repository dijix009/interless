import Foundation
import Testing
import Workspace

struct WorkspaceSnapshotStoreTests {
    @Test func snapshotRevertRestoresExistingAndRemovesCreatedFiles() async throws {
        let root = try TempDir.make()
        let storage = try TempDir.make()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: storage)
        }
        try TempDir.write("before\n", to: "Sources/App.swift", in: root)
        let store = WorkspaceSnapshotStore(root: root, storageRoot: storage)

        let snapshot = try await store.createSnapshot(
            paths: ["Sources/App.swift", "Generated.txt"],
            reason: "test")
        try TempDir.write("after\n", to: "Sources/App.swift", in: root)
        try TempDir.write("created\n", to: "Generated.txt", in: root)

        let result = try await store.revert(snapshot.id)

        #expect(result.restoredPaths == ["Sources/App.swift"])
        #expect(result.removedPaths == ["Generated.txt"])
        #expect(try String(contentsOf: root.appendingPathComponent("Sources/App.swift"), encoding: .utf8) == "before\n")
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Generated.txt").path))
    }

    @Test func snapshotRejectsEscapesAndOversizedEntries() async throws {
        let root = try TempDir.make()
        let storage = try TempDir.make()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: storage)
        }
        try TempDir.write("12345", to: "large.txt", in: root)
        let store = WorkspaceSnapshotStore(root: root, storageRoot: storage, maxEntryBytes: 4)

        await #expect(throws: WorkspaceSnapshotError.invalidPath("../outside.txt")) {
            _ = try await store.createSnapshot(paths: ["../outside.txt"], reason: "escape")
        }
        await #expect(throws: WorkspaceSnapshotError.fileTooLarge(path: "large.txt", bytes: 5, limit: 4)) {
            _ = try await store.createSnapshot(paths: ["large.txt"], reason: "large")
        }
    }
}
