import Foundation
import os
import Shared
import Core

/// Coordinates a workspace re-index: scan → filter → load → upsert → prune →
/// record git metadata (ARCHITECTURE.md §9). Owns no MLX/GRDB types — the scanner,
/// index store, git provider, and loader are injected as protocols (no singletons,
/// §17). Mirrors `InferenceController`'s actor + return-stream-synchronously +
/// `AsyncSemaphore` + cancellation patterns.
public actor WorkspaceIndexer {

    private let root: URL
    private let scanner: any WorkspaceScanner
    private let store: any WorkspaceIndexStore
    private let git: any GitMetadataProvider
    private let loader: any FileContentLoader
    private let extractor: any CodeStructureExtractor
    private let config: WorkspaceConfig
    private let resourceBudget: ResourceBudget
    private let metrics: MetricsRecorder?
    private let reindexGate = AsyncSemaphore(value: 1) // serialize full re-indexes
    private let log = Logger(subsystem: "dev.interless", category: "indexing")

    public init(
        root: URL,
        scanner: any WorkspaceScanner,
        store: any WorkspaceIndexStore,
        git: any GitMetadataProvider,
        loader: any FileContentLoader,
        extractor: any CodeStructureExtractor = SwiftCodeStructureExtractor(),
        config: WorkspaceConfig = .default,
        resourceBudget: ResourceBudget? = nil,
        metrics: MetricsRecorder? = nil
    ) {
        self.root = root
        self.scanner = scanner
        self.store = store
        self.git = git
        self.loader = loader
        self.extractor = extractor
        if let resourceBudget {
            self.resourceBudget = resourceBudget
            var adjusted = config
            adjusted.maxFileSizeBytes = resourceBudget.maxIndexedFileSizeBytes
            self.config = adjusted
        } else {
            self.resourceBudget = ResourceBudget.balanced
            self.config = config
        }
        self.metrics = metrics
    }

    /// Full re-index. Returns the progress stream **synchronously**; the work runs
    /// in a spawned task and continues even if the progress stream isn't consumed.
    public func reindex() -> AsyncStream<IndexingProgress> {
        let root = self.root
        let scanner = self.scanner
        let store = self.store
        let git = self.git
        let loader = self.loader
        let extractor = self.extractor
        let config = self.config
        let metrics = self.metrics
        let gate = self.reindexGate
        let log = self.log

        return AsyncStream(IndexingProgress.self, bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task {
                do { try await gate.wait() }
                catch { continuation.finish(); return }
                defer { gate.signal() }

                var progress = IndexingProgress(phase: .scanning)
                do {
                    // Memory is O(batch), not O(repo): per-path indexed lookups replace
                    // the previous load-everything dict, and deletions are pruned in
                    // SQL via the `seenAt` scan epoch instead of an all-paths set diff.
                    let scanStart = try await store.beginScan()
                    var pendingUpserts: [IndexedFile] = []
                    var pendingSeen: [String] = []
                    continuation.yield(progress)

                    let stream = try await scanner.scan(root: root)
                    progress.phase = .indexing
                    for await entry in stream where !entry.isDirectory {
                        try Task.checkCancellation()
                        progress.scanned += 1

                        let prior = try await store.fileState(path: entry.relativePath)
                        // Cheap fast-path: size + mtime unchanged ⇒ skip (no read/hash).
                        if let prior, prior.sizeBytes == entry.sizeBytes, prior.modifiedAtEpoch == entry.modifiedAtEpoch {
                            progress.skipped += 1
                            pendingSeen.append(entry.relativePath)
                            if pendingSeen.count >= 512 {
                                try await store.markSeen(paths: pendingSeen, seenAt: scanStart)
                                pendingSeen.removeAll(keepingCapacity: true)
                            }
                            Self.throttledYield(&progress, continuation)
                            continue
                        }

                        if let file = try await Self.process(
                            entry: entry,
                            prior: prior,
                            root: root,
                            store: store,
                            loader: loader,
                            extractor: extractor,
                            config: config,
                            metrics: metrics,
                            progress: &progress,
                            log: log) {
                            pendingUpserts.append(file)
                            if pendingUpserts.count >= 128 {
                                try await store.upsertBatch(pendingUpserts, seenAt: scanStart)
                                pendingUpserts.removeAll(keepingCapacity: true)
                            }
                        } else {
                            // Touched (updateState already stamped seenAt) or unreadable —
                            // stamp it so the prune below keeps the existing entry.
                            pendingSeen.append(entry.relativePath)
                            if pendingSeen.count >= 512 {
                                try await store.markSeen(paths: pendingSeen, seenAt: scanStart)
                                pendingSeen.removeAll(keepingCapacity: true)
                            }
                        }
                        progress.lastPath = entry.relativePath
                        Self.throttledYield(&progress, continuation)
                    }
                    try await store.upsertBatch(pendingUpserts, seenAt: scanStart)
                    try await store.markSeen(paths: pendingSeen, seenAt: scanStart)

                    // Prune deletions — only valid after a complete scan.
                    progress.phase = .pruning
                    continuation.yield(progress)
                    progress.removed += try await store.pruneUnseen(olderThan: scanStart)

                    // Record git metadata.
                    let status = await git.snapshot(root: root)
                    try await store.setMetadata(key: "git.branch", value: status.branch)
                    try await store.setMetadata(key: "git.head", value: status.headSHA)
                    try await store.setMetadata(key: "lastFullScanEpoch", value: String(Int(Date().timeIntervalSince1970)))

                    progress.phase = .completed
                    continuation.yield(progress)
                    continuation.finish()
                } catch is CancellationError {
                    progress.phase = .cancelled
                    continuation.yield(progress)
                    continuation.finish()
                } catch {
                    log.error("reindex failed: \(String(describing: error), privacy: .public)")
                    progress.phase = .failed
                    continuation.yield(progress)
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Event-driven incremental reindex. Falls back to a full scan when a batch
    /// can affect more than the named file (directory/root/rename/ignore-file).
    public func reindex(events: [WorkspaceEvent]) -> AsyncStream<IndexingProgress> {
        guard !Self.requiresFullReindex(events, config: config) else {
            return reindex()
        }

        let root = self.root
        let scanner = self.scanner
        let store = self.store
        let git = self.git
        let loader = self.loader
        let extractor = self.extractor
        let config = self.config
        let metrics = self.metrics
        let gate = self.reindexGate
        let log = self.log

        return AsyncStream(IndexingProgress.self, bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task {
                do { try await gate.wait() }
                catch { continuation.finish(); return }
                defer { gate.signal() }

                var progress = IndexingProgress(phase: .indexing)
                do {
                    for path in Self.uniquePaths(events) {
                        try Task.checkCancellation()
                        progress.scanned += 1
                        progress.lastPath = path

                        if events.contains(where: { $0.relativePath == path && $0.kind == .deleted }) {
                            try await store.removeFile(path: path)
                            progress.removed += 1
                            Self.throttledYield(&progress, continuation)
                            continue
                        }

                        guard let entry = try await Self.findIncludedEntry(path, root: root, scanner: scanner) else {
                            try await store.removeFile(path: path)
                            progress.removed += 1
                            Self.throttledYield(&progress, continuation)
                            continue
                        }

                        let prior = try await store.fileState(path: path)
                        if let prior, prior.sizeBytes == entry.sizeBytes, prior.modifiedAtEpoch == entry.modifiedAtEpoch {
                            progress.skipped += 1
                            Self.throttledYield(&progress, continuation)
                            continue
                        }

                        if let file = try await Self.process(
                            entry: entry,
                            prior: prior,
                            root: root,
                            store: store,
                            loader: loader,
                            extractor: extractor,
                            config: config,
                            metrics: metrics,
                            progress: &progress,
                            log: log) {
                            try await store.upsertBatch([file], seenAt: Int(Date().timeIntervalSince1970))
                        }
                        Self.throttledYield(&progress, continuation)
                    }

                    let status = await git.snapshot(root: root)
                    try await store.setMetadata(key: "git.branch", value: status.branch)
                    try await store.setMetadata(key: "git.head", value: status.headSHA)
                    try await store.setMetadata(key: "lastIncrementalScanEpoch", value: String(Int(Date().timeIntervalSince1970)))

                    progress.phase = .completed
                    continuation.yield(progress)
                    continuation.finish()
                } catch is CancellationError {
                    progress.phase = .cancelled
                    continuation.yield(progress)
                    continuation.finish()
                } catch {
                    log.error("incremental reindex failed: \(String(describing: error), privacy: .public)")
                    progress.phase = .failed
                    continuation.yield(progress)
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Search the index, then enrich the (bounded) hits with snippets read from
    /// disk (the index is contentless, §12).
    public func search(_ query: String, limit: Int = 50) async throws -> [SearchHit] {
        let hits = try await store.search(query, limit: limit)
        let budget = resourceBudget
        let metrics = self.metrics
        let root = self.root
        return await withTaskGroup(of: SearchHit.self) { group in
            for hit in hits {
                group.addTask {
                    var hit = hit
                    let fileURL = root.appendingPathComponent(hit.relativePath)
                    if let result = try? SnippetExtractor.snippet(
                        fileAt: fileURL,
                        query: query,
                        maxReadBytes: budget.maxSearchSnippetReadBytes
                    ) {
                        hit.snippet = result.snippet
                        await metrics?.record(.init(
                            kind: .searchSnippetBytesRead,
                            unit: .bytes,
                            value: Double(result.bytesRead),
                            metadata: ["path": hit.relativePath]))
                    }
                    return hit
                }
            }
            var enriched: [SearchHit] = []
            for await hit in group {
                enriched.append(hit)
            }
            let order = Dictionary(uniqueKeysWithValues: hits.enumerated().map { ($0.element.relativePath, $0.offset) })
            return enriched.sorted { (order[$0.relativePath] ?? 0) < (order[$1.relativePath] ?? 0) }
        }
    }

    public func gitStatus() async -> GitStatus {
        await git.snapshot(root: root)
    }

    // MARK: - Private helpers (static; capture nothing)

    private static func process(
        entry: FileEntry,
        prior: FileIndexState?,
        root: URL,
        store: any WorkspaceIndexStore,
        loader: any FileContentLoader,
        extractor: any CodeStructureExtractor,
        config: WorkspaceConfig,
        metrics: MetricsRecorder?,
        progress: inout IndexingProgress,
        log: Logger
    ) async throws -> IndexedFile? {
        let fileURL = root.appendingPathComponent(entry.relativePath)
        let loaded = await loader.load(fileAt: fileURL, config: config)
        switch loaded {
        case let .text(content, _, hash):
            await metrics?.record(.init(kind: .indexBytesRead, unit: .bytes, value: Double(entry.sizeBytes), metadata: ["path": entry.relativePath]))
            let structure = extractor.extract(from: content, relativePath: entry.relativePath)
            return try await Self.fileToUpsert(
                store, prior: prior, entry: entry, hash: hash,
                content: content, structure: structure, progress: &progress)
        case let .binary(_, hash):
            await metrics?.record(.init(kind: .indexBytesRead, unit: .bytes, value: Double(entry.sizeBytes), metadata: ["path": entry.relativePath]))
            return try await Self.fileToUpsert(
                store, prior: prior, entry: entry, hash: hash,
                content: nil, structure: CodeStructure(), progress: &progress)
        case .skippedTooLarge:
            await metrics?.record(.init(kind: .indexSkippedTooLargeCount, unit: .count, value: 1, metadata: ["path": entry.relativePath]))
            return try await Self.fileToUpsert(
                store, prior: prior, entry: entry, hash: "oversize:\(entry.sizeBytes)",
                content: nil, structure: CodeStructure(), progress: &progress)
        case let .unreadable(reason):
            log.notice("skip unreadable \(entry.relativePath, privacy: .public): \(reason, privacy: .public)")
            return nil
        }
    }

    private static func requiresFullReindex(_ events: [WorkspaceEvent], config: WorkspaceConfig) -> Bool {
        events.contains { event in
            guard let path = event.relativePath else { return true }
            if event.kind == .renamed || event.kind == .unknown || event.isDirectory { return true }
            return config.ignoreFileNames.contains { path == $0 || path.hasSuffix("/\($0)") }
        }
    }

    private static func uniquePaths(_ events: [WorkspaceEvent]) -> [String] {
        var seen = Set<String>()
        return events.compactMap(\.relativePath).filter { seen.insert($0).inserted }
    }

    private static func findIncludedEntry(
        _ relativePath: String,
        root: URL,
        scanner: any WorkspaceScanner
    ) async throws -> FileEntry? {
        if let fileSystemScanner = scanner as? FileSystemScanner {
            return try await fileSystemScanner.entry(root: root, relativePath: relativePath)
        }
        let stream = try await scanner.scan(root: root)
        for await entry in stream where entry.relativePath == relativePath {
            return entry
        }
        return nil
    }

    /// Decides what to write for a scanned file: `nil` when content is unchanged
    /// (after refreshing size/mtime state for a `touch`), else the `IndexedFile`
    /// for the caller to upsert — batched on the full-scan path.
    private static func fileToUpsert(
        _ store: any WorkspaceIndexStore,
        prior: FileIndexState?,
        entry: FileEntry,
        hash: String,
        content: String?,
        structure: CodeStructure,
        progress: inout IndexingProgress
    ) async throws -> IndexedFile? {
        if let prior, prior.contentHash == hash {
            if prior.sizeBytes != entry.sizeBytes || prior.modifiedAtEpoch != entry.modifiedAtEpoch {
                try await store.updateState(FileIndexState(
                    relativePath: entry.relativePath,
                    sizeBytes: entry.sizeBytes,
                    modifiedAtEpoch: entry.modifiedAtEpoch,
                    contentHash: hash))
            }
            progress.skipped += 1 // content unchanged (e.g. a `touch`)
            return nil
        }
        // Store the scanner's stat size (not the loader's byte count) so the
        // incremental size/mtime fast-path stays consistent across re-scans.
        progress.indexed += 1
        return IndexedFile(
            relativePath: entry.relativePath,
            sizeBytes: entry.sizeBytes,
            modifiedAtEpoch: entry.modifiedAtEpoch,
            contentHash: hash,
            content: content,
            symbols: structure.symbols,
            comments: structure.comments,
            references: structure.references)
    }

    private static func throttledYield(
        _ progress: inout IndexingProgress,
        _ continuation: AsyncStream<IndexingProgress>.Continuation
    ) {
        if progress.scanned % 64 == 0 { continuation.yield(progress) }
    }
}
