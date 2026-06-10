import Foundation
import Shared

public enum SessionInputDelivery: String, Sendable, Equatable, Codable, CaseIterable {
    case steer
    case queue
}

public enum SessionInputStatus: String, Sendable, Equatable, Codable, CaseIterable {
    case pending
    case promoted
    case interrupted
}

public struct SessionRecord: Sendable, Equatable, Codable, Identifiable {
    public var id: UUID
    public var workspacePath: String?
    public var title: String
    public var createdAt: Date
    public var updatedAt: Date
    public var isInterrupted: Bool

    public init(
        id: UUID = UUID(),
        workspacePath: String? = nil,
        title: String = "New Session",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isInterrupted: Bool = false
    ) {
        self.id = id
        self.workspacePath = workspacePath
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isInterrupted = isInterrupted
    }
}

public struct SessionInputRecord: Sendable, Equatable, Codable, Identifiable {
    public var id: UUID
    public var sessionID: UUID
    public var prompt: String
    public var delivery: SessionInputDelivery
    public var resume: Bool
    public var status: SessionInputStatus
    public var createdAt: Date
    public var promotedAt: Date?

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        prompt: String,
        delivery: SessionInputDelivery = .queue,
        resume: Bool = true,
        status: SessionInputStatus = .pending,
        createdAt: Date = Date(),
        promotedAt: Date? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.prompt = prompt
        self.delivery = delivery
        self.resume = resume
        self.status = status
        self.createdAt = createdAt
        self.promotedAt = promotedAt
    }
}

public enum SessionMessageRole: String, Sendable, Equatable, Codable, CaseIterable {
    case system
    case user
    case assistant
    case tool
}

public struct SessionMessagePart: Sendable, Equatable, Codable, Identifiable {
    public var id: UUID
    public var sessionID: UUID
    public var messageID: UUID
    public var role: SessionMessageRole
    public var kind: String
    public var text: String
    public var createdAt: Date
    public var modelID: String?
    public var reasoningEffort: ReasoningEffort?

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        messageID: UUID,
        role: SessionMessageRole,
        kind: String = "text",
        text: String,
        createdAt: Date = Date(),
        modelID: String? = nil,
        reasoningEffort: ReasoningEffort? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.messageID = messageID
        self.role = role
        self.kind = kind
        self.text = text
        self.createdAt = createdAt
        self.modelID = modelID
        self.reasoningEffort = reasoningEffort
    }
}

public struct SessionTodo: Sendable, Equatable, Codable, Identifiable {
    public enum Status: String, Sendable, Equatable, Codable, CaseIterable {
        case pending
        case inProgress
        case completed
        case cancelled
    }

    public var id: UUID
    public var sessionID: UUID
    public var title: String
    public var status: Status
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        title: String,
        status: Status = .pending,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.sessionID = sessionID
        self.title = title
        self.status = status
        self.updatedAt = updatedAt
    }
}

public struct SessionCompactionCheckpoint: Sendable, Equatable, Codable, Identifiable {
    public var id: UUID
    public var sessionID: UUID
    public var summary: String
    public var recentContext: String
    public var createdAt: Date
    public var coveredMessagePartIDs: [UUID]
    public var coveredThrough: Date?
    public var sourceMode: ConversationContextMode?
    public var estimatedTokens: Int

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        summary: String,
        recentContext: String,
        createdAt: Date = Date(),
        coveredMessagePartIDs: [UUID] = [],
        coveredThrough: Date? = nil,
        sourceMode: ConversationContextMode? = nil,
        estimatedTokens: Int = 0
    ) {
        self.id = id
        self.sessionID = sessionID
        self.summary = summary
        self.recentContext = recentContext
        self.createdAt = createdAt
        self.coveredMessagePartIDs = coveredMessagePartIDs
        self.coveredThrough = coveredThrough
        self.sourceMode = sourceMode
        self.estimatedTokens = estimatedTokens
    }
}

public enum SessionEventKind: String, Sendable, Equatable, Codable, CaseIterable {
    case created
    case promptAdmitted
    case promptPromoted
    case messagePartAppended
    case toolCallStarted
    case toolCallSettled
    case interrupted
    case compactionStarted
    case compactionEnded
    case todoUpdated
    case failed
}

public struct SessionEventCursor: Sendable, Equatable, Codable, Comparable {
    public var sequence: Int64

    public init(sequence: Int64 = 0) {
        self.sequence = sequence
    }

    public static func < (lhs: SessionEventCursor, rhs: SessionEventCursor) -> Bool {
        lhs.sequence < rhs.sequence
    }
}

public struct SessionEvent: Sendable, Equatable, Codable, Identifiable {
    public var id: UUID
    public var sessionID: UUID
    public var sequence: Int64
    public var kind: SessionEventKind
    public var messageID: UUID?
    public var payload: [String: String]
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        sequence: Int64 = 0,
        kind: SessionEventKind,
        messageID: UUID? = nil,
        payload: [String: String] = [:],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sessionID = sessionID
        self.sequence = sequence
        self.kind = kind
        self.messageID = messageID
        self.payload = payload
        self.createdAt = createdAt
    }

    public var cursor: SessionEventCursor {
        SessionEventCursor(sequence: sequence)
    }
}

public enum SessionRuntimeError: Error, Sendable, Equatable {
    case sessionNotFound(UUID)
    case inputConflict(UUID)
    case inputNotFound(UUID)
    case invalidPrompt
}

