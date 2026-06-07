import Testing
import Foundation
import Shared
import Core
import Workspace

struct WorkspaceIndexerTests {

    // MARK: helpers

    private func fe(_ path: String, size: Int = 1, mtime: Int = 1) -> FileEntry {
        FileEntry(relativePath: path, isDirectory: false, sizeBytes: size, modifiedAtEpoch: mtime)
    }
    private func text(_ string: String, _ hash: String) -> LoadedContent {
        .text(content: string, sizeBytes: string.utf8.count, contentHash: hash)
    }
    private func makeIndexer(
        scanner: FakeScanner,
        store: InMemoryIndexStore,
        loader: FakeContentLoader,
        git: FakeGitMetadata = FakeGitMetadata(status: GitStatus(isRepository: true, branch: "main", headSHA: "abc1234", entries: []))
    ) -> WorkspaceIndexer {
        WorkspaceIndexer(
            root: URL(fileURLWithPath: "/tmp/iftest-fake-ws"),
            scanner: scanner, store: store, git: git, loader: loader)
    }
    private func run(_ indexer: WorkspaceIndexer) async -> IndexingProgress {
        let stream = await indexer.reindex()
        var last = IndexingProgress(phase: .scanning)
        for await progress in stream { last = progress }
        return last
    }
    private func run(_ indexer: WorkspaceIndexer, events: [WorkspaceEvent]) async -> IndexingProgress {
        let stream = await indexer.reindex(events: events)
        var last = IndexingProgress(phase: .scanning)
        for await progress in stream { last = progress }
        return last
    }

    // MARK: tests

    @Test func fullIndexIndexesAllFiles() async throws {
        let scanner = FakeScanner(entries: [fe("a.swift"), fe("b.swift")])
        let loader = FakeContentLoader(map: ["a.swift": text("alpha", "ha"), "b.swift": text("beta", "hb")])
        let store = InMemoryIndexStore()
        let final = await run(makeIndexer(scanner: scanner, store: store, loader: loader))
        #expect(final.phase == .completed)
        #expect(final.indexed == 2)
        #expect(await store.docs.count == 2)
    }

    @Test func incrementalSkipsUnchanged() async throws {
        let scanner = FakeScanner(entries: [fe("a.swift", size: 10, mtime: 100)])
        let loader = FakeContentLoader(map: ["a.swift": text("hello", "h1")])
        let store = InMemoryIndexStore()
        let indexer = makeIndexer(scanner: scanner, store: store, loader: loader)
        _ = await run(indexer)
        #expect(await store.upsertCount == 1)

        let final = await run(indexer) // identical entries + stored states
        #expect(final.skipped == 1)
        #expect(final.indexed == 0)
        #expect(await store.upsertCount == 1) // no new upsert
    }

    @Test func changedFileIsReindexed() async throws {
        let scanner = FakeScanner(entries: [fe("a.swift", size: 10, mtime: 100)])
        let loader = FakeContentLoader(map: ["a.swift": text("hello", "h1")])
        let store = InMemoryIndexStore()
        let indexer = makeIndexer(scanner: scanner, store: store, loader: loader)
        _ = await run(indexer)

        await scanner.setEntries([fe("a.swift", size: 12, mtime: 200)])
        await loader.setMap(["a.swift": text("changed", "h2")])
        let final = await run(indexer)
        #expect(final.indexed == 1)
        #expect(final.skipped == 0)
    }

    @Test func touchedFileWithSameContentSkips() async throws {
        let scanner = FakeScanner(entries: [fe("a.swift", size: 10, mtime: 100)])
        let loader = FakeContentLoader(map: ["a.swift": text("hello", "h1")])
        let store = InMemoryIndexStore()
        let indexer = makeIndexer(scanner: scanner, store: store, loader: loader)
        _ = await run(indexer)

        await scanner.setEntries([fe("a.swift", size: 10, mtime: 999)]) // mtime changed only
        await loader.setMap(["a.swift": text("hello", "h1")])           // same hash
        let final = await run(indexer)
        #expect(final.indexed == 0)
        #expect(final.skipped == 1)
        #expect(await store.docs["a.swift"]?.modifiedAtEpoch == 999)
    }

    @Test func deletedFileIsPruned() async throws {
        let scanner = FakeScanner(entries: [fe("a.swift"), fe("b.swift")])
        let loader = FakeContentLoader(map: ["a.swift": text("x", "ha"), "b.swift": text("y", "hb")])
        let store = InMemoryIndexStore()
        let indexer = makeIndexer(scanner: scanner, store: store, loader: loader)
        _ = await run(indexer)
        #expect(await store.docs.count == 2)

        await scanner.setEntries([fe("a.swift")]) // b.swift gone
        let final = await run(indexer)
        #expect(final.removed == 1)
        #expect(await store.removedPaths == ["b.swift"])
        #expect(await store.docs.keys.sorted() == ["a.swift"])
    }

    @Test func recordsGitMetadata() async throws {
        let store = InMemoryIndexStore()
        let indexer = makeIndexer(
            scanner: FakeScanner(entries: []),
            store: store,
            loader: FakeContentLoader(map: [:]),
            git: FakeGitMetadata(status: GitStatus(isRepository: true, branch: "feature/x", headSHA: "deadbeef", entries: [])))
        _ = await run(indexer)
        #expect(try await store.metadata(key: "git.branch") == "feature/x")
        #expect(try await store.metadata(key: "git.head") == "deadbeef")
    }

