import Foundation
import Testing
import Core
import Persistence
import Shared

struct SessionStoreTests {
    @Test func semanticMessageSearchRanksOverFullHistoryNotJustRecent() async throws {
        let store = try PersistenceBootstrap.inMemorySessionStore()
        let session = try await store.createSession(id: nil, workspacePath: nil, title: "S")

        // An OLD, highly-relevant turn (early createdAt) plus newer unrelated turns.
        func add(_ text: String, _ vec: [Float], createdAt: Double) async throws -> UUID {
            let id = UUID()
            try await store.appendMessagePart(SessionMessagePart(
                id: id, sessionID: session.id, messageID: UUID(), role: .user,
                text: text, createdAt: Date(timeIntervalSince1970: createdAt)))
            try await store.upsertMessageEmbedding(SessionMessageEmbedding(
                sessionID: session.id, partID: id, vector: EmbeddingVector(vec)))
            return id
        }
        let oldRelevant = try await add("the auth token format we chose", [1, 0, 0], createdAt: 1)
        _ = try await add("unrelated chatter about lunch", [0, 1, 0], createdAt: 100)
        _ = try await add("more unrelated weather talk", [0, 0, 1], createdAt: 101)

        // Query close to the OLD turn; top-1 must be it despite being the oldest.
        let hits = try await store.semanticMessageSearch(
            sessionID: session.id, vector: EmbeddingVector([1, 0, 0]), limit: 2)
        #expect(hits.first?.id == oldRelevant)
        #expect(hits.count == 2) // bounded to limit
    }

    @Test func sessionStoreAdmitsInputsIdempotentlyAndReplaysEvents() async throws {
        let store = try PersistenceBootstrap.inMemorySessionStore()
        let session = try await store.createSession(id: UUID(), workspacePath: "/tmp/work", title: "Plan")
        let input = SessionInputRecord(
            id: UUID(),
            sessionID: session.id,
            prompt: "hello",
            delivery: .queue,
            resume: true,
            createdAt: Date(timeIntervalSince1970: 1))

        let admitted = try await store.admitInput(input)
        let retried = try await store.admitInput(input)

        #expect(admitted == retried)
        #expect(try await store.pendingInputs(sessionID: session.id, limit: 10).map(\.id) == [input.id])

        try await store.markInputPromoted(id: input.id, promotedAt: Date(timeIntervalSince1970: 2))
        #expect(try await store.pendingInputs(sessionID: session.id, limit: 10).isEmpty)

        let first = try await store.appendEvent(SessionEvent(sessionID: session.id, kind: .created))
        let second = try await store.appendEvent(SessionEvent(sessionID: session.id, kind: .promptAdmitted, payload: ["input": input.id.uuidString]))
        #expect(first.sequence == 1)
        #expect(second.sequence == 2)
        #expect(try await store.events(sessionID: session.id, after: first.cursor, limit: 10).map(\.kind) == [.promptAdmitted])
    }

