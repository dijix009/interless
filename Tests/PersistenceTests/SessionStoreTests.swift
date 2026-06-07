import Foundation
import Testing
import Core
import Persistence
import Shared

struct SessionStoreTests {
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
        try await store.appendMessagePart(SessionMessagePart(
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
            recentContext: "recent"))

        let parts = try await store.messageParts(sessionID: session.id, limit: 10)
        #expect(parts.map(\.messageID) == [messageID])
        #expect(parts.first?.modelID == "Qwen/Qwen3-4B-MLX-4bit")
        #expect(parts.first?.reasoningEffort == .low)
        #expect(try await store.todos(sessionID: session.id).map(\.title) == ["Inspect"])
        #expect(try await store.latestCompaction(sessionID: session.id)?.summary == "summary")

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
