# ADR 0002: Contentless FTS5 for the workspace search index

**Status:** Accepted (Phase 2)

## Context
ARCHITECTURE.md §9 requires a SQLite **FTS5** search index; §12 says "do NOT
duplicate repository contents unnecessarily." A plain (or external-content) FTS5
table keeps a derived copy of every file's text, which strains §12.

## Decision
Use a **contentless** FTS5 table (`content=''`, `contentless_delete=1`) in
`Persistence/WorkspaceSchema.swift`. It stores only the inverted index (derived
terms) derived from filename, body, symbols, comments, and references. The
database must not store reconstructable full source/body text. Snippets (which
contentless FTS5 cannot produce) are generated on demand from disk for the
bounded result set by `Workspace/SnippetExtractor.swift`. `contentless_delete=1`
requires SQLite ≥ 3.43 (shipped on macOS 15: 3.43.2).

## Consequences
- Maximal §12 compliance: the database stores derived FTS terms and lightweight
  symbol/reference names and locations, but no reconstructable full source/body
  text. Verified by `PersistenceTests.contentlessIndexStoresNoRecoverableStructuredOrBodyText`.
- Snippets cost one small disk read per returned hit (bounded by the search limit).
- Swappable behind `Core/WorkspaceIndexStore`: if snippet latency ever matters, an
  external-content table (one derived copy) can replace it without changing callers.