    @Test func sessionStorePersistsPartsTodosCompactionAndInterruptsPendingInputs() async throws {
        let store = try PersistenceBootstrap.inMemorySessionStore()
        let session = try await store.createSession(id: nil, workspacePath: nil, title: "Chat")
        let input = try await store.admitInput(SessionInputRecord(sessionID: session.id, prompt: "work"))
        let messageID = UUID()
        let partID = UUID()
        try await store.appendMessagePart(SessionMessagePart(
            id: partID,
            sessionID: session.id,
            messageID: messageID,
            role: .user,
            text: "work",
            modelID: "Qwen/Qwen3-4B-MLX-4bit",
            reasoningEffort: .low))
        try await store.replaceTodos([
            SessionTodo(sessionID: session.id, title: "Inspect", status: .inProgress)
        ], sessionID: session.id)
        try await store.saveCompaction(SessionCompactionCheckpoint(
            sessionID: session.id,
            summary: "summary",
            recentContext: "recent",
            coveredMessagePartIDs: [partID],
            coveredThrough: Date(timeIntervalSince1970: 3),
            sourceMode: .smart,
            estimatedTokens: 12))

        let parts = try await store.messageParts(sessionID: session.id, limit: 10)
        #expect(parts.map(\.messageID) == [messageID])
        #expect(parts.first?.modelID == "Qwen/Qwen3-4B-MLX-4bit")
        #expect(parts.first?.reasoningEffort == .low)
        try await store.upsertMessageEmbedding(SessionMessageEmbedding(
            sessionID: session.id,
            partID: partID,
            vector: EmbeddingVector([1, 0, 0]),
            updatedAt: Date(timeIntervalSince1970: 5)))
        #expect(try await store.messageEmbedding(partID: partID)?.vector.cosineSimilarity(to: EmbeddingVector([1, 0, 0])) ?? 0 > 0.99)
        #expect(try await store.messageEmbeddings(sessionID: session.id, limit: 10).map(\.partID) == [partID])
        #expect(try await store.todos(sessionID: session.id).map(\.title) == ["Inspect"])
        let checkpoint = try #require(try await store.latestCompaction(sessionID: session.id))
        #expect(checkpoint.summary == "summary")
        #expect(checkpoint.coveredMessagePartIDs == [partID])
        #expect(checkpoint.coveredThrough == Date(timeIntervalSince1970: 3))
        #expect(checkpoint.sourceMode == .smart)
        #expect(checkpoint.estimatedTokens == 12)

        try await store.interrupt(sessionID: session.id)
        #expect(try await store.session(id: session.id)?.isInterrupted == true)
        let events = try await store.pendingInputs(sessionID: session.id, limit: 10)
        #expect(events.isEmpty)
        #expect(input.status == .pending)
    }

    @Test func sessionStoreRenamesAndDeletesSessions() async throws {
        let store = try PersistenceBootstrap.inMemorySessionStore()
        let session = try await store.createSession(id: nil, workspacePath: "/tmp/work", title: "Draft")
        try await store.appendMessagePart(SessionMessagePart(
            sessionID: session.id,
            messageID: UUID(),
            role: .assistant,
            text: "answer"))
        _ = try await store.appendEvent(SessionEvent(sessionID: session.id, kind: .created))

        try await store.renameSession(id: session.id, title: "Renamed")
        #expect(try await store.session(id: session.id)?.title == "Renamed")

        try await store.deleteSession(id: session.id)
        #expect(try await store.session(id: session.id) == nil)
        #expect(try await store.messageParts(sessionID: session.id, limit: 10).isEmpty)
        #expect(try await store.events(sessionID: session.id, after: nil, limit: 10).isEmpty)
    }

    @Test func sessionExporterRedactsAndImportsBundle() async throws {
        let source = try PersistenceBootstrap.inMemorySessionStore()
        let destination = try PersistenceBootstrap.inMemorySessionStore()
        let session = try await source.createSession(id: UUID(), workspacePath: "/tmp/private-work", title: "Secret Session")
        let messageID = UUID()
        try await source.appendMessagePart(SessionMessagePart(
            sessionID: session.id,
            messageID: messageID,
            role: .user,
            text: "Open /tmp/private-work/token.txt"))
        try await source.appendMessagePart(SessionMessagePart(
            sessionID: session.id,
            messageID: messageID,
            role: .tool,
            text: "stdout secret token"))
        try await source.replaceTodos([
            SessionTodo(sessionID: session.id, title: "Review /tmp/private-work")
        ], sessionID: session.id)
        _ = try await source.appendEvent(SessionEvent(
            sessionID: session.id,
            kind: .messagePartAppended,
            payload: ["stdout": "private tool output"]))

        let bundle = try await SessionExporter().export(sessionID: session.id, from: source)
        let imported = try await SessionExporter().importBundle(bundle, into: destination)
        let importedParts = try await destination.messageParts(sessionID: imported.id, limit: 10)

        #expect(bundle.session.workspacePath?.contains("/tmp/private-work") == false)
        #expect(bundle.messageParts.contains { $0.text == "[tool output redacted]" })
        #expect(bundle.events.first?.payload["stdout"] == "[redacted]")
        #expect(bundle.replay?.replayedCount == 1)
        #expect(imported.id == session.id)
        #expect(importedParts.count == 2)
    }
}
