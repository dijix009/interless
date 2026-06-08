import Foundation
import Shared

public struct SessionMessageEmbedding: Sendable, Equatable, Codable, Identifiable {
    public var id: UUID { partID }
    public var sessionID: UUID
    public var partID: UUID
    public var vector: EmbeddingVector
    public var updatedAt: Date

    public init(
        sessionID: UUID,
        partID: UUID,
        vector: EmbeddingVector,
        updatedAt: Date = Date()
    ) {
        self.sessionID = sessionID
        self.partID = partID
        self.vector = vector
        self.updatedAt = updatedAt
    }
}

public struct ConversationContextRequest: Sendable, Equatable, Codable {
    public var sessionID: UUID?
    public var prompt: String
    public var mode: ConversationContextMode
    public var isPlainChat: Bool
    public var effectiveContextTokenCap: Int
    public var now: Date

    public init(
        sessionID: UUID?,
        prompt: String,
        mode: ConversationContextMode,
        isPlainChat: Bool,
        effectiveContextTokenCap: Int,
        now: Date = Date()
    ) {
        self.sessionID = sessionID
        self.prompt = prompt
        self.mode = mode
        self.isPlainChat = isPlainChat
        self.effectiveContextTokenCap = effectiveContextTokenCap
        self.now = now
    }
}

public struct ConversationContextBundle: Sendable, Equatable, Codable {
    public var requestedMode: ConversationContextMode
    public var effectiveMode: EffectiveConversationContextMode
    public var observations: [String]
    public var includedMessagePartIDs: [UUID]
    public var summaryID: UUID?
    public var estimatedTokens: Int
    public var diagnostics: [String: String]

    public init(
        requestedMode: ConversationContextMode,
        effectiveMode: EffectiveConversationContextMode,
        observations: [String] = [],
        includedMessagePartIDs: [UUID] = [],
        summaryID: UUID? = nil,
        estimatedTokens: Int = 0,
        diagnostics: [String: String] = [:]
    ) {
        self.requestedMode = requestedMode
        self.effectiveMode = effectiveMode
        self.observations = observations
        self.includedMessagePartIDs = includedMessagePartIDs
        self.summaryID = summaryID
        self.estimatedTokens = estimatedTokens
        self.diagnostics = diagnostics
    }
}
