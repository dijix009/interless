import Foundation
import Core
import Shared

public struct ConversationContextBuilder: Sendable {
    public typealias LoadMessageParts = @Sendable (_ sessionID: UUID, _ limit: Int) async throws -> [SessionMessagePart]
    public typealias LoadCompaction = @Sendable (_ sessionID: UUID) async throws -> SessionCompactionCheckpoint?
    public typealias SaveCompaction = @Sendable (_ checkpoint: SessionCompactionCheckpoint) async throws -> Void
    public typealias EmbedTexts = @Sendable (_ texts: [String]) async throws -> [EmbeddingVector]?
    public typealias LoadEmbeddings = @Sendable (_ sessionID: UUID, _ limit: Int) async throws -> [SessionMessageEmbedding]
    public typealias LoadEmbedding = @Sendable (_ partID: UUID) async throws -> SessionMessageEmbedding?
    public typealias SaveEmbedding = @Sendable (_ embedding: SessionMessageEmbedding) async throws -> Void

    private struct Candidate: Sendable {
        var index: Int
        var part: SessionMessagePart
        var row: String
        var tokens: Set<String>
    }

    private struct ScoredCandidate: Sendable {
        var candidate: Candidate
        var score: Double
    }

    public var loadMessageParts: LoadMessageParts
    public var loadLatestCompaction: LoadCompaction
    public var saveCompaction: SaveCompaction
    public var embedTexts: EmbedTexts
    public var loadMessageEmbeddings: LoadEmbeddings
    public var loadMessageEmbedding: LoadEmbedding
    public var saveMessageEmbedding: SaveEmbedding

    public init(
        loadMessageParts: @escaping LoadMessageParts,
        loadLatestCompaction: @escaping LoadCompaction,
        saveCompaction: @escaping SaveCompaction,
        embedTexts: @escaping EmbedTexts,
        loadMessageEmbeddings: @escaping LoadEmbeddings,
        loadMessageEmbedding: @escaping LoadEmbedding,
        saveMessageEmbedding: @escaping SaveEmbedding
    ) {
        self.loadMessageParts = loadMessageParts
        self.loadLatestCompaction = loadLatestCompaction
        self.saveCompaction = saveCompaction
        self.embedTexts = embedTexts
        self.loadMessageEmbeddings = loadMessageEmbeddings
        self.loadMessageEmbedding = loadMessageEmbedding
        self.saveMessageEmbedding = saveMessageEmbedding
    }

    public func build(request: ConversationContextRequest) async -> ConversationContextBundle {
        guard let sessionID = request.sessionID else {
            return ConversationContextBundle(
                requestedMode: request.mode,
                effectiveMode: request.mode == .smart ? .smartDegraded : .simple,
                observations: [modeObservation(request.mode == .smart ? .smartDegraded : .simple)],
                diagnostics: ["reason": "no-session"])
        }
        do {
            let parts = try await loadMessageParts(sessionID, 500)
            switch request.mode {
            case .simple:
                return await simpleBundle(request: request, parts: parts, effectiveMode: .simple)
            case .smart:
                return try await smartBundle(request: request, parts: parts)
            }
        } catch {
            return ConversationContextBundle(
                requestedMode: request.mode,
                effectiveMode: request.mode == .smart ? .smartDegraded : .simple,
                observations: [modeObservation(request.mode == .smart ? .smartDegraded : .simple)],
                diagnostics: ["error": String(describing: error)])
        }
    }

    public func indexMessagePart(_ part: SessionMessagePart) async {
        guard isEmbeddable(part) else { return }
        do {
            guard try await loadMessageEmbedding(part.id) == nil else { return }
            guard let vector = try await embedTexts([embeddingText(for: part)])?.first,
                  !vector.isEmpty else { return }
            try await saveMessageEmbedding(SessionMessageEmbedding(
                sessionID: part.sessionID,
                partID: part.id,
                vector: vector))
        } catch {
            return
        }
    }

