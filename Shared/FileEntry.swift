/// A single result of a workspace traversal (ARCHITECTURE.md §9).
///
/// Streamed one-at-a-time by the scanner so peak memory stays O(1) in tree size.
public struct FileEntry: Sendable, Equatable, Codable {
    /// Path relative to the workspace root, `/`-separated, no leading slash.
    public var relativePath: String
    public var isDirectory: Bool
    public var sizeBytes: Int
    /// Modification time as whole seconds since 1970 — stable across the SQLite
    /// round-trip (avoids sub-second `Double` drift in incremental comparisons).
    public var modifiedAtEpoch: Int

    public init(relativePath: String, isDirectory: Bool, sizeBytes: Int, modifiedAtEpoch: Int) {
        self.relativePath = relativePath
        self.isDirectory = isDirectory
        self.sizeBytes = sizeBytes
        self.modifiedAtEpoch = modifiedAtEpoch
    }
}
