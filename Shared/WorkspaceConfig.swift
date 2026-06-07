/// Tunable scan/index policy (ARCHITECTURE.md §9 thresholds). `Codable` so it can
/// be persisted as workspace metadata later.
public struct WorkspaceConfig: Sendable, Equatable, Codable {
    /// Files larger than this are indexed by filename only (content skipped).
    public var maxFileSizeBytes: Int
    /// How many leading bytes to scan for a NUL byte when detecting binary files.
    public var binarySniffByteCount: Int
    /// Whether to follow symbolic links while scanning (default false — loop-safe,
    /// least-privilege).
    public var followSymlinks: Bool
    /// Ignore-file names honored per directory, applied in order.
    public var ignoreFileNames: [String]
    /// Ignore files larger than this are skipped to keep traversal memory bounded.
    public var maxIgnoreFileSizeBytes: Int

    public init(
        maxFileSizeBytes: Int = 1 << 20,        // 1 MiB
        binarySniffByteCount: Int = 8192,
        followSymlinks: Bool = false,
        ignoreFileNames: [String] = [".gitignore", ".opencodeignore"],
        maxIgnoreFileSizeBytes: Int = 256 * 1024
    ) {
        self.maxFileSizeBytes = maxFileSizeBytes
        self.binarySniffByteCount = binarySniffByteCount
        self.followSymlinks = followSymlinks
        self.ignoreFileNames = ignoreFileNames
        self.maxIgnoreFileSizeBytes = max(0, maxIgnoreFileSizeBytes)
    }

    public static let `default` = WorkspaceConfig()
}
