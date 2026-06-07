import Foundation
import CryptoKit
import Shared

/// Reads file content for indexing (ARCHITECTURE.md §9). The only file doing
/// bounded file reads + hashing. Stateless → a `Sendable` struct.
public struct DiskFileContentLoader: FileContentLoader {

    public init() {}

    public func load(fileAt url: URL, config: WorkspaceConfig) async -> LoadedContent {
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }

            // Read up to cap+1 bytes so we can detect "over the cap" without
            // slurping an arbitrarily large file into memory (§9 low-memory).
            let cap = max(0, config.maxFileSizeBytes)
            let data = try handle.read(upToCount: cap + 1) ?? Data()
            if data.count > cap {
                return .skippedTooLarge(sizeBytes: data.count)
            }

            let hash = Self.hexSHA256(data)
            let sniff = data.prefix(max(0, config.binarySniffByteCount))
            if sniff.contains(0) {
                return .binary(sizeBytes: data.count, contentHash: hash)
            }
            // Lossy UTF-8 decode — never throws on invalid bytes.
            let text = String(decoding: data, as: UTF8.self)
            return .text(content: text, sizeBytes: data.count, contentHash: hash)
        } catch {
            return .unreadable(reason: String(describing: error))
        }
    }

    private static func hexSHA256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
