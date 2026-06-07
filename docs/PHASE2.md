# Phase 2 — Workspace Engine: status & remaining work

Phase 2 ships in sub-phases. **2a** was the core engine; **2b** completes the
remaining §9 workspace-indexing requirements. `App/` production composition is
tracked as Phase 4, not a Phase 2 blocker.

## 2a — delivered
- [x] Recursive, low-memory scanner (`FileSystemScanner`; pull-based `AsyncStream`).
- [x] Nested per-directory `.gitignore`/`.opencodeignore` + binary/size exclusion.
- [x] Async file loading (size-bounded, NUL-byte binary sniff, UTF-8 lossy, SHA-256).
- [x] SQLite **FTS5** search over filenames + full content (contentless — see ADR 0002).
- [x] Incremental indexing (size/mtime fast-path + content-hash dedup) + deletion pruning.
- [x] Git metadata via the `git` CLI (see ADR 0001).
- [x] Fast unit + end-to-end tests (`./scripts/test.sh`).

## 2b — delivered
- [x] Swift-first structured extraction for symbols, comments, imports, calls,
      type references, and identifiers.
- [x] Contentless structured FTS5 columns (`filename`, `body`, `symbols`,
      `comments`, `references`) plus lightweight symbol/reference location tables.
- [x] `v2_structured_index` migration that forces full reindexing because old
      contentless FTS rows cannot reconstruct body text.
- [x] FSEvents-backed live event stream and debounced `WorkspaceWatcher`.
- [x] Path-scoped create/modify/delete indexing, with full-reindex fallback for
      directory, rename, root, unknown, and ignore-file events.
- [x] Bounded ignore-scope traversal: inactive sibling ignore scopes are pruned as
      the scanner advances.
- [x] Fast tests for extraction, structured persistence/search, incremental
      indexing, watcher debounce/fallback, and scanner hardening.

## Phase 4 composition
- [ ] Production composition (`liveIndexer`) in `App/`, replacing the test-only
      end-to-end wiring.

## Later (§12 persistence, beyond Phase 2)
- [ ] `conversations`, `model assignments`, `prompt history` tables (migrator slots reserved).

## Supported `.gitignore` subset (2a)
**In:** comments/blanks (+ `\#` escape), `*`/`?` (do not cross `/`), `**`,
leading-`/` anchoring, basename-vs-anchored rule, trailing-`/` dir-only, `!`
negation (last-match-wins), `.opencodeignore` layering, nested per-directory ignore
files, built-in `.git/`.
**Out:** char-classes `[a-z]`, `core.ignorecase`, `.git/info/exclude` + global
`core.excludesFile`, full `git check-ignore` parity.
