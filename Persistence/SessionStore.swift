import Foundation
import GRDB
import Core
import Shared

public final class GRDBSessionStore: SessionRuntimeStore {
    private let dbWriter: any DatabaseWriter
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(dbWriter: any DatabaseWriter) {
        self.dbWriter = dbWriter
    }

    public func createSession(id: UUID?, workspacePath: String?, title: String) async throws -> SessionRecord {
        let sessionID = id ?? UUID()
        let now = Date()
        try await dbWriter.write { db in
            try db.execute(sql: """
                INSERT OR IGNORE INTO native_session (
                    id, workspacePath, title, createdAt, updatedAt, isInterrupted
                ) VALUES (?, ?, ?, ?, ?, 0)
                """, arguments: [
                    sessionID.uuidString,
                    workspacePath,
                    title,
                    now.timeIntervalSince1970,
                    now.timeIntervalSince1970,
                ])
        }
        guard let record = try await session(id: sessionID) else {
            throw SessionRuntimeError.sessionNotFound(sessionID)
        }
        return record
    }

    public func session(id: UUID) async throws -> SessionRecord? {
        try await dbWriter.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM native_session WHERE id = ?", arguments: [id.uuidString])
                .flatMap(Self.session)
        }
    }

    public func recentSessions(limit: Int, workspacePath: String?) async throws -> [SessionRecord] {
        try await dbWriter.read { db in
            let rows: [Row]
            if let workspacePath {
                rows = try Row.fetchAll(db, sql: """
                    SELECT * FROM native_session
                    WHERE workspacePath = ?
                    ORDER BY updatedAt DESC
                    LIMIT ?
                    """, arguments: [workspacePath, max(0, limit)])
            } else {
                rows = try Row.fetchAll(db, sql: """
                    SELECT * FROM native_session
                    ORDER BY updatedAt DESC
                    LIMIT ?
                    """, arguments: [max(0, limit)])
            }
            return rows.compactMap(Self.session)
        }
    }

    public func renameSession(id: UUID, title: String) async throws {
        try await dbWriter.write { db in
            guard try Row.fetchOne(db, sql: "SELECT id FROM native_session WHERE id = ?", arguments: [id.uuidString]) != nil else {
                throw SessionRuntimeError.sessionNotFound(id)
            }
            let now = Date()
            try db.execute(sql: """
                UPDATE native_session
                SET title = ?, updatedAt = ?
                WHERE id = ?
                """, arguments: [title, now.timeIntervalSince1970, id.uuidString])
        }
    }

    public func deleteSession(id: UUID) async throws {
        try await dbWriter.write { db in
            guard try Row.fetchOne(db, sql: "SELECT id FROM native_session WHERE id = ?", arguments: [id.uuidString]) != nil else {
                throw SessionRuntimeError.sessionNotFound(id)
            }
            try db.execute(sql: "DELETE FROM native_session WHERE id = ?", arguments: [id.uuidString])
        }
    }

    public func admitInput(_ input: SessionInputRecord) async throws -> SessionInputRecord {
        try await dbWriter.write { db in
            if let existing = try Row.fetchOne(db, sql: "SELECT * FROM session_input WHERE id = ?", arguments: [input.id.uuidString])
                .flatMap(Self.input) {
                guard existing.sessionID == input.sessionID,
                      existing.prompt == input.prompt,
                      existing.delivery == input.delivery,
                      existing.resume == input.resume else {
                    throw SessionRuntimeError.inputConflict(input.id)
                }
                return existing
            }
            guard try Row.fetchOne(db, sql: "SELECT id FROM native_session WHERE id = ?", arguments: [input.sessionID.uuidString]) != nil else {
                throw SessionRuntimeError.sessionNotFound(input.sessionID)
            }
            try db.execute(sql: """
                INSERT INTO session_input (
                    id, sessionID, prompt, delivery, resume, status, createdAt, promotedAt
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [
                    input.id.uuidString,
                    input.sessionID.uuidString,
                    input.prompt,
                    input.delivery.rawValue,
                    input.resume ? 1 : 0,
                    input.status.rawValue,
                    input.createdAt.timeIntervalSince1970,
                    input.promotedAt?.timeIntervalSince1970,
                ])
            try Self.touchSession(db, id: input.sessionID, updatedAt: input.createdAt)
            return input
        }
    }

    public func pendingInputs(sessionID: UUID, limit: Int) async throws -> [SessionInputRecord] {
        try await dbWriter.read { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM session_input
                WHERE sessionID = ? AND status = ?
                ORDER BY createdAt ASC
                LIMIT ?
                """, arguments: [sessionID.uuidString, SessionInputStatus.pending.rawValue, max(0, limit)])
                .compactMap(Self.input)
        }
    }

    public func markInputPromoted(id: UUID, promotedAt: Date) async throws {
        try await dbWriter.write { db in
            try db.execute(literal: """
                UPDATE session_input
                SET status = \(SessionInputStatus.promoted.rawValue), promotedAt = \(promotedAt.timeIntervalSince1970)
                WHERE id = \(id.uuidString)
                """)
        }
    }

    public func appendMessagePart(_ part: SessionMessagePart) async throws {
        try await dbWriter.write { db in
            try db.execute(sql: """
                INSERT INTO session_message_part (
                    id, sessionID, messageID, role, kind, text, createdAt, modelID, reasoningEffort
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [
                    part.id.uuidString,
                    part.sessionID.uuidString,
                    part.messageID.uuidString,
                    part.role.rawValue,
                    part.kind,
                    part.text,
                    part.createdAt.timeIntervalSince1970,
                    part.modelID,
                    part.reasoningEffort?.rawValue,
                ])
            try Self.touchSession(db, id: part.sessionID, updatedAt: part.createdAt)
        }
    }

    public func messageParts(sessionID: UUID, limit: Int) async throws -> [SessionMessagePart] {
        try await dbWriter.read { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM session_message_part
                WHERE sessionID = ?
                ORDER BY createdAt ASC
                LIMIT ?
                """, arguments: [sessionID.uuidString, max(0, limit)])
                .compactMap(Self.messagePart)
        }
    }

    public func upsertMessageEmbedding(_ embedding: SessionMessageEmbedding) async throws {
        guard !embedding.vector.isEmpty else { return }
        let data = Self.encode(embedding.vector.values)
        try await dbWriter.write { db in
            try db.execute(sql: """
                INSERT INTO session_message_embedding (
                    partID, sessionID, dimensions, vector, updatedAt
                ) VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(partID) DO UPDATE SET
                    sessionID = excluded.sessionID,
                    dimensions = excluded.dimensions,
                    vector = excluded.vector,
                    updatedAt = excluded.updatedAt
                """, arguments: [
                    embedding.partID.uuidString,
                    embedding.sessionID.uuidString,
                    embedding.vector.dimensions,
                    data,
                    embedding.updatedAt.timeIntervalSince1970,
                ])
        }
    }

    public func messageEmbeddings(sessionID: UUID, limit: Int) async throws -> [SessionMessageEmbedding] {
        try await dbWriter.read { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM session_message_embedding
                WHERE sessionID = ?
                ORDER BY updatedAt DESC
                LIMIT ?
                """, arguments: [sessionID.uuidString, max(0, limit)])
                .compactMap(Self.messageEmbedding)
        }
    }

    public func messageEmbedding(partID: UUID) async throws -> SessionMessageEmbedding? {
        try await dbWriter.read { db in
            try Row.fetchOne(db, sql: """
                SELECT * FROM session_message_embedding
                WHERE partID = ?
                LIMIT 1
                """, arguments: [partID.uuidString])
                .flatMap(Self.messageEmbedding)
        }
    }

    /// Top-`limit` message parts of the session by cosine similarity to `vector`,
    /// over the ENTIRE session (no recent-N cap). Streams rows with a cursor and a
    /// bounded heap so peak memory is O(limit), and dot-products the stored BLOB
    /// directly (vectors are normalized on write, so dot == cosine). Returned best
    /// (most similar) first.
    public func semanticMessageSearch(
        sessionID: UUID,
        vector: EmbeddingVector,
        limit: Int
    ) async throws -> [SessionMessagePart] {
        guard !vector.isEmpty, limit > 0 else { return [] }
        let query = vector.values
        return try await dbWriter.read { db in
            let cursor = try Row.fetchCursor(db, sql: """
                SELECT p.*, e.vector AS embVector
                FROM session_message_embedding e
                JOIN session_message_part p ON p.id = e.partID
                WHERE e.sessionID = ?
                """, arguments: [sessionID.uuidString])
            // Descending by similarity; worst kept last so it can be dropped.
            var top: [(score: Double, part: SessionMessagePart)] = []
            top.reserveCapacity(limit + 1)
            while let row = try cursor.next() {
                let data: Data = row["embVector"]
                guard let similarity = Self.dotProduct(data, query),
                      let part = Self.messagePart(row) else { continue }
                if top.count >= limit, let worst = top.last, similarity <= worst.score { continue }
                Self.insertByScoreDescending(&top, (similarity, part))
                if top.count > limit { top.removeLast() }
            }
            return top.map(\.part)
        }
    }

    public func replaceTodos(_ todos: [SessionTodo], sessionID: UUID) async throws {
        try await dbWriter.write { db in
            try db.execute(sql: "DELETE FROM session_todo WHERE sessionID = ?", arguments: [sessionID.uuidString])
            for todo in todos {
                try db.execute(sql: """
                    INSERT INTO session_todo (id, sessionID, title, status, updatedAt)
                    VALUES (?, ?, ?, ?, ?)
                    """, arguments: [
                        todo.id.uuidString,
                        sessionID.uuidString,
                        todo.title,
                        todo.status.rawValue,
                        todo.updatedAt.timeIntervalSince1970,
                    ])
            }
            try Self.touchSession(db, id: sessionID, updatedAt: todos.map(\.updatedAt).max() ?? Date())
        }
    }

    public func todos(sessionID: UUID) async throws -> [SessionTodo] {
        try await dbWriter.read { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM session_todo
                WHERE sessionID = ?
                ORDER BY updatedAt ASC
                """, arguments: [sessionID.uuidString])
                .compactMap(Self.todo)
        }
    }

    public func saveCompaction(_ checkpoint: SessionCompactionCheckpoint) async throws {
        let coveredIDsJSON = try String(data: encoder.encode(checkpoint.coveredMessagePartIDs.map(\.uuidString)), encoding: .utf8)
        try await dbWriter.write { db in
            try db.execute(sql: """
                INSERT INTO session_compaction (
                    id, sessionID, summary, recentContext, createdAt,
                    coveredMessagePartIDsJSON, coveredThrough, sourceMode, estimatedTokens
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [
                    checkpoint.id.uuidString,
                    checkpoint.sessionID.uuidString,
                    checkpoint.summary,
                    checkpoint.recentContext,
                    checkpoint.createdAt.timeIntervalSince1970,
                    coveredIDsJSON,
                    checkpoint.coveredThrough?.timeIntervalSince1970,
                    checkpoint.sourceMode?.rawValue,
                    checkpoint.estimatedTokens,
                ])
            try Self.touchSession(db, id: checkpoint.sessionID, updatedAt: checkpoint.createdAt)
        }
    }

    public func latestCompaction(sessionID: UUID) async throws -> SessionCompactionCheckpoint? {
        try await dbWriter.read { db in
            try Row.fetchOne(db, sql: """
                SELECT * FROM session_compaction
                WHERE sessionID = ?
                ORDER BY createdAt DESC
                LIMIT 1
                """, arguments: [sessionID.uuidString])
                .flatMap(Self.compaction)
        }
    }

    public func appendEvent(_ event: SessionEvent) async throws -> SessionEvent {
        try await dbWriter.write { db in
            let next = try (Int64.fetchOne(db, sql: """
                SELECT COALESCE(MAX(sequence), 0) + 1
                FROM session_event
                WHERE sessionID = ?
                """, arguments: [event.sessionID.uuidString]) ?? 1)
            var saved = event
            saved.sequence = next
            try db.execute(sql: """
                INSERT INTO session_event (
                    id, sessionID, sequence, kind, messageID, payloadJSON, createdAt
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                """, arguments: [
                    saved.id.uuidString,
                    saved.sessionID.uuidString,
                    saved.sequence,
                    saved.kind.rawValue,
                    saved.messageID?.uuidString,
                    String(decoding: try encoder.encode(saved.payload), as: UTF8.self),
                    saved.createdAt.timeIntervalSince1970,
                ])
            try Self.touchSession(db, id: saved.sessionID, updatedAt: saved.createdAt)
            return saved
        }
    }

    public func events(sessionID: UUID, after cursor: SessionEventCursor?, limit: Int) async throws -> [SessionEvent] {
        try await dbWriter.read { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM session_event
                WHERE sessionID = ? AND sequence > ?
                ORDER BY sequence ASC
                LIMIT ?
                """, arguments: [sessionID.uuidString, cursor?.sequence ?? 0, max(0, limit)])
                .compactMap { row in
                    try Self.event(row, decoder: decoder)
                }
        }
    }

    public func interrupt(sessionID: UUID) async throws {
        try await dbWriter.write { db in
            guard try Row.fetchOne(db, sql: "SELECT id FROM native_session WHERE id = ?", arguments: [sessionID.uuidString]) != nil else {
                throw SessionRuntimeError.sessionNotFound(sessionID)
            }
            let now = Date()
            try db.execute(sql: """
                UPDATE native_session
                SET isInterrupted = 1, updatedAt = ?
                WHERE id = ?
                """, arguments: [now.timeIntervalSince1970, sessionID.uuidString])
            try db.execute(sql: """
                UPDATE session_input
                SET status = ?
                WHERE sessionID = ? AND status = ?
                """, arguments: [
                    SessionInputStatus.interrupted.rawValue,
                    sessionID.uuidString,
                    SessionInputStatus.pending.rawValue,
                ])
        }
    }

    private static func touchSession(_ db: Database, id: UUID, updatedAt: Date) throws {
        try db.execute(sql: """
            UPDATE native_session
            SET updatedAt = ?
            WHERE id = ?
            """, arguments: [updatedAt.timeIntervalSince1970, id.uuidString])
    }

    private static func session(_ row: Row) -> SessionRecord? {
        guard let id = UUID(uuidString: row["id"] as String) else { return nil }
        let workspacePath: String? = row["workspacePath"]
        let title: String = row["title"]
        let createdAt: Double = row["createdAt"]
        let updatedAt: Double = row["updatedAt"]
        let isInterrupted: Bool = (row["isInterrupted"] as Int) != 0
        return SessionRecord(
            id: id,
            workspacePath: workspacePath,
            title: title,
            createdAt: Date(timeIntervalSince1970: createdAt),
            updatedAt: Date(timeIntervalSince1970: updatedAt),
            isInterrupted: isInterrupted)
    }

    private static func input(_ row: Row) -> SessionInputRecord? {
        guard let id = UUID(uuidString: row["id"] as String),
              let sessionID = UUID(uuidString: row["sessionID"] as String),
              let delivery = SessionInputDelivery(rawValue: row["delivery"] as String),
              let status = SessionInputStatus(rawValue: row["status"] as String) else {
            return nil
        }
        let prompt: String = row["prompt"]
        let resume: Bool = (row["resume"] as Int) != 0
        let createdAt: Double = row["createdAt"]
        let promotedAt: Double? = row["promotedAt"]
        return SessionInputRecord(
            id: id,
            sessionID: sessionID,
            prompt: prompt,
            delivery: delivery,
            resume: resume,
            status: status,
            createdAt: Date(timeIntervalSince1970: createdAt),
            promotedAt: promotedAt.map(Date.init(timeIntervalSince1970:)))
    }

    private static func messagePart(_ row: Row) -> SessionMessagePart? {
        guard let id = UUID(uuidString: row["id"] as String),
              let sessionID = UUID(uuidString: row["sessionID"] as String),
              let messageID = UUID(uuidString: row["messageID"] as String),
              let role = SessionMessageRole(rawValue: row["role"] as String) else {
            return nil
        }
        let kind: String = row["kind"]
        let text: String = row["text"]
        let createdAt: Double = row["createdAt"]
        return SessionMessagePart(
            id: id,
            sessionID: sessionID,
            messageID: messageID,
            role: role,
            kind: kind,
            text: text,
            createdAt: Date(timeIntervalSince1970: createdAt),
            modelID: row["modelID"] as String?,
            reasoningEffort: (row["reasoningEffort"] as String?).flatMap(ReasoningEffort.init(rawValue:)))
    }

    private static func todo(_ row: Row) -> SessionTodo? {
        guard let id = UUID(uuidString: row["id"] as String),
              let sessionID = UUID(uuidString: row["sessionID"] as String),
              let status = SessionTodo.Status(rawValue: row["status"] as String) else {
            return nil
        }
        let title: String = row["title"]
        let updatedAt: Double = row["updatedAt"]
        return SessionTodo(
            id: id,
            sessionID: sessionID,
            title: title,
            status: status,
            updatedAt: Date(timeIntervalSince1970: updatedAt))
    }

    private static func compaction(_ row: Row) -> SessionCompactionCheckpoint? {
        guard let id = UUID(uuidString: row["id"] as String),
              let sessionID = UUID(uuidString: row["sessionID"] as String) else {
            return nil
        }
        let summary: String = row["summary"]
        let recentContext: String = row["recentContext"]
        let createdAt: Double = row["createdAt"]
        let coveredIDsJSON: String? = row["coveredMessagePartIDsJSON"]
        let coveredIDs = coveredIDsJSON
            .flatMap { try? JSONDecoder().decode([String].self, from: Data($0.utf8)) }
            .map { $0.compactMap(UUID.init(uuidString:)) } ?? []
        let coveredThrough: Double? = row["coveredThrough"]
        let sourceMode: String? = row["sourceMode"]
        let estimatedTokens: Int = row["estimatedTokens"] ?? 0
        return SessionCompactionCheckpoint(
            id: id,
            sessionID: sessionID,
            summary: summary,
            recentContext: recentContext,
            createdAt: Date(timeIntervalSince1970: createdAt),
            coveredMessagePartIDs: coveredIDs,
            coveredThrough: coveredThrough.map(Date.init(timeIntervalSince1970:)),
            sourceMode: sourceMode.flatMap(ConversationContextMode.init(rawValue:)),
            estimatedTokens: estimatedTokens)
    }

    private static func messageEmbedding(_ row: Row) -> SessionMessageEmbedding? {
        guard let sessionID = UUID(uuidString: row["sessionID"] as String),
              let partID = UUID(uuidString: row["partID"] as String) else {
            return nil
        }
        let dimensions: Int = row["dimensions"]
        let data: Data = row["vector"]
        let values = decode(data)
        guard dimensions == values.count else { return nil }
        let updatedAt: Double = row["updatedAt"]
        return SessionMessageEmbedding(
            sessionID: sessionID,
            partID: partID,
            vector: EmbeddingVector(values),
            updatedAt: Date(timeIntervalSince1970: updatedAt))
    }

    private static func event(_ row: Row, decoder: JSONDecoder) throws -> SessionEvent? {
        guard let id = UUID(uuidString: row["id"] as String),
              let sessionID = UUID(uuidString: row["sessionID"] as String),
              let kind = SessionEventKind(rawValue: row["kind"] as String) else {
            return nil
        }
        let sequence: Int64 = row["sequence"]
        let messageIDString: String? = row["messageID"]
        let payloadJSON: String = row["payloadJSON"]
        let createdAt: Double = row["createdAt"]
        let payload = (try? decoder.decode([String: String].self, from: Data(payloadJSON.utf8))) ?? [:]
        return SessionEvent(
            id: id,
            sessionID: sessionID,
            sequence: sequence,
            kind: kind,
            messageID: messageIDString.flatMap(UUID.init(uuidString:)),
            payload: payload,
            createdAt: Date(timeIntervalSince1970: createdAt))
    }

    private static func encode(_ values: [Float]) -> Data {
        values.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private static func decode(_ data: Data) -> [Float] {
        let count = data.count / MemoryLayout<Float>.stride
        guard count > 0 else { return [] }
        return data.withUnsafeBytes { buffer in
            guard let base = buffer.bindMemory(to: Float.self).baseAddress else { return [] }
            return Array(UnsafeBufferPointer(start: base, count: count))
        }
    }

    /// Dot product of a stored (normalized) Float BLOB with the normalized query,
    /// without materializing a `[Float]` per row. nil on dimension mismatch.
    private static func dotProduct(_ data: Data, _ query: [Float]) -> Double? {
        let count = data.count / MemoryLayout<Float>.stride
        guard count == query.count, count > 0 else { return nil }
        let sum: Float = data.withUnsafeBytes { raw in
            let stored = raw.bindMemory(to: Float.self)
            var acc: Float = 0
            for index in 0..<count { acc += stored[index] * query[index] }
            return acc
        }
        return Double(sum)
    }

    /// Insert into an array kept sorted by `score` descending (binary search).
    private static func insertByScoreDescending(
        _ array: inout [(score: Double, part: SessionMessagePart)],
        _ element: (score: Double, part: SessionMessagePart)
    ) {
        var low = 0
        var high = array.count
        while low < high {
            let mid = (low + high) / 2
            if array[mid].score > element.score { low = mid + 1 } else { high = mid }
        }
        array.insert(element, at: low)
    }
}
