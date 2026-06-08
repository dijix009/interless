import Foundation
import GRDB

public enum ConversationMode: String, Sendable, Equatable, Codable, Hashable {
    case chat
    case code
}

public struct PersistedConversation: Sendable, Equatable, Codable, Identifiable {
    public var id: UUID
    public var title: String
    public var workspacePath: String?
    public var mode: ConversationMode
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID,
        title: String,
        workspacePath: String?,
        mode: ConversationMode,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.workspacePath = workspacePath
        self.mode = mode
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct PersistedConversationMessage: Sendable, Equatable, Codable, Identifiable {
    public var id: UUID
    public var conversationID: UUID
    public var role: String
    public var text: String
    public var tokensPerSecond: Double?
    public var createdAt: Date

    public init(
        id: UUID,
        conversationID: UUID,
        role: String,
        text: String,
        tokensPerSecond: Double? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.conversationID = conversationID
        self.role = role
        self.text = text
        self.tokensPerSecond = tokensPerSecond
        self.createdAt = createdAt
    }
}

public struct PromptHistoryEntry: Sendable, Equatable, Codable, Identifiable {
    public var id: UUID
    public var prompt: String
    public var workspacePath: String?
    public var mode: ConversationMode
    public var createdAt: Date

    public init(id: UUID, prompt: String, workspacePath: String?, mode: ConversationMode, createdAt: Date) {
        self.id = id
        self.prompt = prompt
        self.workspacePath = workspacePath
        self.mode = mode
        self.createdAt = createdAt
    }
}

public struct ModelAssignment: Sendable, Equatable, Codable, Identifiable {
    public var id: String { role }
    public var role: String
    public var modelID: String
    public var quantization: Int
    public var updatedAt: Date

    public init(role: String, modelID: String, quantization: Int, updatedAt: Date = Date()) {
        self.role = role
        self.modelID = modelID
        self.quantization = quantization
        self.updatedAt = updatedAt
    }
}

public protocol AppStore: Sendable {
    func createConversation(title: String, workspacePath: String?, mode: ConversationMode) async throws -> UUID
    func conversation(id: UUID) async throws -> PersistedConversation?
    func appendMessage(conversationID: UUID, role: String, text: String, createdAt: Date, tokensPerSecond: Double?) async throws
    func recentConversations(limit: Int, mode: ConversationMode?) async throws -> [PersistedConversation]
    func messages(conversationID: UUID) async throws -> [PersistedConversationMessage]
    func renameConversation(_ id: UUID, title: String) async throws
    func deleteConversation(_ id: UUID) async throws
    func recordPrompt(_ prompt: String, workspacePath: String?, mode: ConversationMode) async throws
    func recentPrompts(limit: Int, mode: ConversationMode?) async throws -> [PromptHistoryEntry]
    func saveModelAssignment(_ assignment: ModelAssignment) async throws
    func modelAssignments() async throws -> [ModelAssignment]
    func clearHistory() async throws
}

public extension AppStore {
    func appendMessage(conversationID: UUID, role: String, text: String, createdAt: Date) async throws {
        try await appendMessage(
            conversationID: conversationID,
            role: role,
            text: text,
            createdAt: createdAt,
            tokensPerSecond: nil)
    }

    func createConversation(title: String, workspacePath: String?) async throws -> UUID {
        try await createConversation(
            title: title,
            workspacePath: workspacePath,
            mode: workspacePath == nil ? .chat : .code)
    }

    func recentConversations(limit: Int) async throws -> [PersistedConversation] {
        try await recentConversations(limit: limit, mode: nil)
    }

    func recordPrompt(_ prompt: String, workspacePath: String?) async throws {
        try await recordPrompt(prompt, workspacePath: workspacePath, mode: workspacePath == nil ? .chat : .code)
    }

    func recentPrompts(limit: Int) async throws -> [PromptHistoryEntry] {
        try await recentPrompts(limit: limit, mode: nil)
    }
}

public final class GRDBAppStore: AppStore {
    private let dbWriter: any DatabaseWriter

    public init(dbWriter: any DatabaseWriter) {
        self.dbWriter = dbWriter
    }