    public func compactIfNeeded(
        sessionID: UUID,
        mode: ConversationContextMode,
        now: Date = Date(),
        summarize: (@Sendable (String) async -> String?)? = nil
    ) async {
        do {
            let parts = try await loadMessageParts(sessionID, 500)
            let candidates = eligibleCandidates(from: parts, prompt: "")
            let tokenCount = estimateTokens(candidates.map(\.row).joined(separator: "\n\n"))
            guard candidates.count >= 24 || tokenCount >= 12_000 else { return }
            if let latest = try await loadLatestCompaction(sessionID),
               let coveredThrough = latest.coveredThrough,
               let newest = candidates.last?.part.createdAt,
               coveredThrough >= newest {
                return
            }
            let compacted = Array(candidates.dropLast(min(12, candidates.count)))
            guard !compacted.isEmpty else { return }
            // Prefer a model-written abstractive summary (preserves decisions,
            // paths, open tasks); degrade to the extractive prefix slice when no
            // summarizer is available or it returns nothing.
            let summary: String
            if let summarize,
               let abstractive = await summarize(compacted.map(\.row).joined(separator: "\n\n")),
               !abstractive.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                summary = String(abstractive.prefix(2_400))
            } else {
                summary = Self.extractiveSummary(from: compacted.map(\.row), maxCharacters: 2_400)
            }
            let recent = candidates.suffix(8).map(\.row).joined(separator: "\n\n")
            try await saveCompaction(SessionCompactionCheckpoint(
                sessionID: sessionID,
                summary: summary,
                recentContext: String(recent.prefix(2_000)),
                createdAt: now,
                coveredMessagePartIDs: compacted.map(\.part.id),
                coveredThrough: compacted.map(\.part.createdAt).max(),
                sourceMode: mode,
                estimatedTokens: estimateTokens(summary)))
        } catch {
            return
        }
    }

    public static func isLikelyContextDependent(_ prompt: String) -> Bool {
        let normalized = normalizedPrompt(prompt)
        guard !normalized.isEmpty else { return false }
        let standalone: Set<String> = [
            "hi", "hello", "hello there", "hey", "hey there", "hi there", "hiya", "yo",
            "good morning", "good afternoon", "good evening", "ok", "okay", "cool",
            "thanks", "thank you", "yes", "no", "sure"
        ]
        if standalone.contains(normalized) { return false }
        let explicitPhrases = [
            "tell me more", "continue", "go on", "expand", "elaborate", "summarize this",
            "explain that", "what about", "from above", "as above", "previous", "earlier",
            "the last", "same", "again", "rewrite it", "make it", "turn it", "that story",
            "this story", "our conversation", "we discussed", "you said"
        ]
        if explicitPhrases.contains(where: normalized.contains) { return true }
        let tokens = tokenSet(normalized)
        let references: Set<String> = [
            "it", "that", "this", "those", "these", "her", "him", "them", "they", "she",
            "he", "there", "above", "previous", "earlier", "same"
        ]
        return tokens.count <= 18 && !tokens.isDisjoint(with: references)
    }

    private func simpleBundle(
        request: ConversationContextRequest,
        parts: [SessionMessagePart],
        effectiveMode: EffectiveConversationContextMode
    ) async -> ConversationContextBundle {
        var observations = [modeObservation(effectiveMode)]
        guard Self.isLikelyContextDependent(request.prompt) else {
            return ConversationContextBundle(
                requestedMode: request.mode,
                effectiveMode: effectiveMode,
                observations: observations,
                diagnostics: ["reason": "latest-request-standalone"])
        }
        let tokenLimit = min(1_600, max(128, request.effectiveContextTokenCap / 5))
        let rows = boundedRecentRows(
            candidates: eligibleCandidates(from: parts, prompt: request.prompt),
            tokenLimit: tokenLimit)
        // Simple mode also consults the compaction checkpoint, so history older
        // than the trimmed transcript isn't simply gone.
        var summaryID: UUID?
        if let sessionID = request.sessionID,
           let checkpoint = try? await loadLatestCompaction(sessionID),
           !checkpoint.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            observations.append(
                "Conversation memory summary (background only; use only if relevant):\n"
                    + String(checkpoint.summary.prefix(1_600)))
            summaryID = checkpoint.id
        }
        if !rows.isEmpty {
            observations.append(priorConversationObservation(rows: rows))
        }
        return ConversationContextBundle(
            requestedMode: request.mode,
            effectiveMode: effectiveMode,
            observations: observations,
            includedMessagePartIDs: rows.map(\.part.id),
            summaryID: summaryID,
            estimatedTokens: estimateTokens(rows.map(\.row).joined(separator: "\n\n")),
            diagnostics: ["reason": rows.isEmpty ? "no-relevant-history" : "deterministic-follow-up"])
    }

    private func smartBundle(
        request: ConversationContextRequest,
        parts: [SessionMessagePart]
    ) async throws -> ConversationContextBundle {
        guard let queryVector = try await embedTexts(["conversation_query: \(request.prompt)"])?.first,
              !queryVector.isEmpty else {
            return await simpleBundle(request: request, parts: parts, effectiveMode: .smartDegraded)
        }
        let candidates = eligibleCandidates(from: parts, prompt: request.prompt)
        try await ensureEmbeddings(for: candidates)
        let embeddings = try await loadMessageEmbeddings(request.sessionID!, 500)
        let embeddingByPartID = Dictionary(uniqueKeysWithValues: embeddings.map { ($0.partID, $0.vector) })
        let promptTokens = Self.tokenSet(request.prompt)
        let scored = candidates.compactMap { candidate -> ScoredCandidate? in
            let lexical = lexicalScore(promptTokens: promptTokens, candidateTokens: candidate.tokens)
            let semantic = embeddingByPartID[candidate.part.id].map { max(0, queryVector.cosineSimilarity(to: $0)) } ?? 0
            guard semantic > 0 || lexical > 0 else { return nil }
            let recency = Double(candidate.index + 1) / Double(max(1, candidates.count))
            let score = (semantic * 0.70) + (lexical * 0.20) + (recency * 0.10)
            return ScoredCandidate(candidate: candidate, score: score)
        }
        let contextDependent = Self.isLikelyContextDependent(request.prompt)
        let threshold = contextDependent ? 0.14 : 0.28
        let hits = scored.sorted { lhs, rhs in
            if lhs.score == rhs.score { return lhs.candidate.index > rhs.candidate.index }
            return lhs.score > rhs.score
        }
        .filter { $0.score >= threshold }
        .prefix(contextDependent ? 6 : 4)
        let selected = adjacentCandidates(for: hits.map(\.candidate.index), candidates: candidates)
        let tokenLimit = request.isPlainChat
            ? min(2_000, max(256, request.effectiveContextTokenCap / 4))
            : min(4_000, max(512, Int(Double(request.effectiveContextTokenCap) * 0.35)))
        var observations = [modeObservation(.smart)]
        var summaryID: UUID?
        var usedTokens = 0
        if let summary = try await relevantSummary(
            sessionID: request.sessionID!,
            promptTokens: promptTokens,
            queryVector: queryVector,
            contextDependent: contextDependent,
            tokenLimit: tokenLimit / 2) {
            observations.append(summary.text)
            summaryID = summary.id
            usedTokens += estimateTokens(summary.text)
        }
        let remainingTokens = max(0, tokenLimit - usedTokens)
        let rows = boundedRecentRows(candidates: selected, tokenLimit: remainingTokens)
        if !rows.isEmpty {
            observations.append(priorConversationObservation(rows: rows))
        }
        return ConversationContextBundle(
            requestedMode: .smart,
            effectiveMode: .smart,
            observations: observations,
            includedMessagePartIDs: rows.map(\.part.id),
            summaryID: summaryID,
            estimatedTokens: usedTokens + estimateTokens(rows.map(\.row).joined(separator: "\n\n")),
            diagnostics: [
                "candidateCount": "\(candidates.count)",
                "hitCount": "\(hits.count)",
                "reason": rows.isEmpty && summaryID == nil ? "topic-change-or-no-relevant-history" : "semantic-retrieval",
            ])
    }

    private func ensureEmbeddings(for candidates: [Candidate]) async throws {
        let missing = try await candidates.asyncFilter { candidate in
            try await loadMessageEmbedding(candidate.part.id) == nil
        }
        let batch = Array(missing.prefix(48))
        guard !batch.isEmpty else { return }
        guard let vectors = try await embedTexts(batch.map { embeddingText(for: $0.part) }) else { return }
        for (candidate, vector) in zip(batch, vectors) where !vector.isEmpty {
            try await saveMessageEmbedding(SessionMessageEmbedding(
                sessionID: candidate.part.sessionID,
                partID: candidate.part.id,
                vector: vector))
        }
    }

    private func relevantSummary(
        sessionID: UUID,
        promptTokens: Set<String>,
        queryVector: EmbeddingVector,
        contextDependent: Bool,
        tokenLimit: Int
    ) async throws -> (id: UUID, text: String)? {
        guard tokenLimit > 0,
              let checkpoint = try await loadLatestCompaction(sessionID),
              !checkpoint.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let summaryTokens = Self.tokenSet(checkpoint.summary)
        let lexical = lexicalScore(promptTokens: promptTokens, candidateTokens: summaryTokens)
        let include = contextDependent || lexical >= 0.08 || queryVector.isEmpty == false && lexical >= 0.04
        guard include else { return nil }
        let text = "Conversation memory summary (background only; use only if relevant):\n"
            + Self.truncate(checkpoint.summary, tokenLimit: tokenLimit)
        return (checkpoint.id, text)
    }

    private func adjacentCandidates(
        for selectedIndices: [Int],
        candidates: [Candidate]
    ) -> [Candidate] {
        guard !selectedIndices.isEmpty else { return [] }
        var indices = Set<Int>()
        for index in selectedIndices {
            indices.insert(index)
            indices.insert(index - 1)
            indices.insert(index + 1)
        }
        return candidates
            .filter { indices.contains($0.index) }
            .sorted { $0.index < $1.index }
    }

    private func eligibleCandidates(from parts: [SessionMessagePart], prompt: String) -> [Candidate] {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        var result: [Candidate] = []
        for part in parts {
            guard isEmbeddable(part) else { continue }
            let trimmed = part.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if part.role == .user, trimmed == trimmedPrompt, part == parts.last(where: { $0.role == .user }) {
                continue
            }
            let row: String
            switch part.role {
            case .user:
                row = "User: \(trimmed)"
            case .assistant:
                row = "Assistant: \(trimmed)"
            case .system, .tool:
                continue
            }
            result.append(Candidate(
                index: result.count,
                part: part,
                row: row,
                tokens: Self.tokenSet(trimmed)))
        }
        return result
    }

    private func boundedRecentRows(candidates: [Candidate], tokenLimit: Int) -> [Candidate] {
        guard tokenLimit > 0 else { return [] }
        var selected: [Candidate] = []
        var used = 0
        for candidate in candidates.reversed() {
            let candidateTokens = estimateTokens(candidate.row)
            if used + candidateTokens <= tokenLimit {
                selected.append(candidate)
                used += candidateTokens
                continue
            }
            if selected.isEmpty {
                var truncated = candidate
                truncated.row = Self.truncate(candidate.row, tokenLimit: tokenLimit)
                selected.append(truncated)
            }
            break
        }
        return selected.reversed()
    }

    private func priorConversationObservation(rows: [Candidate]) -> String {
        "Relevant prior conversation (background only; ignore if unrelated to the latest request):\n"
            + rows.map(\.row).joined(separator: "\n\n")
    }

    private func modeObservation(_ mode: EffectiveConversationContextMode) -> String {
        "Conversation context mode: \(mode.rawValue)"
    }

    private func isEmbeddable(_ part: SessionMessagePart) -> Bool {
        guard part.role == .user || part.role == .assistant else { return false }
        guard !["tool", "error", "cancelled"].contains(part.kind) else { return false }
        return !part.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func embeddingText(for part: SessionMessagePart) -> String {
        "\(part.role.rawValue): \(part.text)"
    }

    private func lexicalScore(promptTokens: Set<String>, candidateTokens: Set<String>) -> Double {
        guard !promptTokens.isEmpty, !candidateTokens.isEmpty else { return 0 }
        let overlap = promptTokens.intersection(candidateTokens).count
        return Double(overlap) / Double(max(promptTokens.count, 1))
    }

    private func estimateTokens(_ text: String) -> Int {
        max(1, Int(ceil(Double(text.count) / 4.0)))
    }

    private static func extractiveSummary(from rows: [String], maxCharacters: Int) -> String {
        let joined = rows.joined(separator: "\n\n")
        guard joined.count > maxCharacters else { return joined }
        return String(joined.prefix(maxCharacters)) + "\n[summary truncated]"
    }

    private static func truncate(_ text: String, tokenLimit: Int) -> String {
        let characterLimit = max(0, tokenLimit * 4)
        guard text.count > characterLimit else { return text }
        guard characterLimit > 20 else { return String(text.prefix(characterLimit)) }
        return String(text.prefix(characterLimit - 12)) + "\n[truncated]"
    }

    private static func normalizedPrompt(_ prompt: String) -> String {
        prompt
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!,?;:"))
    }

    private static func tokenSet(_ text: String) -> Set<String> {
        let separators = CharacterSet.alphanumerics.inverted
        return Set(text
            .lowercased()
            .components(separatedBy: separators)
            .filter { $0.count >= 2 }
            .filter { !stopWords.contains($0) })
    }

    private static let stopWords: Set<String> = [
        "the", "and", "for", "with", "that", "this", "you", "are", "was", "were",
        "have", "has", "had", "but", "not", "can", "could", "would", "should",
        "about", "into", "from", "your", "our", "their", "there", "what", "when",
        "where", "which", "who", "why", "how", "please", "write", "make"
    ]
}

private extension Array {
    func asyncFilter(_ include: (Element) async throws -> Bool) async throws -> [Element] {
        var result: [Element] = []
        for element in self {
            if try await include(element) {
                result.append(element)
            }
        }
        return result
    }
}
