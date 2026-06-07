import Testing
import Foundation
import Shared
import Workspace

struct FileContentLoaderTests {
    private let loader = DiskFileContentLoader()

    @Test func loadsUTF8Text() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        try TempDir.write("hello world", to: "a.txt", in: root)

        let result = await loader.load(fileAt: root.appendingPathComponent("a.txt"), config: .default)
        guard case let .text(content, size, hash) = result else {
            Issue.record("expected .text, got \(result)"); return
        }
        #expect(content == "hello world")
        #expect(size == 11)
        #expect(!hash.isEmpty)
    }

    @Test func detectsBinaryByNulByte() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        try TempDir.writeData(Data([0x68, 0x00, 0x69]), to: "b.bin", in: root)

        let result = await loader.load(fileAt: root.appendingPathComponent("b.bin"), config: .default)
        guard case .binary = result else { Issue.record("expected .binary, got \(result)"); return }
    }

    @Test func skipsOversizeFiles() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        try TempDir.write(String(repeating: "a", count: 2000), to: "big.txt", in: root)

        let result = await loader.load(
            fileAt: root.appendingPathComponent("big.txt"),
            config: WorkspaceConfig(maxFileSizeBytes: 1000))
        guard case .skippedTooLarge = result else { Issue.record("expected .skippedTooLarge, got \(result)"); return }
    }

    @Test func unreadableForMissingFile() async {
        let result = await loader.load(fileAt: URL(fileURLWithPath: "/nope/missing.txt"), config: .default)
        guard case .unreadable = result else { Issue.record("expected .unreadable, got \(result)"); return }
    }

    @Test func hashIsStableAndContentSensitive() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        try TempDir.write("abc", to: "1.txt", in: root)
        try TempDir.write("abc", to: "2.txt", in: root)
        try TempDir.write("abd", to: "3.txt", in: root)

        func hash(_ name: String) async -> String? {
            if case let .text(_, _, h) = await loader.load(fileAt: root.appendingPathComponent(name), config: .default) {
                return h
            }
            return nil
        }
        let h1 = await hash("1.txt")
        let h2 = await hash("2.txt")
        let h3 = await hash("3.txt")
        #expect(h1 != nil)
        #expect(h1 == h2)      // identical content → identical hash
        #expect(h1 != h3)      // one byte different → different hash
    }
}