    public func createConversation(title: String, workspacePath: String?, mode: ConversationMode) async throws -> UUID {
        let id = UUID()
        let now = Date()
        try await dbWriter.write { db in
            try db.execute(sql: """
                INSERT INTO conversation (id, title, workspacePath, mode, createdAt, updatedAt)
                VALUES (?, ?, ?, ?, ?, ?)
                """, arguments: [id.uuidString, title, workspacePath, mode.rawValue, now.timeIntervalSince1970, now.timeIntervalSince1970])
        }
        return id
    }

    public func conversation(id: UUID) async throws -> PersistedConversation? {
        try await dbWriter.read { db in
            try Row.fetchOne(db, sql: """
                SELECT id, title, workspacePath, mode, createdAt, updatedAt
                FROM conversation
                WHERE id = ?
                """, arguments: [id.uuidString]).flatMap(Self.conversation)
        }
    }

    public func appendMessage(
        conversationID: UUID,
        role: String,
        text: String,
        createdAt: Date = Date(),
        tokensPerSecond: Double? = nil
    ) async throws {
        let id = UUID()
        try await dbWriter.write { db in
            try db.execute(sql: """
                INSERT INTO conversation_message (id, conversationID, role, text, tokensPerSecond, createdAt)
                VALUES (?, ?, ?, ?, ?, ?)
                """, arguments: [id.uuidString, conversationID.uuidString, role, text, tokensPerSecond, createdAt.timeIntervalSince1970])
            try db.execute(sql: """
                UPDATE conversation SET updatedAt = ? WHERE id = ?
                """, arguments: [createdAt.timeIntervalSince1970, conversationID.uuidString])
        }
    }

    public func recentConversations(limit: Int, mode: ConversationMode? = nil) async throws -> [PersistedConversation] {
        try await dbWriter.read { db in
            let arguments: StatementArguments
            let modeFilter: String
            if let mode {
                arguments = [mode.rawValue, max(0, limit)]
                modeFilter = "WHERE mode = ?"
            } else {
                arguments = [max(0, limit)]
                modeFilter = ""
            }
            return try Row.fetchAll(db, sql: """
                SELECT id, title, workspacePath, mode, createdAt, updatedAt
                FROM conversation
                \(modeFilter)
                ORDER BY updatedAt DESC
                LIMIT ?
                """, arguments: arguments).compactMap(Self.conversation)
        }
    }

    public func messages(conversationID: UUID) async throws -> [PersistedConversationMessage] {
        try await dbWriter.read { db in
            return try Row.fetchAll(db, sql: """
                SELECT id, conversationID, role, text, tokensPerSecond, createdAt
                FROM conversation_message
                WHERE conversationID = ?
                ORDER BY createdAt ASC
                """, arguments: [conversationID.uuidString]).compactMap(Self.message)
        }
    }

    public func renameConversation(_ id: UUID, title: String) async throws {
        let now = Date()
        try await dbWriter.write { db in
            try db.execute(sql: """
                UPDATE conversation SET title = ?, updatedAt = ? WHERE id = ?
                """, arguments: [title, now.timeIntervalSince1970, id.uuidString])
        }
    }

    public func deleteConversation(_ id: UUID) async throws {
        try await dbWriter.write { db in
            try db.execute(sql: "DELETE FROM conversation_message WHERE conversationID = ?", arguments: [id.uuidString])
            try db.execute(sql: "DELETE FROM conversation WHERE id = ?", arguments: [id.uuidString])
        }
    }

    public func recordPrompt(_ prompt: String, workspacePath: String?, mode: ConversationMode) async throws {
        let id = UUID()
        let now = Date()
        try await dbWriter.write { db in
            try db.execute(sql: """
                INSERT INTO prompt_history (id, prompt, workspacePath, mode, createdAt)
                VALUES (?, ?, ?, ?, ?)
                """, arguments: [id.uuidString, prompt, workspacePath, mode.rawValue, now.timeIntervalSince1970])
        }
    }

