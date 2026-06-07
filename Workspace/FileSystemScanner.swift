import Foundation
import os
import Shared

/// Recursive, low-memory workspace traversal (ARCHITECTURE.md §9). The only file
/// using `FileManager`'s directory enumerator. Applies nested
/// `.gitignore`/`.opencodeignore` rules and prunes ignored directories.
///
/// Stateless (`Sendable` struct); the actual walk lives in a serially-driven
/// `Walker` so the pull-based `AsyncStream(unfolding:)` stays O(1) in memory.
public struct FileSystemScanner: WorkspaceScanner {

    private let config: WorkspaceConfig

    public init(config: WorkspaceConfig = .default) { self.config = config }

    public func scan(root: URL) async throws -> AsyncStream<FileEntry> {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir) else {
            throw WorkspaceError.rootNotFound(root.path)
        }
        guard isDir.boolValue else {
            throw WorkspaceError.rootNotDirectory(root.path)
        }

        let walker = Walker(root: root, config: config)
        return AsyncStream<FileEntry>(unfolding: {
            if Task.isCancelled { return nil }
            return walker.next()
        })
    }

    /// Resolve a single relative path with the same containment, symlink, and
    /// ignore rules used by the full scanner. This is the hot path for FSEvents
    /// batches and avoids walking the entire workspace for one changed file.
    public func entry(root: URL, relativePath: String) async throws -> FileEntry? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir) else {
            throw WorkspaceError.rootNotFound(root.path)
        }
        guard isDir.boolValue else {
            throw WorkspaceError.rootNotDirectory(root.path)
        }
        guard !relativePath.hasPrefix("/") else { return nil }
        let segments = relativePath.split(separator: "/").map(String.init)
        guard !segments.isEmpty, !segments.contains("..") else { return nil }

        let rootURL = root.standardizedFileURL.resolvingSymlinksInPath()
        let fileURL = rootURL.appendingPathComponent(relativePath)
        let resolvedURL = fileURL.standardizedFileURL.resolvingSymlinksInPath()
        let rootPath = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
        guard resolvedURL.path == rootURL.path || resolvedURL.path.hasPrefix(rootPath) else { return nil }

        var ignore = IgnoreStack()
        var directoryURL = rootURL
        loadIgnoreScope(dirURL: directoryURL, segments: [], into: &ignore)
        for index in 0..<max(0, segments.count - 1) {
            let dirSegments = Array(segments.prefix(index + 1))
            if dirSegments.last == ".git" { return nil }
            if ignore.isIgnored(pathSegments: dirSegments, isDirectory: true) { return nil }
            directoryURL.appendPathComponent(segments[index])
            loadIgnoreScope(dirURL: directoryURL, segments: dirSegments, into: &ignore)
        }
        if ignore.isIgnored(pathSegments: segments, isDirectory: false) { return nil }

        let values = try resolvedURL.resourceValues(forKeys: Set(Walker.keys))
        let isDirectory = values.isDirectory ?? false
        let isSymlink = values.isSymbolicLink ?? false
        if isDirectory || (isSymlink && !config.followSymlinks) { return nil }
        return FileEntry(
            relativePath: relativePath,
            isDirectory: false,
            sizeBytes: values.fileSize ?? 0,
            modifiedAtEpoch: Int((values.contentModificationDate ?? Date(timeIntervalSince1970: 0)).timeIntervalSince1970))
    }
}

/// Drives the lazy directory enumerator and maintains the nested ignore stack.
/// `@unchecked Sendable`: it is only ever touched by the single `unfolding`
/// consumer, one `next()` at a time.
private final class Walker: @unchecked Sendable {
    fileprivate static let keys: [URLResourceKey] = [
        .isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .isSymbolicLinkKey,
    ]

    private let config: WorkspaceConfig
    private let rootPrefix: String  // root path with a trailing "/"
    private let enumerator: FileManager.DirectoryEnumerator?
    private var ignore = IgnoreStack()
    private let log = Logger(subsystem: "dev.interless", category: "workspace")

