/// The per-file state the index already knows, used to skip unchanged files on a
/// re-index (ARCHITECTURE.md §9, "incremental indexing").
public struct FileIndexState: Sendable, Equatable, Codable {
    public var relativePath: String
    public var sizeBytes: Int
    public var modifiedAtEpoch: Int
    public var contentHash: String

    public init(relativePath: String, sizeBytes: Int, modifiedAtEpoch: Int, contentHash: String) {
        self.relativePath = relativePath
        self.sizeBytes = sizeBytes
        self.modifiedAtEpoch = modifiedAtEpoch
        self.contentHash = contentHash
    }
}