    @Test func searchPassesThroughToStore() async throws {
        let scanner = FakeScanner(entries: [fe("Auth.swift")])
        let loader = FakeContentLoader(map: ["Auth.swift": text("authenticate user", "h")])
        let store = InMemoryIndexStore()
        let indexer = makeIndexer(scanner: scanner, store: store, loader: loader)
        _ = await run(indexer)
        let hits = try await indexer.search("authenticate", limit: 10)
        #expect(hits.contains { $0.relativePath == "Auth.swift" })
    }

    @Test func swiftFilesStoreStructuredFields() async throws {
        let scanner = FakeScanner(entries: [fe("Auth.swift")])
        let loader = FakeContentLoader(map: ["Auth.swift": text("import Foundation\nstruct Authenticator { func login() { print(\"ok\") } }", "h")])
        let store = InMemoryIndexStore()
        let indexer = makeIndexer(scanner: scanner, store: store, loader: loader)
        _ = await run(indexer)

        let file = try #require(await store.docs["Auth.swift"])
        #expect(file.symbols.contains { $0.name == "Authenticator" && $0.kind == "type" })
        #expect(file.symbols.contains { $0.name == "login" && $0.kind == "function" })
        #expect(file.references.contains { $0.name == "Foundation" && $0.kind == "import" })
        #expect(file.references.contains { $0.name == "print" && $0.kind == "call" })
    }

    @Test func changedSwiftFileRefreshesStructuredFieldsFromEvents() async throws {
        let scanner = FakeScanner(entries: [fe("Auth.swift", size: 10, mtime: 100)])
        let loader = FakeContentLoader(map: ["Auth.swift": text("struct OldAuth {}", "h1")])
        let store = InMemoryIndexStore()
        let indexer = makeIndexer(scanner: scanner, store: store, loader: loader)
        _ = await run(indexer)

        await scanner.setEntries([fe("Auth.swift", size: 11, mtime: 200)])
        await loader.setMap(["Auth.swift": text("struct NewAuth { func refresh() {} }", "h2")])
        let final = await run(indexer, events: [.init(relativePath: "Auth.swift", kind: .modified)])

        #expect(final.phase == .completed)
        #expect(final.indexed == 1)
        let file = try #require(await store.docs["Auth.swift"])
        #expect(file.symbols.contains { $0.name == "NewAuth" })
        #expect(file.symbols.contains { $0.name == "refresh" })
        #expect(!file.symbols.contains { $0.name == "OldAuth" })
    }

    @Test func touchedSwiftFileOnlyUpdatesStateFromEvents() async throws {
        let scanner = FakeScanner(entries: [fe("Auth.swift", size: 10, mtime: 100)])
        let loader = FakeContentLoader(map: ["Auth.swift": text("struct Auth {}", "h1")])
        let store = InMemoryIndexStore()
        let indexer = makeIndexer(scanner: scanner, store: store, loader: loader)
        _ = await run(indexer)

        await scanner.setEntries([fe("Auth.swift", size: 10, mtime: 200)])
        await loader.setMap(["Auth.swift": text("struct Auth {}", "h1")])
        let final = await run(indexer, events: [.init(relativePath: "Auth.swift", kind: .modified)])

        #expect(final.indexed == 0)
        #expect(final.skipped == 1)
        #expect(await store.upsertCount == 1)
        #expect(await store.updateStateCount == 1)
        #expect(await store.docs["Auth.swift"]?.modifiedAtEpoch == 200)
    }

    @Test func eventDeletedFileRemovesStructuredFields() async throws {
        let scanner = FakeScanner(entries: [fe("Auth.swift")])
        let loader = FakeContentLoader(map: ["Auth.swift": text("struct Auth {}", "h")])
        let store = InMemoryIndexStore()
        let indexer = makeIndexer(scanner: scanner, store: store, loader: loader)
        _ = await run(indexer)

        let final = await run(indexer, events: [.init(relativePath: "Auth.swift", kind: .deleted)])

        #expect(final.removed == 1)
        #expect(await store.docs["Auth.swift"] == nil)
        #expect(await store.removedPaths == ["Auth.swift"])
    }

    @Test func nonSwiftFilesKeepStructuredFieldsEmpty() async throws {
        let scanner = FakeScanner(entries: [fe("README.md")])
        let loader = FakeContentLoader(map: ["README.md": text("struct Auth { func login() {} }", "h")])
        let store = InMemoryIndexStore()
        let indexer = makeIndexer(scanner: scanner, store: store, loader: loader)
        _ = await run(indexer)

        let file = try #require(await store.docs["README.md"])
        #expect(file.symbols.isEmpty)
        #expect(file.comments.isEmpty)
        #expect(file.references.isEmpty)
    }

    @Test func ignoreFileEventFallsBackToFullReindex() async throws {
        let scanner = FakeScanner(entries: [fe("a.swift"), fe("b.swift")])
        let loader = FakeContentLoader(map: [
            "a.swift": text("struct A {}", "ha"),
            "b.swift": text("struct B {}", "hb"),
        ])
        let store = InMemoryIndexStore()
        let indexer = makeIndexer(scanner: scanner, store: store, loader: loader)

        let final = await run(indexer, events: [.init(relativePath: ".gitignore", kind: .modified)])

        #expect(final.phase == .completed)
        #expect(final.indexed == 2)
        #expect(await store.docs.keys.sorted() == ["a.swift", "b.swift"])
    }
}
