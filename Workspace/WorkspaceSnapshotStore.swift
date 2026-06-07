import CryptoKit
import Foundation

public enum WorkspaceSnapshotError: Error, Sendable, Equatable {
    case invalidPath(String)
    case pathEscapesWorkspace(String)
    case snapshotNotFound(UUID)
    case fileTooLarge(path: String, bytes: Int, limit: Int)
    case unsupportedSymlink(String)
}

public enum WorkspaceSnapshotEntryKind: String, Sendable, Equatable, Codable {
    case file
    case directory
    case missing
}

public struct WorkspaceSnapshotEntry: Sendable, Equatable, Codable, Identifiable {
    public var id: String { relativePath }
    public var relativePath: String
    public var kind: WorkspaceSnapshotEntryKind
    public var byteCount: Int

    public init(relativePath: String, kind: WorkspaceSnapshotEntryKind, byteCount: Int = 0) {
        self.relativePath = relativePath
        self.kind = kind
        self.byteCount = max(0, byteCount)
    }
}

public struct WorkspaceMutationSnapshot: Sendable, Equatable, Codable, Identifiable {
    public var id: UUID
    public var workspaceRootPath: String
    public var reason: String
    public var createdAt: Date
    public var entries: [WorkspaceSnapshotEntry]

    public init(
        id: UUID = UUID(),
        workspaceRootPath: String,
        reason: String,
        createdAt: Date = Date(),
        entries: [WorkspaceSnapshotEntry]
    ) {
        self.id = id
        self.workspaceRootPath = workspaceRootPath
        self.reason = reason
        self.createdAt = createdAt
        self.entries = entries
    }
}

public struct WorkspaceMutationRevertResult: Sendable, Equatable {
    public var snapshotID: UUID
    public var restoredPaths: [String]
    public var removedPaths: [String]

    public init(snapshotID: UUID, restoredPaths: [String], removedPaths: [String]) {
        self.snapshotID = snapshotID
        self.restoredPaths = restoredPaths
        self.removedPaths = removedPaths
    }
}

