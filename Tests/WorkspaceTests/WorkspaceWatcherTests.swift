import Testing
import Foundation
import Shared
import Workspace

struct WorkspaceWatcherTests {
    private func fe(_ path: String, size: Int = 1, mtime: Int = 1) -> FileEntry {
        FileEntry(relativePath: path, isDirectory: false, sizeBytes: size, modifiedAtEpoch: mtime)
    }

    private func text(_ string: String, _ hash: String) -> LoadedContent {
        .text(content: string, sizeBytes: string.utf8.count, contentHash: hash)
    }

    private func indexer(
        scanner: FakeScanner,
        store: InMemoryIndexStore,
        loader: FakeContentLoader
    ) -> WorkspaceIndexer {
        WorkspaceIndexer(
            root: URL(fileURLWithPath: "/tmp/iftest-watch"),
            scanner: scanner,
            store: store,
            git: FakeGitMetadata(status: GitStatus(isRepository: false, branch: nil, headSHA: nil, entries: [])),
            loader: loader)
    }

    private func firstCompletedProgress(from stream: AsyncStream<IndexingProgress>) async -> IndexingProgress {
        var last = IndexingProgress(phase: .scanning)
        for await progress in stream {
            last = progress
            if progress.phase == .completed { break }
        }
        return last
    }

    @Test func debounceCoalescesEventStormIntoOneIncrementalBatch() async throws {
        let events = FakeWorkspaceEventStream()
        let scanner = FakeScanner(entries: [fe("a.swift", size: 10, mtime: 100), fe("b.swift", size: 10, mtime: 100)])
        let loader = FakeContentLoader(map: [
            "a.swift": text("struct A {}", "ha"),
            "b.swift": text("struct B {}", "hb"),
        ])
        let store = InMemoryIndexStore()
        let watcher = WorkspaceWatcher(
            root: URL(fileURLWithPath: "/tmp/iftest-watch"),
            eventStream: events,
            indexer: indexer(scanner: scanner, store: store, loader: loader),
            debounce: .milliseconds(10))

        let stream = await watcher.start()
        let task = Task { await firstCompletedProgress(from: stream) }
        try await Task.sleep(for: .milliseconds(10))
        events.emit([.init(relativePath: "a.swift", kind: .modified)])
        events.emit([.init(relativePath: "b.swift", kind: .modified)])

        let final = await task.value
        #expect(final.phase == .completed)
        #expect(final.indexed == 2)
        #expect(await store.docs.keys.sorted() == ["a.swift", "b.swift"])
    }

    @Test func deleteEventRemovesFile() async throws {
        let events = FakeWorkspaceEventStream()
        let scanner = FakeScanner(entries: [fe("a.swift")])
        let loader = FakeContentLoader(map: ["a.swift": text("struct A {}", "ha")])
        let store = InMemoryIndexStore()
        let indexer = indexer(scanner: scanner, store: store, loader: loader)
        let full = await indexer.reindex()
        _ = await firstCompletedProgress(from: full)

        let watcher = WorkspaceWatcher(
            root: URL(fileURLWithPath: "/tmp/iftest-watch"),
            eventStream: events,
            indexer: indexer,
            debounce: .milliseconds(10))
        let stream = await watcher.start()
        let task = Task { await firstCompletedProgress(from: stream) }
        try await Task.sleep(for: .milliseconds(10))
        events.emit([.init(relativePath: "a.swift", kind: .deleted)])

        let final = await task.value
        #expect(final.removed == 1)
        #expect(await store.docs["a.swift"] == nil)
    }

    @Test func ignoreFileEventTriggersFullReindexThroughWatcher() async throws {
        let events = FakeWorkspaceEventStream()
        let scanner = FakeScanner(entries: [fe("a.swift"), fe("b.swift")])
        let loader = FakeContentLoader(map: [
            "a.swift": text("struct A {}", "ha"),
            "b.swift": text("struct B {}", "hb"),
        ])
        let store = InMemoryIndexStore()
        let watcher = WorkspaceWatcher(
            root: URL(fileURLWithPath: "/tmp/iftest-watch"),
            eventStream: events,
            indexer: indexer(scanner: scanner, store: store, loader: loader),
            debounce: .milliseconds(10))

        let stream = await watcher.start()
        let task = Task { await firstCompletedProgress(from: stream) }
        try await Task.sleep(for: .milliseconds(10))
        events.emit([.init(relativePath: ".opencodeignore", kind: .modified)])

        let final = await task.value
        #expect(final.phase == .completed)
        #expect(final.indexed == 2)
        #expect(await store.docs.keys.sorted() == ["a.swift", "b.swift"])
    }

    @Test func generatedDirectoryEventsAreDroppedBeforeReindexing() async throws {
        let events = FakeWorkspaceEventStream()
        let scanner = FakeScanner(entries: [fe("a.swift")])
        let loader = FakeContentLoader(map: ["a.swift": text("struct A {}", "ha")])
        let store = InMemoryIndexStore()
        let watcher = WorkspaceWatcher(
            root: URL(fileURLWithPath: "/tmp/iftest-watch"),
            eventStream: events,
            indexer: indexer(scanner: scanner, store: store, loader: loader),
            debounce: .milliseconds(10))

        let stream = await watcher.start()
        let task = Task {
            var iterator = stream.makeAsyncIterator()
            return await iterator.next()
        }
        try await Task.sleep(for: .milliseconds(10))
        events.emit([
            .init(relativePath: ".build/debug/Module.o", kind: .modified),
            .init(relativePath: ".git/index.lock", kind: .modified),
        ])
        try await Task.sleep(for: .milliseconds(50))
        events.finish()

        #expect(await task.value == nil)
        #expect(await store.docs.isEmpty)
    }

    @Test func finishCancelsWatcherStream() async throws {
        let events = FakeWorkspaceEventStream()
        let watcher = WorkspaceWatcher(
            root: URL(fileURLWithPath: "/tmp/iftest-watch"),
            eventStream: events,
            indexer: indexer(
                scanner: FakeScanner(entries: []),
                store: InMemoryIndexStore(),
                loader: FakeContentLoader(map: [:])),
            debounce: .milliseconds(10))

        let stream = await watcher.start()
        let task = Task {
            var count = 0
            for await _ in stream { count += 1 }
            return count
        }
        try await Task.sleep(for: .milliseconds(10))
        events.finish()

        #expect(await task.value == 0)
    }
}
