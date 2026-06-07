import Foundation

public enum ContextEpochReason: String, Sendable, Equatable, Codable, CaseIterable {
    case initial
    case promptExpansion
    case compaction
    case agentSwitch
    case manual
}

public struct ContextEpoch: Sendable, Equatable, Codable, Identifiable {
    public var id: UUID
    public var sessionID: UUID
    public var agentID: String?
    public var revision: Int
    public var reason: ContextEpochReason
    public var contextHash: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        agentID: String? = nil,
        revision: Int,
        reason: ContextEpochReason,
        contextHash: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sessionID = sessionID
        self.agentID = agentID
        self.revision = revision
        self.reason = reason
        self.contextHash = contextHash
        self.createdAt = createdAt
    }
}

public actor ContextEpochStore {
    private var epochsBySession: [UUID: [ContextEpoch]] = [:]

    public init() {}

    @discardableResult
    public func replace(
        sessionID: UUID,
        agentID: String? = nil,
        reason: ContextEpochReason,
        context: String,
        createdAt: Date = Date()
    ) -> ContextEpoch {
        let existing = epochsBySession[sessionID] ?? []
        let revision = (existing.last?.revision ?? 0) + 1
        let epoch = ContextEpoch(
            sessionID: sessionID,
            agentID: agentID,
            revision: revision,
            reason: reason,
            contextHash: Self.hash(context),
            createdAt: createdAt)
        epochsBySession[sessionID] = existing + [epoch]
        return epoch
    }

    public func current(sessionID: UUID) -> ContextEpoch? {
        epochsBySession[sessionID]?.last
    }

    public func history(sessionID: UUID) -> [ContextEpoch] {
        epochsBySession[sessionID] ?? []
    }

    public func clear(sessionID: UUID) {
        epochsBySession[sessionID] = nil
    }

    private static func hash(_ text: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}
