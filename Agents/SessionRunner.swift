import Foundation
import Core

public actor SessionRunner {
    private let store: any SessionRuntimeStore
    private let agent: any Agent

    public init(store: any SessionRuntimeStore, agent: any Agent) {
        self.store = store
        self.agent = agent
    }

    public func admitPrompt(
        sessionID: UUID,
        prompt: String,
        delivery: SessionInputDelivery = .queue,
        resume: Bool = true,
        inputID: UUID = UUID()
    ) async throws -> SessionInputRecord {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SessionRuntimeError.invalidPrompt }
        let input = try await store.admitInput(SessionInputRecord(
            id: inputID,
            sessionID: sessionID,
            prompt: trimmed,
            delivery: delivery,
            resume: resume))
        _ = try await store.appendEvent(SessionEvent(
            sessionID: sessionID,
            kind: .promptAdmitted,
            messageID: input.id,
            payload: ["delivery": delivery.rawValue, "resume": resume ? "true" : "false"]))
        return input
    }

    public func drain(sessionID: UUID) async throws -> AgentResult? {
        guard let input = try await store.pendingInputs(sessionID: sessionID, limit: 1).first else {
            return nil
        }
        let promotedAt = Date()
        try await store.markInputPromoted(id: input.id, promotedAt: promotedAt)
        let messageID = UUID()
        try await store.appendMessagePart(SessionMessagePart(
            sessionID: sessionID,
            messageID: messageID,
            role: .user,
            text: input.prompt,
            createdAt: promotedAt))
        _ = try await store.appendEvent(SessionEvent(
            sessionID: sessionID,
            kind: .promptPromoted,
            messageID: messageID,
            payload: ["inputID": input.id.uuidString]))

        let result = try await agent.execute(task: AgentTask(prompt: input.prompt))
        let assistantMessageID = UUID()
        try await store.appendMessagePart(SessionMessagePart(
            sessionID: sessionID,
            messageID: assistantMessageID,
            role: .assistant,
            text: result.text))
        _ = try await store.appendEvent(SessionEvent(
            sessionID: sessionID,
            kind: .messagePartAppended,
            messageID: assistantMessageID,
            payload: ["role": SessionMessageRole.assistant.rawValue]))
        return result
    }

    public func interrupt(sessionID: UUID) async throws {
        try await store.interrupt(sessionID: sessionID)
        _ = try await store.appendEvent(SessionEvent(sessionID: sessionID, kind: .interrupted))
    }
}