public protocol SessionRuntimeStore: Sendable {
    func createSession(id: UUID?, workspacePath: String?, title: String) async throws -> SessionRecord
    func session(id: UUID) async throws -> SessionRecord?
    func recentSessions(limit: Int, workspacePath: String?) async throws -> [SessionRecord]
    func renameSession(id: UUID, title: String) async throws
    func deleteSession(id: UUID) async throws
    func admitInput(_ input: SessionInputRecord) async throws -> SessionInputRecord
    func pendingInputs(sessionID: UUID, limit: Int) async throws -> [SessionInputRecord]
    func markInputPromoted(id: UUID, promotedAt: Date) async throws
    func appendMessagePart(_ part: SessionMessagePart) async throws
    func messageParts(sessionID: UUID, limit: Int) async throws -> [SessionMessagePart]
    func upsertMessageEmbedding(_ embedding: SessionMessageEmbedding) async throws
    func messageEmbeddings(sessionID: UUID, limit: Int) async throws -> [SessionMessageEmbedding]
    func messageEmbedding(partID: UUID) async throws -> SessionMessageEmbedding?
    func replaceTodos(_ todos: [SessionTodo], sessionID: UUID) async throws
    func todos(sessionID: UUID) async throws -> [SessionTodo]
    func saveCompaction(_ checkpoint: SessionCompactionCheckpoint) async throws
    func latestCompaction(sessionID: UUID) async throws -> SessionCompactionCheckpoint?
    func appendEvent(_ event: SessionEvent) async throws -> SessionEvent
    func events(sessionID: UUID, after cursor: SessionEventCursor?, limit: Int) async throws -> [SessionEvent]
    func interrupt(sessionID: UUID) async throws
}

public actor SessionEventLog {
    private var eventsBySession: [UUID: [SessionEvent]] = [:]
    private var subscribers: [UUID: [UUID: AsyncStream<SessionEvent>.Continuation]] = [:]
    /// Cap on retained in-memory events per session. The durable SQL store
    /// (`SessionStore`) is the authoritative history; this is a recent-tail cache.
    private let retentionLimit: Int
    private static let streamBufferLimit = 512

    public init(retentionLimit: Int = 1000) {
        self.retentionLimit = max(1, retentionLimit)
    }

    public func append(_ event: SessionEvent) -> SessionEvent {
        let nextSequence = (eventsBySession[event.sessionID]?.last?.sequence ?? 0) + 1
        var saved = event
        saved.sequence = nextSequence
        eventsBySession[event.sessionID, default: []].append(saved)
        // Tail-prune oldest events; `last.sequence` (the replay cursor anchor) is
        // preserved, so sequence numbering and durableCursor stay correct.
        if let count = eventsBySession[event.sessionID]?.count, count > retentionLimit {
            eventsBySession[event.sessionID]?.removeFirst(count - retentionLimit)
        }
        for continuation in subscribers[event.sessionID]?.values ?? [:].values {
            continuation.yield(saved)
        }
        return saved
    }

    public func replay(
        sessionID: UUID,
        after cursor: SessionEventCursor? = nil,
        limit: Int = 200
    ) -> [SessionEvent] {
        let sequence = cursor?.sequence ?? 0
        return Array((eventsBySession[sessionID] ?? [])
            .filter { $0.sequence > sequence }
            .prefix(max(0, limit)))
    }

    public func durableCursor(sessionID: UUID) -> DurableEventCursor {
        DurableEventCursor(
            streamID: DurableEventCursor.sessionStreamID(sessionID),
            sequence: eventsBySession[sessionID]?.last?.sequence ?? 0,
            updatedAt: eventsBySession[sessionID]?.last?.createdAt ?? Date())
    }

    public func replay(
        sessionID: UUID,
        after cursor: DurableEventCursor?,
        limit: Int = 200
    ) -> (events: [SessionEvent], summary: DurableEventReplaySummary) {
        let start = cursor ?? DurableEventCursor(
            streamID: DurableEventCursor.sessionStreamID(sessionID),
            sequence: 0)
        let events = replay(
            sessionID: sessionID,
            after: start.sessionEventCursor,
            limit: limit)
        let end = DurableEventCursor(
            streamID: DurableEventCursor.sessionStreamID(sessionID),
            sequence: events.last?.sequence ?? start.sequence,
            updatedAt: events.last?.createdAt ?? start.updatedAt)
        return (
            events,
            DurableEventReplaySummary(
                streamID: start.streamID,
                startCursor: start,
                endCursor: end,
                replayedCount: events.count,
                isTruncated: events.count >= max(0, limit)))
    }

    public func stream(sessionID: UUID) -> AsyncStream<SessionEvent> {
        let id = UUID()
        // Bounded buffer: a slow/abandoned subscriber drops oldest-undelivered
        // events under back-pressure instead of growing memory without limit.
        return AsyncStream(SessionEvent.self, bufferingPolicy: .bufferingNewest(Self.streamBufferLimit)) { continuation in
            subscribers[sessionID, default: [:]][id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeSubscriber(id, sessionID: sessionID) }
            }
        }
    }

    private func removeSubscriber(_ id: UUID, sessionID: UUID) {
        subscribers[sessionID]?.removeValue(forKey: id)
        if subscribers[sessionID]?.isEmpty == true {
            subscribers.removeValue(forKey: sessionID)
        }
    }
}
