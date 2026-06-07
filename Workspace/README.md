# Workspace/

Workspace scanning and indexing (ARCHITECTURE.md §9): recursive low-memory
traversal, nested `.gitignore`/`.opencodeignore`, size/binary filtering,
Swift-first structured extraction, path-scoped incremental indexing, and
FSEvents-driven live updates through `WorkspaceWatcher`.

The persistence boundary remains `Core/WorkspaceIndexStore`; this target owns
filesystem/git parsing and never imports GRDB.