public actor WorkspaceSnapshotStore {
    private let root: URL
    private let rootPath: String
    private let storageRoot: URL
    private let maxEntryBytes: Int
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        root: URL,
        storageRoot: URL? = nil,
        maxEntryBytes: Int = 8 * 1024 * 1024,
        fileManager: FileManager = .default
    ) {
        let resolvedRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        self.root = resolvedRoot
        self.rootPath = resolvedRoot.path.hasSuffix("/") ? resolvedRoot.path : resolvedRoot.path + "/"
        self.storageRoot = storageRoot ?? Self.defaultStorageRoot(for: resolvedRoot)
        self.maxEntryBytes = max(0, maxEntryBytes)
        self.fileManager = fileManager
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public func createSnapshot(
        paths: [String],
        reason: String,
        id: UUID = UUID(),
        createdAt: Date = Date()
    ) async throws -> WorkspaceMutationSnapshot {
        try Task.checkCancellation()
        let uniquePaths = orderedUnique(paths)
        let snapshotDirectory = directory(for: id)
        let payloadDirectory = snapshotDirectory.appendingPathComponent("files", isDirectory: true)
        try fileManager.createDirectory(at: payloadDirectory, withIntermediateDirectories: true)

        var entries: [WorkspaceSnapshotEntry] = []
        do {
            for path in uniquePaths {
                let target = try resolve(path)
                let entry = try copyEntryIfPresent(path: path, target: target, payloadDirectory: payloadDirectory)
                entries.append(entry)
            }
            let snapshot = WorkspaceMutationSnapshot(
                id: id,
                workspaceRootPath: root.path,
                reason: reason,
                createdAt: createdAt,
                entries: entries)
            try write(snapshot, to: snapshotDirectory)
            return snapshot
        } catch {
            try? fileManager.removeItem(at: snapshotDirectory)
            throw error
        }
    }

    public func snapshot(id: UUID) async throws -> WorkspaceMutationSnapshot {
        let directory = directory(for: id)
        let manifest = directory.appendingPathComponent("manifest.json")
        guard fileManager.fileExists(atPath: manifest.path) else {
            throw WorkspaceSnapshotError.snapshotNotFound(id)
        }
        return try decoder.decode(WorkspaceMutationSnapshot.self, from: Data(contentsOf: manifest))
    }

    public func list(limit: Int = 50) async throws -> [WorkspaceMutationSnapshot] {
        guard fileManager.fileExists(atPath: storageRoot.path) else { return [] }
        let urls = try fileManager.contentsOfDirectory(
            at: storageRoot,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles])
        let snapshots = try urls.compactMap { url -> WorkspaceMutationSnapshot? in
            let manifest = url.appendingPathComponent("manifest.json")
            guard fileManager.fileExists(atPath: manifest.path) else { return nil }
            return try decoder.decode(WorkspaceMutationSnapshot.self, from: Data(contentsOf: manifest))
        }
        return snapshots
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(max(0, limit))
            .map { $0 }
    }

    public func revert(_ id: UUID) async throws -> WorkspaceMutationRevertResult {
        try Task.checkCancellation()
        let snapshot = try await snapshot(id: id)
        let payloadDirectory = directory(for: id).appendingPathComponent("files", isDirectory: true)
        var restored: [String] = []
        var removed: [String] = []

        for entry in snapshot.entries {
            let target = try resolve(entry.relativePath)
            switch entry.kind {
            case .missing:
                if fileManager.fileExists(atPath: target.path) {
                    try fileManager.removeItem(at: target)
                    removed.append(entry.relativePath)
                }
            case .file, .directory:
                let source = payloadDirectory.appendingPathComponent(entry.relativePath)
                guard fileManager.fileExists(atPath: source.path) else {
                    throw WorkspaceSnapshotError.snapshotNotFound(id)
                }
                if fileManager.fileExists(atPath: target.path) {
                    try fileManager.removeItem(at: target)
                }
                try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.copyItem(at: source, to: target)
                restored.append(entry.relativePath)
            }
        }

        return WorkspaceMutationRevertResult(
            snapshotID: id,
            restoredPaths: restored,
            removedPaths: removed)
    }

    private func copyEntryIfPresent(
        path: String,
        target: URL,
        payloadDirectory: URL
    ) throws -> WorkspaceSnapshotEntry {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: target.path, isDirectory: &isDirectory) else {
            return WorkspaceSnapshotEntry(relativePath: path, kind: .missing)
        }

        let values = try target.resourceValues(forKeys: [.isSymbolicLinkKey, .fileSizeKey])
        if values.isSymbolicLink == true {
            throw WorkspaceSnapshotError.unsupportedSymlink(path)
        }

        let destination = payloadDirectory.appendingPathComponent(path)
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)

        if isDirectory.boolValue {
            try fileManager.copyItem(at: target, to: destination)
            return WorkspaceSnapshotEntry(relativePath: path, kind: .directory)
        }

        let bytes = values.fileSize ?? 0
        guard bytes <= maxEntryBytes else {
            throw WorkspaceSnapshotError.fileTooLarge(path: path, bytes: bytes, limit: maxEntryBytes)
        }
        try fileManager.copyItem(at: target, to: destination)
        return WorkspaceSnapshotEntry(relativePath: path, kind: .file, byteCount: bytes)
    }

    private func write(_ snapshot: WorkspaceMutationSnapshot, to directory: URL) throws {
        let data = try encoder.encode(snapshot)
        try data.write(to: directory.appendingPathComponent("manifest.json"), options: [.atomic])
    }

    private func resolve(_ path: String) throws -> URL {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("/") else {
            throw WorkspaceSnapshotError.invalidPath(path)
        }
        let parts = trimmed.split(separator: "/").map(String.init)
        guard !parts.contains("..") else {
            throw WorkspaceSnapshotError.invalidPath(path)
        }
        let candidate = root.appendingPathComponent(trimmed)
        let parent = candidate.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath()
        guard parent.path == root.path || parent.path.hasPrefix(rootPath) else {
            throw WorkspaceSnapshotError.pathEscapesWorkspace(path)
        }
        if fileManager.fileExists(atPath: candidate.path) {
            let resolved = candidate.standardizedFileURL.resolvingSymlinksInPath()
            guard resolved.path == root.path || resolved.path.hasPrefix(rootPath) else {
                throw WorkspaceSnapshotError.pathEscapesWorkspace(path)
            }
            return resolved
        }
        return candidate.standardizedFileURL
    }

    private func directory(for id: UUID) -> URL {
        storageRoot.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private static func defaultStorageRoot(for root: URL) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("Interless", isDirectory: true)
            .appendingPathComponent("WorkspaceSnapshots", isDirectory: true)
            .appendingPathComponent(stableWorkspaceID(root.path), isDirectory: true)
    }

    private static func stableWorkspaceID(_ path: String) -> String {
        let digest = SHA256.hash(data: Data(path.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
