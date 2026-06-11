import Foundation
import Testing
import GRDB
import Core
import Shared
@testable import Persistence

// In-memory GRDB (real SQL + FTS5), no files/network.

struct PersistenceStoreTests {

    private func makeStore() throws -> GRDBWorkspaceIndexStore {
        try PersistenceBootstrap.inMemoryStore()
    }

    @Test func upsertThenSearchFindsFile() async throws {
        let store = try makeStore()
        try await store.upsert(IndexedFile(relativePath: "Auth.swift", sizeBytes: 20, modifiedAtEpoch: 1, contentHash: "h1", content: "func authenticate() {}"))
        let hits = try await store.search("authenticate", limit: 10)
        #expect(hits.contains { $0.relativePath == "Auth.swift" })
    }

    @Test func filenameMatchesRankAheadOfBodyMatches() async throws {
        let store = try makeStore()
        try await store.upsert(IndexedFile(relativePath: "network.swift", sizeBytes: 1, modifiedAtEpoch: 1, contentHash: "a", content: "let x = 1"))
        try await store.upsert(IndexedFile(relativePath: "other.swift", sizeBytes: 1, modifiedAtEpoch: 1, contentHash: "b", content: "a network call here"))
        let paths = try await store.search("network", limit: 10).map(\.relativePath)
        let iNetwork = try #require(paths.firstIndex(of: "network.swift"))
        let iOther = try #require(paths.firstIndex(of: "other.swift"))
        #expect(iNetwork < iOther) // filename column is bm25-weighted 5x
    }

    @Test func multiTokenRequiresAllTokens() async throws {
        let store = try makeStore()
        try await store.upsert(IndexedFile(relativePath: "a.swift", sizeBytes: 1, modifiedAtEpoch: 1, contentHash: "a", content: "alpha beta"))
        try await store.upsert(IndexedFile(relativePath: "b.swift", sizeBytes: 1, modifiedAtEpoch: 1, contentHash: "b", content: "alpha only"))
        let hits = try await store.search("alpha beta", limit: 10)
        #expect(hits.map(\.relativePath) == ["a.swift"])
    }

    @Test func searchRespectsLimit() async throws {
        let store = try makeStore()
        for i in 0..<5 {
            try await store.upsert(IndexedFile(relativePath: "f\(i).swift", sizeBytes: 1, modifiedAtEpoch: 1, contentHash: "h\(i)", content: "common token"))
        }
        #expect(try await store.search("common", limit: 3).count == 3)
    }

    @Test func removeDropsFromSearch() async throws {
        let store = try makeStore()
        try await store.upsert(IndexedFile(relativePath: "a.swift", sizeBytes: 1, modifiedAtEpoch: 1, contentHash: "a", content: "findme"))
        #expect(try await store.search("findme", limit: 10).count == 1)
        try await store.removeFile(path: "a.swift")
        #expect(try await store.search("findme", limit: 10).isEmpty)
    }

    @Test func updateReplacesIndexedContent() async throws {
        let store = try makeStore()
        try await store.upsert(IndexedFile(relativePath: "a.swift", sizeBytes: 1, modifiedAtEpoch: 1, contentHash: "v1", content: "alpha"))
        try await store.upsert(IndexedFile(relativePath: "a.swift", sizeBytes: 1, modifiedAtEpoch: 2, contentHash: "v2", content: "beta"))
        #expect(try await store.search("alpha", limit: 10).isEmpty)
        #expect(try await store.search("beta", limit: 10).count == 1)
    }

    @Test func knownFileStatesReflectsUpserts() async throws {
        let store = try makeStore()
        try await store.upsert(IndexedFile(relativePath: "a.swift", sizeBytes: 7, modifiedAtEpoch: 99, contentHash: "hh", content: "x"))
        let states = try await store.knownFileStates()
        #expect(states.count == 1)
        #expect(states.first?.relativePath == "a.swift")
        #expect(states.first?.modifiedAtEpoch == 99)
        #expect(states.first?.contentHash == "hh")
    }

    @Test func binaryFilesIndexedByFilenameOnly() async throws {
        let store = try makeStore()
        try await store.upsert(IndexedFile(relativePath: "diagram.png", sizeBytes: 100, modifiedAtEpoch: 1, contentHash: "h", content: nil))
        #expect(try await store.search("diagram", limit: 10).contains { $0.relativePath == "diagram.png" })
    }

    @Test func metadataRoundTrips() async throws {
        let store = try makeStore()
        #expect(try await store.metadata(key: "git.branch") == nil)
        try await store.setMetadata(key: "git.branch", value: "main")
        #expect(try await store.metadata(key: "git.branch") == "main")
        try await store.setMetadata(key: "git.branch", value: nil)
        #expect(try await store.metadata(key: "git.branch") == nil)
    }

