import Foundation
import CryptoKit

/// Computes the on-disk location of a workspace's index database.
///
/// The DB lives under Application Support, namespaced by the app name and a digest
/// of the (canonicalized) workspace root — so distinct workspaces never collide
/// and the root path is kept out of the filename (ARCHITECTURE.md §14 hygiene).
public enum WorkspaceDatabaseLocator {

    /// Returns `…/Application Support/Interless/workspaces/<digest>/index.sqlite`,
    /// creating the directory if needed.
    public static func databaseURL(forWorkspaceRoot root: URL) throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)

        let canonical = root.standardizedFileURL.resolvingSymlinksInPath().path
        let digest = SHA256.hash(data: Data(canonical.utf8))
            .prefix(8)
            .map { String(format: "%02x", $0) }
            .joined() // 16 hex chars — stable across reopens

        let directory = support
            .appendingPathComponent("Interless", isDirectory: true)
            .appendingPathComponent("workspaces", isDirectory: true)
            .appendingPathComponent(digest, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        return directory.appendingPathComponent("index.sqlite", isDirectory: false)
    }
}
