import Foundation

/// Foundation-only temp-directory helpers for the file-touching tests.
enum TempDir {
    static func make() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("iftest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func write(_ contents: String, to relativePath: String, in root: URL) throws {
        try writeData(Data(contents.utf8), to: relativePath, in: root)
    }

    static func writeData(_ data: Data, to relativePath: String, in root: URL) throws {
        let fileURL = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL)
    }
}
