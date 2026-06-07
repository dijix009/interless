import Foundation
import Shared

/// The result of attempting to load a file's content for indexing.
public enum LoadedContent: Sendable, Equatable {
    /// Decodable text within the size cap; carries its size and content hash.
    case text(content: String, sizeBytes: Int, contentHash: String)
    /// A NUL byte was found in the sniff window — indexed by filename only.
    case binary(sizeBytes: Int, contentHash: String)
    /// Larger than `WorkspaceConfig.maxFileSizeBytes` — indexed by filename only.
    case skippedTooLarge(sizeBytes: Int)
    /// The file could not be read (e.g. vanished mid-scan).
    case unreadable(reason: String)
}

/// In-process seam for reading file content (ARCHITECTURE.md §9 async file loading).
/// The real implementation (`DiskFileContentLoader`) is the only file doing bounded
/// file reads + hashing; tests use a fake or temp files.
public protocol FileContentLoader: Sendable {
    /// Size-bounded async read: detects oversize and binary files, decodes UTF-8
    /// lossily, and hashes the bytes read. Never throws — failures map to
    /// `.unreadable`.
    func load(fileAt url: URL, config: WorkspaceConfig) async -> LoadedContent
}
