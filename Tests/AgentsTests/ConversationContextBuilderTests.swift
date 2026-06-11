import Foundation
import Testing
import Agents
import Core
import Shared

struct ConversationContextBuilderTests {
    @Test func simpleContextSkipsStandaloneAndNewTopicPrompts() async {
        let store = ContextMemoryStore()
        let sessionID = UUID()
        await store.append(.init(sessionID: sessionID, messageID: UUID(), role: .user, text: "Write a story about Finley."))
        await store.append(.init(sessionID: sessionID, messageID: UUID(), role: .assistant, text: "Finley lived in a quiet pond."))
        let builder = await store.builder(embedTexts: { _ in nil })

        let hello = await builder.build(request: .init(
            sessionID: sessionID,
            prompt: "Hello?",
            mode: .simple,
            isPlainChat: true,
            effectiveContextTokenCap: 8_192))
        let newTopic = await builder.build(request: .init(
            sessionID: sessionID,
            prompt: "Write a Python script that sorts CSV files.",
            mode: .simple,
            isPlainChat: true,
            effectiveContextTokenCap: 8_192))

        #expect(hello.effectiveMode == .simple)
        #expect(!hello.observations.joined().contains("Finley"))
        #expect(!newTopic.observations.joined().contains("Finley"))
    }

    @Test func simpleContextIncludesBoundedFollowUps() async {
        let store = ContextMemoryStore()
        let sessionID = UUID()
        let user = SessionMessagePart(sessionID: sessionID, messageID: UUID(), role: .user, text: "Write a story about Finley.")
        await store.append(user)
        await store.append(.init(sessionID: sessionID, messageID: UUID(), role: .assistant, text: "Finley lived in a quiet pond."))
        let builder = await store.builder(embedTexts: { _ in nil })

        let bundle = await builder.build(request: .init(
            sessionID: sessionID,
            prompt: "Tell me more about him.",
            mode: .simple,
            isPlainChat: true,
            effectiveContextTokenCap: 8_192))

        #expect(bundle.effectiveMode == .simple)
        #expect(bundle.includedMessagePartIDs.contains(user.id))
        #expect(bundle.observations.joined().contains("Finley"))
    }

    @Test func smartContextDegradesWhenEmbeddingsAreUnavailable() async {
        let store = ContextMemoryStore()
        let sessionID = UUID()
        await store.append(.init(sessionID: sessionID, messageID: UUID(), role: .user, text: "Write a story about Finley."))
        let builder = await store.builder(embedTexts: { _ in nil })

        let bundle = await builder.build(request: .init(
            sessionID: sessionID,
            prompt: "Tell me more about him.",
            mode: .smart,
            isPlainChat: false,
            effectiveContextTokenCap: 16_384))

        #expect(bundle.requestedMode == .smart)
        #expect(bundle.effectiveMode == .smartDegraded)
        #expect(bundle.observations.first?.contains("smartDegraded") == true)
    }

