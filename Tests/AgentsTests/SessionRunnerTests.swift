import Foundation
import Testing
import Agents
import Core

struct SessionRunnerTests {
    @Test func sessionRunnerPromotesOneInputAndPersistsAssistantPart() async throws {
        let store = InMemorySessionRuntimeStore()
        let session = try await store.createSession(id: UUID(), workspacePath: "/tmp/work", title: "Plan")
        let runner = SessionRunner(store: store, agent: EchoAgent())

        let input = try await runner.admitPrompt(sessionID: session.id, prompt: "inspect", inputID: UUID())
        let result = try await runner.drain(sessionID: session.id)

        #expect(input.status == .pending)
        #expect(result?.text == "echo: inspect")
        #expect(try await store.pendingInputs(sessionID: session.id, limit: 10).isEmpty)
        #expect(try await store.messageParts(sessionID: session.id, limit: 10).map(\.role) == [.user, .assistant])
        #expect(try await store.events(sessionID: session.id, after: nil, limit: 10).map(\.kind) == [
            .promptAdmitted,
            .promptPromoted,
            .messagePartAppended,
        ])
    }
}

private struct EchoAgent: Agent {
    func execute(task: AgentTask) async throws -> AgentResult {
        AgentResult(taskID: task.id, route: .utility, text: "echo: \(task.prompt)")
    }
}

private actor InMemorySessionRuntimeStore: SessionRuntimeStore {
    private var sessions: [UUID: SessionRecord] = [:]
    private var inputs: [UUID: SessionInputRecord] = [:]
    private var parts: [SessionMessagePart] = []
    private var embeddings: [UUID: SessionMessageEmbedding] = [:]
    private var compactions: [UUID: SessionCompactionCheckpoint] = [:]
    private var eventsBySession: [UUID: [SessionEvent]] = [:]

    func createSession(id: UUID?, workspacePath: String?, title: String) async throws -> SessionRecord {
        let record = SessionRecord(id: id ?? UUID(), workspacePath: workspacePath, title: title)
        sessions[record.id] = record
        return record
    }

    func session(id: UUID) async throws -> SessionRecord? {
        sessions[id]
    }

    func recentSessions(limit: Int, workspacePath: String?) async throws -> [SessionRecord] {
        Array(sessions.values.prefix(limit))
    }

    func renameSession(id: UUID, title: String) async throws {
        guard var session = sessions[id] else { throw SessionRuntimeError.sessionNotFound(id) }
        session.title = title
        session.updatedAt = Date()
        sessions[id] = session
    }

    func deleteSession(id: UUID) async throws {
        guard sessions.removeValue(forKey: id) != nil else { throw SessionRuntimeError.sessionNotFound(id) }
        inputs = inputs.filter { $0.value.sessionID != id }
        parts.removeAll { $0.sessionID == id }
        embeddings = embeddings.filter { $0.value.sessionID != id }
        compactions[id] = nil
        eventsBySession[id] = nil
    }

    func admitInput(_ input: SessionInputRecord) async throws -> SessionInputRecord {
        if let existing = inputs[input.id] { return existing }
        inputs[input.id] = input
        return input
    }

    func pendingInputs(sessionID: UUID, limit: Int) async throws -> [SessionInputRecord] {
        Array(inputs.values
            .filter { $0.sessionID == sessionID && $0.status == .pending }
            .sorted { $0.createdAt < $1.createdAt }
            .prefix(limit))
    }

    func markInputPromoted(id: UUID, promotedAt: Date) async throws {
        inputs[id]?.status = .promoted
        inputs[id]?.promotedAt = promotedAt
    }

    func appendMessagePart(_ part: SessionMessagePart) async throws {
        parts.append(part)
    }

    func messageParts(sessionID: UUID, limit: Int) async throws -> [SessionMessagePart] {
        Array(parts.filter { $0.sessionID == sessionID }.prefix(limit))
    }

    func upsertMessageEmbedding(_ embedding: SessionMessageEmbedding) async throws {
        embeddings[embedding.partID] = embedding
    }

    func messageEmbeddings(sessionID: UUID, limit: Int) async throws -> [SessionMessageEmbedding] {
        Array(embeddings.values
            .filter { $0.sessionID == sessionID }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(limit))
    }

    func messageEmbedding(partID: UUID) async throws -> SessionMessageEmbedding? {
        embeddings[partID]
    }

    func replaceTodos(_ todos: [SessionTodo], sessionID: UUID) async throws {}
    func todos(sessionID: UUID) async throws -> [SessionTodo] { [] }
    func saveCompaction(_ checkpoint: SessionCompactionCheckpoint) async throws {
        compactions[checkpoint.sessionID] = checkpoint
    }
    func latestCompaction(sessionID: UUID) async throws -> SessionCompactionCheckpoint? { compactions[sessionID] }

    func appendEvent(_ event: SessionEvent) async throws -> SessionEvent {
        var saved = event
        saved.sequence = (eventsBySession[event.sessionID]?.last?.sequence ?? 0) + 1
        eventsBySession[event.sessionID, default: []].append(saved)
        return saved
    }

    func events(sessionID: UUID, after cursor: SessionEventCursor?, limit: Int) async throws -> [SessionEvent] {
        Array((eventsBySession[sessionID] ?? [])
            .filter { $0.sequence > (cursor?.sequence ?? 0) }
            .prefix(limit))
    }

    func interrupt(sessionID: UUID) async throws {
        sessions[sessionID]?.isInterrupted = true
    }
}
