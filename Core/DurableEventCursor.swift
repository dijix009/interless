import Foundation

public struct DurableEventCursor: Sendable, Equatable, Codable, Comparable, Identifiable {
    public var id: String { "\(streamID)#\(sequence)" }
    public var streamID: String
    public var sequence: Int64
    public var updatedAt: Date

    public init(
        streamID: String,
        sequence: Int64 = 0,
        updatedAt: Date = Date()
    ) {
        self.streamID = streamID
        self.sequence = max(0, sequence)
        self.updatedAt = updatedAt
    }

    public init(sessionID: UUID, cursor: SessionEventCursor, updatedAt: Date = Date()) {
        self.init(
            streamID: Self.sessionStreamID(sessionID),
            sequence: cursor.sequence,
            updatedAt: updatedAt)
    }

    public var sessionEventCursor: SessionEventCursor {
        SessionEventCursor(sequence: sequence)
    }

    public static func sessionStreamID(_ sessionID: UUID) -> String {
        "session:\(sessionID.uuidString)"
    }

    public static func < (lhs: DurableEventCursor, rhs: DurableEventCursor) -> Bool {
        if lhs.streamID == rhs.streamID {
            return lhs.sequence < rhs.sequence
        }
        return lhs.streamID < rhs.streamID
    }
}

public struct DurableEventReplaySummary: Sendable, Equatable, Codable {
    public var streamID: String
    public var startCursor: DurableEventCursor
    public var endCursor: DurableEventCursor
    public var replayedCount: Int
    public var isTruncated: Bool

    public init(
        streamID: String,
        startCursor: DurableEventCursor,
        endCursor: DurableEventCursor,
        replayedCount: Int,
        isTruncated: Bool = false
    ) {
        self.streamID = streamID
        self.startCursor = startCursor
        self.endCursor = endCursor
        self.replayedCount = max(0, replayedCount)
        self.isTruncated = isTruncated
    }
}