    /// §12: the contentless FTS5 index keeps NO copy of file text.
    @Test func contentlessIndexStoresNoBodyText() async throws {
        let queue = try DatabaseQueue() // in-memory
        try WorkspaceSchema.makeMigrator().migrate(queue)
        let store = GRDBWorkspaceIndexStore(dbWriter: queue)
        try await store.upsert(IndexedFile(relativePath: "a.swift", sizeBytes: 1, modifiedAtEpoch: 1, contentHash: "h", content: "ZEBRAUNIQUE secret body text"))

        // The FTS table returns no column text (contentless): body is NULL.
        let body = try await queue.read { db in
            try String.fetchOne(db, sql: "SELECT body FROM file_fts LIMIT 1")
        }
        #expect(body == nil || body == "")

        // …yet the content is still searchable via the inverted index.
        #expect(try await store.search("ZEBRAUNIQUE", limit: 10).contains { $0.relativePath == "a.swift" })
    }

    @Test func structuredFieldsAreSearchableAndLocationsPersisted() async throws {
        let queue = try DatabaseQueue()
        try WorkspaceSchema.makeMigrator().migrate(queue)
        let store = GRDBWorkspaceIndexStore(dbWriter: queue)
        try await store.upsert(IndexedFile(
            relativePath: "Auth.swift",
            sizeBytes: 1,
            modifiedAtEpoch: 1,
            contentHash: "h",
            content: "let x = 1",
            symbols: [CodeSymbol(name: "Authenticator", kind: "type", line: 3, column: 8)],
            comments: ["verifies credentials before issuing token"],
            references: [CodeReference(name: "Foundation", kind: "import", line: 1, column: 8)]))

        #expect(try await store.search("Authenticator", limit: 10).map(\.relativePath) == ["Auth.swift"])
        #expect(try await store.search("credentials", limit: 10).map(\.relativePath) == ["Auth.swift"])
        #expect(try await store.search("Foundation", limit: 10).map(\.relativePath) == ["Auth.swift"])

        let symbol: Row? = try queue.read { db in
            return try Row.fetchOne(db, sql: "SELECT name, kind, line, column FROM file_symbol WHERE path = ?", arguments: ["Auth.swift"])
        }
        #expect(symbol?["name"] as String? == "Authenticator")
        #expect(symbol?["kind"] as String? == "type")
        #expect(symbol?["line"] as Int? == 3)
        #expect(symbol?["column"] as Int? == 8)

        let reference: Row? = try queue.read { db in
            return try Row.fetchOne(db, sql: "SELECT name, kind FROM file_reference WHERE path = ?", arguments: ["Auth.swift"])
        }
        #expect(reference?["name"] as String? == "Foundation")
        #expect(reference?["kind"] as String? == "import")
    }

    @Test func structuredColumnsRankAheadOfBodyMatches() async throws {
        let store = try makeStore()
        try await store.upsert(IndexedFile(
            relativePath: "symbol.swift",
            sizeBytes: 1,
            modifiedAtEpoch: 1,
            contentHash: "a",
            content: "let x = 1",
            symbols: [CodeSymbol(name: "Needle", kind: "type", line: 1, column: 1)]))
        try await store.upsert(IndexedFile(
            relativePath: "body.swift",
            sizeBytes: 1,
            modifiedAtEpoch: 1,
            contentHash: "b",
            content: "Needle appears here"))

        let paths = try await store.search("Needle", limit: 10).map(\.relativePath)
        let iSymbol = try #require(paths.firstIndex(of: "symbol.swift"))
        let iBody = try #require(paths.firstIndex(of: "body.swift"))
        #expect(iSymbol < iBody)
    }

    @Test func contentlessIndexStoresNoRecoverableStructuredOrBodyText() async throws {
        let queue = try DatabaseQueue()
        try WorkspaceSchema.makeMigrator().migrate(queue)
        let store = GRDBWorkspaceIndexStore(dbWriter: queue)
        try await store.upsert(IndexedFile(
            relativePath: "a.swift",
            sizeBytes: 1,
            modifiedAtEpoch: 1,
            contentHash: "h",
            content: "BODYSECRET",
            symbols: [CodeSymbol(name: "SYMBOLSECRET", kind: "type", line: 1, column: 1)],
            comments: ["COMMENTSECRET"],
            references: [CodeReference(name: "REFERENCESECRET", kind: "type", line: 1, column: 1)]))

        let row: Row? = try queue.read { db in
            return try Row.fetchOne(db, sql: "SELECT body, symbols, comments, \"references\" FROM file_fts LIMIT 1")
        }
        #expect(row?["body"] as String? == nil || row?["body"] as String? == "")
        #expect(row?["symbols"] as String? == nil || row?["symbols"] as String? == "")
        #expect(row?["comments"] as String? == nil || row?["comments"] as String? == "")
        #expect(row?["references"] as String? == nil || row?["references"] as String? == "")

        #expect(try await store.search("SYMBOLSECRET", limit: 10).count == 1)
        #expect(try await store.search("COMMENTSECRET", limit: 10).count == 1)
        #expect(try await store.search("REFERENCESECRET", limit: 10).count == 1)
    }

