import Foundation
import GRDB

/// Composition root for the workspace index store (ARCHITECTURE.md §12).
public enum PersistenceBootstrap {

    /// Live store for a workspace root: a WAL `DatabasePool` under Application
    /// Support, migrated to the current schema.
    public static func liveStore(forWorkspaceRoot root: URL) throws -> GRDBWorkspaceIndexStore {
        let dbURL = try WorkspaceDatabaseLocator.databaseURL(forWorkspaceRoot: root)
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        let pool = try DatabasePool(path: dbURL.path, configuration: configuration)
        try WorkspaceSchema.makeMigrator().migrate(pool)
        return GRDBWorkspaceIndexStore(dbWriter: pool)
    }

    /// In-memory store for tests/previews: a migrated `DatabaseQueue`, no files.
    public static func inMemoryStore() throws -> GRDBWorkspaceIndexStore {
        let queue = try DatabaseQueue() // named: nil ⇒ in-memory
        try WorkspaceSchema.makeMigrator().migrate(queue)
        return GRDBWorkspaceIndexStore(dbWriter: queue)
    }

    public static func liveAppStore() throws -> GRDBAppStore {
        let pool = try liveAppDatabasePool()
        return GRDBAppStore(dbWriter: pool)
    }

    public static func liveConfigStore() throws -> GRDBConfigStore {
        let pool = try liveAppDatabasePool()
        return GRDBConfigStore(dbWriter: pool)
    }

    public static func liveSessionStore() throws -> GRDBSessionStore {
        let pool = try liveAppDatabasePool()
        return GRDBSessionStore(dbWriter: pool)
    }

    private static func liveAppDatabasePool() throws -> DatabasePool {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        let directory = base.appendingPathComponent("Interless", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let dbURL = directory.appendingPathComponent("app.sqlite", isDirectory: false)
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        let pool = try DatabasePool(path: dbURL.path, configuration: configuration)
        try AppSchema.makeMigrator().migrate(pool)
        return pool
    }

    public static func inMemoryAppStore() throws -> GRDBAppStore {
        let queue = try DatabaseQueue()
        try AppSchema.makeMigrator().migrate(queue)
        return GRDBAppStore(dbWriter: queue)
    }

    public static func inMemoryConfigStore() throws -> GRDBConfigStore {
        let queue = try DatabaseQueue()
        try AppSchema.makeMigrator().migrate(queue)
        return GRDBConfigStore(dbWriter: queue)
    }

    public static func inMemorySessionStore() throws -> GRDBSessionStore {
        let queue = try DatabaseQueue()
        try AppSchema.makeMigrator().migrate(queue)
        return GRDBSessionStore(dbWriter: queue)
    }
}