    public func recentPrompts(limit: Int, mode: ConversationMode? = nil) async throws -> [PromptHistoryEntry] {
        try await dbWriter.read { db in
            let arguments: StatementArguments
            let modeFilter: String
            if let mode {
                arguments = [mode.rawValue, max(0, limit)]
                modeFilter = "WHERE mode = ?"
            } else {
                arguments = [max(0, limit)]
                modeFilter = ""
            }
            return try Row.fetchAll(db, sql: """
                SELECT id, prompt, workspacePath, mode, createdAt
                FROM prompt_history
                \(modeFilter)
                ORDER BY createdAt DESC
                LIMIT ?
                """, arguments: arguments).compactMap(Self.prompt)
        }
    }

    public func saveModelAssignment(_ assignment: ModelAssignment) async throws {
        try await dbWriter.write { db in
            try db.execute(sql: """
                INSERT INTO model_assignment (role, modelID, quantization, updatedAt)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(role) DO UPDATE SET
                    modelID = excluded.modelID,
                    quantization = excluded.quantization,
                    updatedAt = excluded.updatedAt
                """, arguments: [
                    assignment.role,
                    assignment.modelID,
                    assignment.quantization,
                    assignment.updatedAt.timeIntervalSince1970,
                ])
        }
    }

    public func modelAssignments() async throws -> [ModelAssignment] {
        try await dbWriter.read { db in
            try Row.fetchAll(db, sql: """
                SELECT role, modelID, quantization, updatedAt
                FROM model_assignment
                ORDER BY role
                """).map {
                    let role: String = $0["role"]
                    let modelID: String = $0["modelID"]
                    let quantization: Int = $0["quantization"]
                    let updatedAt: Double = $0["updatedAt"]
                    return ModelAssignment(
                        role: role,
                        modelID: modelID,
                        quantization: quantization,
                        updatedAt: Date(timeIntervalSince1970: updatedAt))
                }
        }
    }

    public func clearHistory() async throws {
        try await dbWriter.write { db in
            try db.execute(sql: "DELETE FROM conversation_message")
            try db.execute(sql: "DELETE FROM conversation")
            try db.execute(sql: "DELETE FROM prompt_history")
        }
    }

    private static func conversation(_ row: Row) -> PersistedConversation? {
        let idString: String = row["id"]
        let title: String = row["title"]
        let workspacePath: String? = row["workspacePath"]
        let modeString: String = row["mode"]
        let createdAt: Double = row["createdAt"]
        let updatedAt: Double = row["updatedAt"]
        guard let id = UUID(uuidString: idString),
              let mode = ConversationMode(rawValue: modeString) else { return nil }
        return PersistedConversation(
            id: id,
            title: title,
            workspacePath: workspacePath,
            mode: mode,
            createdAt: Date(timeIntervalSince1970: createdAt),
            updatedAt: Date(timeIntervalSince1970: updatedAt))
    }

    private static func message(_ row: Row) -> PersistedConversationMessage? {
        let idString: String = row["id"]
        let conversationIDString: String = row["conversationID"]
        let role: String = row["role"]
        let text: String = row["text"]
        let tokensPerSecond: Double? = row["tokensPerSecond"]
        let createdAt: Double = row["createdAt"]
        guard let id = UUID(uuidString: idString),
              let conversationID = UUID(uuidString: conversationIDString) else { return nil }
        return PersistedConversationMessage(
            id: id,
            conversationID: conversationID,
            role: role,
            text: text,
            tokensPerSecond: tokensPerSecond,
            createdAt: Date(timeIntervalSince1970: createdAt))
    }