    @Test func smartContextRetrievesRelevantTurnsAndSuppressesTopicChanges() async {
        let store = ContextMemoryStore()
        let sessionID = UUID()
        let story = SessionMessagePart(sessionID: sessionID, messageID: UUID(), role: .assistant, text: "Finley the fish loved Lila near the pond.")
        let code = SessionMessagePart(sessionID: sessionID, messageID: UUID(), role: .assistant, text: "Swift actors isolate mutable state.")
        await store.append(story)
        await store.append(code)
        let builder = await store.builder(embedTexts: { texts in
            texts.map { text in
                if text.localizedCaseInsensitiveContains("finley") || text.localizedCaseInsensitiveContains("lila") {
                    return EmbeddingVector([1, 0, 0])
                }
                if text.localizedCaseInsensitiveContains("swift") || text.localizedCaseInsensitiveContains("actor") {
                    return EmbeddingVector([0, 1, 0])
                }
                return EmbeddingVector([0, 0, 1])
            }
        })

        let followUp = await builder.build(request: .init(
            sessionID: sessionID,
            prompt: "Tell me more about Finley.",
            mode: .smart,
            isPlainChat: false,
            effectiveContextTokenCap: 16_384))
        let topicChange = await builder.build(request: .init(
            sessionID: sessionID,
            prompt: "Explain SQL indexing from scratch.",
            mode: .smart,
            isPlainChat: false,
            effectiveContextTokenCap: 16_384))

        #expect(followUp.effectiveMode == .smart)
        #expect(followUp.includedMessagePartIDs.contains(story.id))
        #expect(followUp.observations.joined().contains("Finley"))
        #expect(!topicChange.observations.joined().contains("Finley"))
        #expect(!topicChange.observations.joined().contains("Swift actors"))
    }
}

    @Test func compactionPrefersAbstractiveSummaryAndSimpleModeReadsIt() async throws {
        let sessionID = UUID()
        let store = ContextMemoryStore()
        // Enough parts to cross the >= 24 candidate compaction trigger.
        for index in 0..<30 {
            await store.append(SessionMessagePart(
                sessionID: sessionID,
                messageID: UUID(),
                role: index % 2 == 0 ? .user : .assistant,
                text: "Exchange number \(index) about the Interless retrieval design."))
        }
        let builder = await store.builder(embedTexts: { _ in nil })

        await builder.compactIfNeeded(
            sessionID: sessionID,
            mode: .simple,
            summarize: { _ in "- decided to use FTS5\n- open task: wire retrieval" })

        // Simple mode consults the checkpoint and carries the abstractive summary.
        let bundle = await builder.build(request: .init(
            sessionID: sessionID,
            prompt: "Tell me more about it.",
            mode: .simple,
            isPlainChat: true,
            effectiveContextTokenCap: 4_096))
        #expect(bundle.summaryID != nil)
        #expect(bundle.observations.contains { $0.contains("decided to use FTS5") })
    }

private actor ContextMemoryStore {
    private var parts: [SessionMessagePart] = []
    private var embeddings: [UUID: SessionMessageEmbedding] = [:]
    private var compaction: SessionCompactionCheckpoint?

    func append(_ part: SessionMessagePart) {
        parts.append(part)
    }

    func builder(
        embedTexts: @escaping ConversationContextBuilder.EmbedTexts
    ) -> ConversationContextBuilder {
        let store = self
        return ConversationContextBuilder(
            loadMessageParts: { sessionID, limit in
                await store.parts(sessionID: sessionID, limit: limit)
            },
            loadLatestCompaction: { _ in
                await store.compactionSnapshot()
            },
            saveCompaction: { checkpoint in
                await store.save(checkpoint)
            },
            embedTexts: embedTexts,
            loadMessageEmbeddings: { sessionID, limit in
                await store.embeddings(sessionID: sessionID, limit: limit)
            },
            loadMessageEmbedding: { partID in
                await store.embedding(partID: partID)
            },
            saveMessageEmbedding: { embedding in
                await store.save(embedding)
            })
    }

    private func parts(sessionID: UUID, limit: Int) -> [SessionMessagePart] {
        Array(parts.filter { $0.sessionID == sessionID }.prefix(limit))
    }

    private func embeddings(sessionID: UUID, limit: Int) -> [SessionMessageEmbedding] {
        Array(embeddings.values.filter { $0.sessionID == sessionID }.prefix(limit))
    }

    private func embedding(partID: UUID) -> SessionMessageEmbedding? {
        embeddings[partID]
    }

    private func compactionSnapshot() -> SessionCompactionCheckpoint? {
        compaction
    }

    private func save(_ embedding: SessionMessageEmbedding) {
        embeddings[embedding.partID] = embedding
    }

    private func save(_ checkpoint: SessionCompactionCheckpoint) {
        compaction = checkpoint
    }
}
