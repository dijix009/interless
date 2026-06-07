import Foundation
import GRDB
import Core

public struct PersistedConfigSnapshot: Sendable, Equatable, Codable, Identifiable {
    public var id: UUID
    public var workspacePath: String?
    public var loadedAt: Date
    public var sourceCount: Int
    public var diagnosticCount: Int
    public var errorCount: Int
    public var effectiveJSON: String

    public init(
        id: UUID = UUID(),
        workspacePath: String?,
        loadedAt: Date,
        sourceCount: Int,
        diagnosticCount: Int,
        errorCount: Int,
        effectiveJSON: String
    ) {
        self.id = id
        self.workspacePath = workspacePath
        self.loadedAt = loadedAt
        self.sourceCount = sourceCount
        self.diagnosticCount = diagnosticCount
        self.errorCount = errorCount
        self.effectiveJSON = effectiveJSON
    }
}

public protocol ConfigStore: Sendable {
    func save(_ snapshot: LoadedInterlessConfig, workspacePath: String?) async throws
    func latest(workspacePath: String?) async throws -> PersistedConfigSnapshot?
}

public final class GRDBConfigStore: ConfigStore {
    private let dbWriter: any DatabaseWriter
    private let encoder = JSONEncoder()

    public init(dbWriter: any DatabaseWriter) {
        self.dbWriter = dbWriter
        encoder.outputFormatting = [.sortedKeys]
    }

    public func save(_ snapshot: LoadedInterlessConfig, workspacePath: String?) async throws {
        let effectiveJSON = String(
            decoding: try encoder.encode(snapshot.effective),
            as: UTF8.self)
        let persisted = PersistedConfigSnapshot(
            workspacePath: workspacePath,
            loadedAt: snapshot.loadedAt,
            sourceCount: snapshot.sources.filter(\.exists).count,
            diagnosticCount: snapshot.diagnostics.count,
            errorCount: snapshot.diagnostics.filter { $0.severity == .error }.count,
            effectiveJSON: effectiveJSON)
        try await dbWriter.write { db in
            try db.execute(sql: """
                INSERT INTO config_snapshot (
                    id, workspacePath, loadedAt, sourceCount, diagnosticCount, errorCount, effectiveJSON
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                """, arguments: [
                    persisted.id.uuidString,
                    persisted.workspacePath,
                    persisted.loadedAt.timeIntervalSince1970,
                    persisted.sourceCount,
                    persisted.diagnosticCount,
                    persisted.errorCount,
                    persisted.effectiveJSON,
                ])
        }
    }

    public func latest(workspacePath: String?) async throws -> PersistedConfigSnapshot? {
        try await dbWriter.read { db in
            let row: Row?
            if let workspacePath {
                row = try Row.fetchOne(db, sql: """
                    SELECT * FROM config_snapshot
                    WHERE workspacePath = ?
                    ORDER BY loadedAt DESC
                    LIMIT 1
                    """, arguments: [workspacePath])
            } else {
                row = try Row.fetchOne(db, sql: """
                    SELECT * FROM config_snapshot
                    WHERE workspacePath IS NULL
                    ORDER BY loadedAt DESC
                    LIMIT 1
                    """)
            }
            guard let row else { return nil }
            return Self.snapshot(row)
        }
    }

    private static func snapshot(_ row: Row) -> PersistedConfigSnapshot? {
        let idString: String = row["id"]
        let workspacePath: String? = row["workspacePath"]
        let loadedAt: Double = row["loadedAt"]
        let sourceCount: Int = row["sourceCount"]
        let diagnosticCount: Int = row["diagnosticCount"]
        let errorCount: Int = row["errorCount"]
        let effectiveJSON: String = row["effectiveJSON"]
        guard let id = UUID(uuidString: idString) else { return nil }
        return PersistedConfigSnapshot(
            id: id,
            workspacePath: workspacePath,
            loadedAt: Date(timeIntervalSince1970: loadedAt),
            sourceCount: sourceCount,
            diagnosticCount: diagnosticCount,
            errorCount: errorCount,
            effectiveJSON: effectiveJSON)
    }
}