    init(root: URL, config: WorkspaceConfig) {
        self.config = config
        let rootPath = root.standardizedFileURL.path
        self.rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        self.enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Self.keys,
            options: [],                 // include hidden files (.gitignore etc.)
            errorHandler: { _, _ in true })
        // Root-level ignore files apply to the whole tree (base = []).
        loadIgnoreScope(dirURL: root, segments: [])
    }

    func next() -> FileEntry? {
        guard let enumerator else { return nil }
        while let object = enumerator.nextObject() {
            guard let url = object as? URL else { continue }
            let segments = relativeSegments(url)
            guard let name = segments.last else { continue }
            ignore.prune(for: segments)

            let values = try? url.resourceValues(forKeys: Set(Self.keys))
            let isDirectory = values?.isDirectory ?? false
            let isSymlink = values?.isSymbolicLink ?? false

            // Always skip the .git directory.
            if isDirectory && name == ".git" {
                enumerator.skipDescendants()
                continue
            }
            // Symlink policy.
            if isSymlink && !config.followSymlinks {
                if isDirectory { enumerator.skipDescendants() }
                continue
            }

            if isDirectory {
                loadIgnoreScope(dirURL: url, segments: segments)
                if ignore.isIgnored(pathSegments: segments, isDirectory: true) {
                    enumerator.skipDescendants()
                }
                continue // directories are never yielded; they only drive pruning + scopes
            }

            if ignore.isIgnored(pathSegments: segments, isDirectory: false) {
                continue
            }

            let size = values?.fileSize ?? 0
            let mtime = Int((values?.contentModificationDate ?? Date(timeIntervalSince1970: 0)).timeIntervalSince1970)
            return FileEntry(
                relativePath: segments.joined(separator: "/"),
                isDirectory: false,
                sizeBytes: size,
                modifiedAtEpoch: mtime)
        }
        return nil
    }

    private func relativeSegments(_ url: URL) -> [String] {
        let path = url.standardizedFileURL.path
        let relative = path.hasPrefix(rootPrefix) ? String(path.dropFirst(rootPrefix.count)) : path
        return relative.split(separator: "/").map(String.init)
    }

    private func loadIgnoreScope(dirURL: URL, segments: [String]) {
        FileSystemScanner.loadIgnoreScope(
            dirURL: dirURL,
            segments: segments,
            ignoreFileNames: config.ignoreFileNames,
            maxIgnoreFileSizeBytes: config.maxIgnoreFileSizeBytes,
            into: &ignore)
    }
}

private extension FileSystemScanner {
    static func loadIgnoreScope(
        dirURL: URL,
        segments: [String],
        ignoreFileNames: [String],
        maxIgnoreFileSizeBytes: Int,
        into ignore: inout IgnoreStack
    ) {
        var contents: [String] = []
        for name in ignoreFileNames {
            let fileURL = dirURL.appendingPathComponent(name)
            if let text = boundedText(at: fileURL, maxBytes: maxIgnoreFileSizeBytes) {
                contents.append(text)
            }
        }
        guard !contents.isEmpty else { return }
        ignore.add(.init(baseSegments: segments, rules: IgnoreRules.parse(contents)))
    }

    static func boundedText(at url: URL, maxBytes: Int) -> String? {
        guard maxBytes > 0 else { return nil }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard size <= maxBytes else { return nil }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maxBytes + 1), data.count <= maxBytes else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func loadIgnoreScope(dirURL: URL, segments: [String], into ignore: inout IgnoreStack) {
        Self.loadIgnoreScope(
            dirURL: dirURL,
            segments: segments,
            ignoreFileNames: config.ignoreFileNames,
            maxIgnoreFileSizeBytes: config.maxIgnoreFileSizeBytes,
            into: &ignore)
    }
}