    private static func prompt(_ row: Row) -> PromptHistoryEntry? {
        let idString: String = row["id"]
        let prompt: String = row["prompt"]
        let workspacePath: String? = row["workspacePath"]
        let modeString: String = row["mode"]
        let createdAt: Double = row["createdAt"]
        guard let id = UUID(uuidString: idString),
              let mode = ConversationMode(rawValue: modeString) else { return nil }
        return PromptHistoryEntry(
            id: id,
            prompt: prompt,
            workspacePath: workspacePath,
            mode: mode,
            createdAt: Date(timeIntervalSince1970: createdAt))
    }
}

enum AppSchema {
    static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_app_state") { db in
            try db.execute(sql: """
                CREATE TABLE conversation (
                    id TEXT PRIMARY KEY NOT NULL,
                    title TEXT NOT NULL,
                    workspacePath TEXT,
                    mode TEXT NOT NULL DEFAULT 'code',
                    createdAt REAL NOT NULL,
                    updatedAt REAL NOT NULL
                )
                """)
            try db.execute(sql: "CREATE INDEX idx_conversation_updatedAt ON conversation(updatedAt)")
            try db.execute(sql: """
                CREATE TABLE conversation_message (
                    id TEXT PRIMARY KEY NOT NULL,
                    conversationID TEXT NOT NULL REFERENCES conversation(id) ON DELETE CASCADE,
                    role TEXT NOT NULL,
                    text TEXT NOT NULL,
                    tokensPerSecond REAL,
                    createdAt REAL NOT NULL
                )
                """)
            try db.execute(sql: "CREATE INDEX idx_conversation_message_conversation ON conversation_message(conversationID, createdAt)")
            try db.execute(sql: """
                CREATE TABLE prompt_history (
                    id TEXT PRIMARY KEY NOT NULL,
                    prompt TEXT NOT NULL,
                    workspacePath TEXT,
                    mode TEXT NOT NULL DEFAULT 'code',
                    createdAt REAL NOT NULL
                )
                """)
            try db.execute(sql: "CREATE INDEX idx_prompt_history_createdAt ON prompt_history(createdAt)")
            try db.execute(sql: """
                CREATE TABLE model_assignment (
                    role TEXT PRIMARY KEY NOT NULL,
                    modelID TEXT NOT NULL,
                    quantization INTEGER NOT NULL,
                    updatedAt REAL NOT NULL
                )
                """)
        }
        migrator.registerMigration("v2_conversation_mode") { db in
            let conversationColumns = try db.columns(in: "conversation").map(\.name)
            if !conversationColumns.contains("mode") {
                try db.execute(sql: "ALTER TABLE conversation ADD COLUMN mode TEXT NOT NULL DEFAULT 'code'")
            }
            try db.execute(sql: "UPDATE conversation SET mode = 'chat' WHERE workspacePath IS NULL")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_conversation_mode_updatedAt ON conversation(mode, updatedAt)")

            let promptColumns = try db.columns(in: "prompt_history").map(\.name)
            if !promptColumns.contains("mode") {
                try db.execute(sql: "ALTER TABLE prompt_history ADD COLUMN mode TEXT NOT NULL DEFAULT 'code'")
            }
            try db.execute(sql: "UPDATE prompt_history SET mode = 'chat' WHERE workspacePath IS NULL")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_prompt_history_mode_createdAt ON prompt_history(mode, createdAt)")
        }
        migrator.registerMigration("v3_message_generation_speed") { db in
            let messageColumns = try db.columns(in: "conversation_message").map(\.name)
            if !messageColumns.contains("tokensPerSecond") {
                try db.execute(sql: "ALTER TABLE conversation_message ADD COLUMN tokensPerSecond REAL")
            }
        }
        migrator.registerMigration("v4_config_snapshots") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS config_snapshot (
                    id TEXT PRIMARY KEY NOT NULL,
                    workspacePath TEXT,
                    loadedAt REAL NOT NULL,
                    sourceCount INTEGER NOT NULL,
                    diagnosticCount INTEGER NOT NULL,
                    errorCount INTEGER NOT NULL,
                    effectiveJSON TEXT NOT NULL
                )
                """)
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_config_snapshot_workspace_loadedAt ON config_snapshot(workspacePath, loadedAt)")
        }
        migrator.registerMigration("v5_native_sessions") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS native_session (
                    id TEXT PRIMARY KEY NOT NULL,
                    workspacePath TEXT,
                    title TEXT NOT NULL,
                    createdAt REAL NOT NULL,
                    updatedAt REAL NOT NULL,
                    isInterrupted INTEGER NOT NULL DEFAULT 0
                )
                """)
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_native_session_workspace_updatedAt ON native_session(workspacePath, updatedAt)")
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS session_input (
                    id TEXT PRIMARY KEY NOT NULL,
                    sessionID TEXT NOT NULL REFERENCES native_session(id) ON DELETE CASCADE,
                    prompt TEXT NOT NULL,
                    delivery TEXT NOT NULL,
                    resume INTEGER NOT NULL,
                    status TEXT NOT NULL,
                    createdAt REAL NOT NULL,
                    promotedAt REAL
                )
                """)
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_session_input_pending ON session_input(sessionID, status, createdAt)")
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS session_message_part (
                    id TEXT PRIMARY KEY NOT NULL,
                    sessionID TEXT NOT NULL REFERENCES native_session(id) ON DELETE CASCADE,
                    messageID TEXT NOT NULL,
                    role TEXT NOT NULL,
                    kind TEXT NOT NULL,
                    text TEXT NOT NULL,
                    createdAt REAL NOT NULL
                )
                """)
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_session_message_part_order ON session_message_part(sessionID, createdAt)")
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS session_todo (
                    id TEXT PRIMARY KEY NOT NULL,
                    sessionID TEXT NOT NULL REFERENCES native_session(id) ON DELETE CASCADE,
                    title TEXT NOT NULL,
                    status TEXT NOT NULL,
                    updatedAt REAL NOT NULL
                )
                """)
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_session_todo_session ON session_todo(sessionID, updatedAt)")
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS session_compaction (
                    id TEXT PRIMARY KEY NOT NULL,
                    sessionID TEXT NOT NULL REFERENCES native_session(id) ON DELETE CASCADE,
                    summary TEXT NOT NULL,
                    recentContext TEXT NOT NULL,
                    createdAt REAL NOT NULL
                )
                """)
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_session_compaction_latest ON session_compaction(sessionID, createdAt)")
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS session_event (
                    id TEXT PRIMARY KEY NOT NULL,
                    sessionID TEXT NOT NULL REFERENCES native_session(id) ON DELETE CASCADE,
                    sequence INTEGER NOT NULL,
                    kind TEXT NOT NULL,
                    messageID TEXT,
                    payloadJSON TEXT NOT NULL,
                    createdAt REAL NOT NULL,
                    UNIQUE(sessionID, sequence)
                )
                """)
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_session_event_replay ON session_event(sessionID, sequence)")
        }
        migrator.registerMigration("v6_session_message_metadata") { db in
            let columns = try db.columns(in: "session_message_part").map(\.name)
            if !columns.contains("modelID") {
                try db.execute(sql: "ALTER TABLE session_message_part ADD COLUMN modelID TEXT")
            }
            if !columns.contains("reasoningEffort") {
                try db.execute(sql: "ALTER TABLE session_message_part ADD COLUMN reasoningEffort TEXT")
            }
        }
        migrator.registerMigration("v7_session_context_memory") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS session_message_embedding (
                    partID TEXT PRIMARY KEY NOT NULL REFERENCES session_message_part(id) ON DELETE CASCADE,
                    sessionID TEXT NOT NULL REFERENCES native_session(id) ON DELETE CASCADE,
                    dimensions INTEGER NOT NULL,
                    vector BLOB NOT NULL,
                    updatedAt REAL NOT NULL
                )
                """)
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_session_message_embedding_session ON session_message_embedding(sessionID, updatedAt)")
            let compactionColumns = try db.columns(in: "session_compaction").map(\.name)
            if !compactionColumns.contains("coveredMessagePartIDsJSON") {
                try db.execute(sql: "ALTER TABLE session_compaction ADD COLUMN coveredMessagePartIDsJSON TEXT")
            }
            if !compactionColumns.contains("coveredThrough") {
                try db.execute(sql: "ALTER TABLE session_compaction ADD COLUMN coveredThrough REAL")
            }
            if !compactionColumns.contains("sourceMode") {
                try db.execute(sql: "ALTER TABLE session_compaction ADD COLUMN sourceMode TEXT")
            }
            if !compactionColumns.contains("estimatedTokens") {
                try db.execute(sql: "ALTER TABLE session_compaction ADD COLUMN estimatedTokens INTEGER NOT NULL DEFAULT 0")
            }
        }
        return migrator
    }
}