    @Test func v2MigrationClearsOldFileStateAndCreatesStructuredTables() async throws {
        let queue = try DatabaseQueue()
        let migrator = WorkspaceSchema.makeMigrator()
        try migrator.migrate(queue, upTo: "v1_workspace_index")
        try await queue.write { db in
            try db.execute(sql: """
                INSERT INTO indexed_file (path, size, mtime, contentHash, indexedAt)
                VALUES ('old.swift', 1, 1, 'old', 1)
                """)
            try db.execute(sql: """
                INSERT INTO file_fts (rowid, filename, body)
                VALUES (1, 'old.swift', 'old body')
                """)
        }

        try migrator.migrate(queue)

        let stateCount = try await queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM indexed_file")
        }
        #expect(stateCount == 0)
        let columns = try await queue.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM pragma_table_info('file_fts')")
        }
        #expect(columns == ["filename", "body", "symbols", "comments", "references"])
        let symbolTableCount = try await queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM file_symbol")
        }
        let referenceTableCount = try await queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM file_reference")
        }
        #expect(symbolTableCount == 0)
        #expect(referenceTableCount == 0)
    }

    @Test func semanticEmbeddingSearchRanksByCosineSimilarity() async throws {
        let store = try makeStore()
        try await store.upsert(IndexedFile(relativePath: "polar.md", sizeBytes: 1, modifiedAtEpoch: 1, contentHash: "a", content: "polar bears"))
        try await store.upsert(IndexedFile(relativePath: "desert.md", sizeBytes: 1, modifiedAtEpoch: 1, contentHash: "b", content: "desert foxes"))

        try await store.upsertEmbedding(path: "polar.md", vector: EmbeddingVector([1, 0, 0]))
        try await store.upsertEmbedding(path: "desert.md", vector: EmbeddingVector([0, 1, 0]))

        let hits = try await store.semanticSearch(vector: EmbeddingVector([1, 0, 0]), limit: 2)
        #expect(hits.map(\.relativePath) == ["polar.md", "desert.md"])
        #expect(hits[0].score < hits[1].score)
    }

    @Test func pruneUnseenRemovesUnstampedRowsAcrossAllTables() async throws {
        let queue = try DatabaseQueue()
        try WorkspaceSchema.makeMigrator().migrate(queue)
        let store = GRDBWorkspaceIndexStore(dbWriter: queue)
        let symbol = CodeSymbol(name: "Widget", kind: "type", line: 1, column: 1)
        let reference = CodeReference(name: "Foundation", kind: "import", line: 1, column: 1)
        for path in ["keep1.swift", "keep2.swift", "gone.swift"] {
            try await store.upsert(IndexedFile(
                relativePath: path, sizeBytes: 1, modifiedAtEpoch: 1, contentHash: path,
                content: "struct Widget {}", symbols: [symbol], comments: ["doc"], references: [reference]))
            try await store.upsertEmbedding(path: path, vector: EmbeddingVector([1, 0, 0]))
        }
        // Stamp the keepers with a future epoch, then prune between the stamps.
        let future = Int(Date().timeIntervalSince1970) + 100
        try await store.markSeen(paths: ["keep1.swift", "keep2.swift"], seenAt: future)
        let removed = try await store.pruneUnseen(olderThan: future - 1)

        #expect(removed == 1)
        #expect(try await store.fileState(path: "gone.swift") == nil)
        #expect(try await store.fileState(path: "keep1.swift") != nil)
        // Dependent rows for the pruned file are gone from every table.
        let counts = try await queue.read { db in
            (goneSymbols: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM file_symbol WHERE path = 'gone.swift'") ?? -1,
             goneReferences: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM file_reference WHERE path = 'gone.swift'") ?? -1,
             goneEmbeddings: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM file_embedding WHERE path = 'gone.swift'") ?? -1,
             keptSymbols: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM file_symbol WHERE path = 'keep1.swift'") ?? -1)
        }
        #expect(counts.goneSymbols == 0)
        #expect(counts.goneReferences == 0)
        #expect(counts.goneEmbeddings == 0)
        #expect(counts.keptSymbols == 1)
        let hits = try await store.search("Widget", limit: 10)
        #expect(!hits.contains { $0.relativePath == "gone.swift" })
        #expect(hits.contains { $0.relativePath == "keep1.swift" })
    }

    @Test func upsertBatchIndexesAllFilesInOneCall() async throws {
        let store = try makeStore()
        let files = (1...3).map { index in
            IndexedFile(
                relativePath: "batch\(index).swift", sizeBytes: index, modifiedAtEpoch: index,
                contentHash: "h\(index)", content: "func batched\(index)() {}",
                symbols: [CodeSymbol(name: "batched\(index)", kind: "function", line: 1, column: 1)])
        }
        try await store.upsertBatch(files, seenAt: Int(Date().timeIntervalSince1970))
        for index in 1...3 {
            #expect(try await store.fileState(path: "batch\(index).swift") != nil)
            let hits = try await store.search("batched\(index)", limit: 5)
            #expect(hits.contains { $0.relativePath == "batch\(index).swift" })
        }
    }

    @Test func semanticSearchReturnsOnlyTopLimitInOrder() async throws {
        let store = try makeStore()
        // Four candidates of varying similarity to the query [1,0,0].
        let rows: [(String, EmbeddingVector)] = [
            ("near.md", EmbeddingVector([1, 0, 0])),       // similarity 1.0
            ("mid.md", EmbeddingVector([0.6, 0.8, 0])),    // similarity 0.6
            ("low.md", EmbeddingVector([0.2, 0.98, 0])),   // similarity ~0.2
            ("far.md", EmbeddingVector([0, 1, 0])),        // similarity 0.0
        ]
        for (path, vector) in rows {
            try await store.upsert(IndexedFile(relativePath: path, sizeBytes: 1, modifiedAtEpoch: 1, contentHash: path, content: path))
            try await store.upsertEmbedding(path: path, vector: vector)
        }
        let hits = try await store.semanticSearch(vector: EmbeddingVector([1, 0, 0]), limit: 2)
        // Only the two most similar, best first (score = -similarity, ascending).
        #expect(hits.map(\.relativePath) == ["near.md", "mid.md"])
        #expect(hits[0].score < hits[1].score)
    }

    @Test func appStorePersistsConversationsPromptsAndModelAssignments() async throws {
        let store = try PersistenceBootstrap.inMemoryAppStore()
        let conversationID = try await store.createConversation(title: "Plan", workspacePath: "/tmp/work", mode: .code)
        try await store.appendMessage(conversationID: conversationID, role: "user", text: "hello", createdAt: Date(timeIntervalSince1970: 1))
        try await store.appendMessage(
            conversationID: conversationID,
            role: "assistant",
            text: "world",
            createdAt: Date(timeIntervalSince1970: 2),
            tokensPerSecond: 42.5)
        try await store.recordPrompt("hello", workspacePath: "/tmp/work", mode: .code)
        try await store.saveModelAssignment(.init(role: "orchestrator", modelID: "orch", quantization: 4, updatedAt: Date(timeIntervalSince1970: 3)))

        let conversations = try await store.recentConversations(limit: 1)
        #expect(conversations.map(\.id) == [conversationID])
        #expect(conversations.first?.mode == .code)
        #expect(try await store.messages(conversationID: conversationID).map(\.role) == ["user", "assistant"])
        #expect(try await store.messages(conversationID: conversationID).last?.tokensPerSecond == 42.5)
        #expect(try await store.recentPrompts(limit: 1).map(\.prompt) == ["hello"])
        #expect(try await store.modelAssignments().first == ModelAssignment(role: "orchestrator", modelID: "orch", quantization: 4, updatedAt: Date(timeIntervalSince1970: 3)))

        try await store.renameConversation(conversationID, title: "Renamed Plan")
        #expect(try await store.conversation(id: conversationID)?.title == "Renamed Plan")

        try await store.clearHistory()
        #expect(try await store.recentConversations(limit: 10).isEmpty)
        #expect(try await store.recentPrompts(limit: 10).isEmpty)
        #expect(try await store.modelAssignments().count == 1)
    }

    @Test func appStoreFiltersConversationsAndPromptsByMode() async throws {
        let store = try PersistenceBootstrap.inMemoryAppStore()
        let codeID = try await store.createConversation(title: "Code", workspacePath: "/tmp/work", mode: .code)
        let chatID = try await store.createConversation(title: "Chat", workspacePath: nil, mode: .chat)
        try await store.recordPrompt("code prompt", workspacePath: "/tmp/work", mode: .code)
        try await store.recordPrompt("chat prompt", workspacePath: nil, mode: .chat)

        #expect(try await store.recentConversations(limit: 10, mode: .code).map(\.id) == [codeID])
        #expect(try await store.recentConversations(limit: 10, mode: .chat).map(\.id) == [chatID])
        #expect(try await store.recentPrompts(limit: 10, mode: .code).map(\.prompt) == ["code prompt"])
        #expect(try await store.recentPrompts(limit: 10, mode: .chat).map(\.prompt) == ["chat prompt"])
    }
}
