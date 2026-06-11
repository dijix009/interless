import GRDB

/// SQLite schema + migrations for the workspace index (ARCHITECTURE.md §9, §12).
///
/// The FTS5 table is **contentless** (`content=''`): it stores only the inverted
/// index, never a reconstructable copy of source text. `contentless_delete=1`
/// (SQLite ≥ 3.43, shipped on macOS 15) enables DELETE/UPDATE by rowid. Snippets
/// are generated from disk by the `Workspace` layer, since contentless FTS5
/// cannot produce them.
enum WorkspaceSchema {

    static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_workspace_index") { db in
            // Generic key/value workspace metadata (last scan, branch, HEAD, …).
            try db.execute(sql: """
                CREATE TABLE metadata (
                    key   TEXT PRIMARY KEY NOT NULL,
                    value TEXT
                )
                """)

            // Per-file incremental state. `id` doubles as the FTS5 rowid.
            try db.execute(sql: """
                CREATE TABLE indexed_file (
                    id          INTEGER PRIMARY KEY AUTOINCREMENT,
                    path        TEXT NOT NULL UNIQUE,
                    size        INTEGER NOT NULL,
                    mtime       INTEGER NOT NULL,
                    contentHash TEXT NOT NULL,
                    indexedAt   INTEGER NOT NULL
                )
                """)

            // Contentless FTS5 over filename + body. This is replaced by the v2
            // structured index below for fresh databases; keeping v1 preserves a
            // valid migration path for existing Phase 2a DBs.
            try db.execute(sql: """
                CREATE VIRTUAL TABLE file_fts USING fts5(
                    filename,
                    body,
                    content='',
                    contentless_delete=1,
                    tokenize='unicode61 separators ''_-./'''
                )
                """)
        }

        migrator.registerMigration("v2_structured_index") { db in
            // Contentless FTS cannot reconstruct old body text, so v2 forces a
            // full reindex by clearing file state and recreating FTS with the
            // structured columns required by ARCHITECTURE.md §9.
            try db.execute(sql: "DROP TABLE IF EXISTS file_fts")
            try db.execute(sql: "DELETE FROM indexed_file")
            try db.execute(sql: """
                CREATE VIRTUAL TABLE file_fts USING fts5(
                    filename,
                    body,
                    symbols,
                    comments,
                    "references",
                    content='',
                    contentless_delete=1,
                    tokenize='unicode61 separators ''_-./'''
                )
                """)
            try db.execute(sql: """
                CREATE TABLE file_symbol (
                    id     INTEGER PRIMARY KEY AUTOINCREMENT,
                    fileID INTEGER NOT NULL REFERENCES indexed_file(id) ON DELETE CASCADE,
                    path   TEXT NOT NULL,
                    name   TEXT NOT NULL,
                    kind   TEXT NOT NULL,
                    line   INTEGER NOT NULL,
                    column INTEGER NOT NULL
                )
                """)
            try db.execute(sql: "CREATE INDEX idx_file_symbol_path ON file_symbol(path)")
            try db.execute(sql: "CREATE INDEX idx_file_symbol_name ON file_symbol(name)")
            try db.execute(sql: """
                CREATE TABLE file_reference (
                    id     INTEGER PRIMARY KEY AUTOINCREMENT,
                    fileID INTEGER NOT NULL REFERENCES indexed_file(id) ON DELETE CASCADE,
                    path   TEXT NOT NULL,
                    name   TEXT NOT NULL,
                    kind   TEXT NOT NULL,
                    line   INTEGER NOT NULL,
                    column INTEGER NOT NULL
                )
                """)
            try db.execute(sql: "CREATE INDEX idx_file_reference_path ON file_reference(path)")
            try db.execute(sql: "CREATE INDEX idx_file_reference_name ON file_reference(name)")
        }

        migrator.registerMigration("v3_semantic_embeddings") { db in
            try db.execute(sql: """
                CREATE TABLE file_embedding (
                    path TEXT PRIMARY KEY NOT NULL,
                    dimensions INTEGER NOT NULL,
                    vector BLOB NOT NULL,
                    updatedAt INTEGER NOT NULL
                )
                """)
        }

        migrator.registerMigration("v4_seen_epoch") { db in
            // Scan-epoch stamp for SQL-side deletion pruning: a full scan stamps
            // every visited row, then deletes `WHERE seenAt < scanStart` — replacing
            // the previous in-RAM all-paths set diff (O(repo) memory). Additive:
            // legacy rows default to 0 and are stamped on the next full scan.
            try db.execute(sql: "ALTER TABLE indexed_file ADD COLUMN seenAt INTEGER NOT NULL DEFAULT 0")
            try db.execute(sql: "CREATE INDEX idx_indexed_file_seenAt ON indexed_file(seenAt)")
        }

        // Reserved for §12's later tables (conversations, model assignments,
        // prompt history) — additive migrations after the workspace index.

        return migrator
    }
}
