# UI/

Pure SwiftUI presentation layer (ARCHITECTURE.md §6): `WorkspaceView`,
`ChatPaneView`, `FileTreeView`, `DiffViewer`, `ModelSettingsView`.

Implemented in Phase 4a-4e:
- Three-pane native workspace shell.
- Streaming chat pane.
- Filterable flattened file tree presentation with disclosure state.
- Safe file preview states for empty, text, binary, truncated, and failed previews.
- Grouped structured git diff renderer.
- Settings-first model configuration panel with manual load/unload/cancel status.
- App notice/activity presentation models.
- Collapsible/de-emphasized tool-event chat presentation.
- Human patch review presentation with accept/reject hunk controls.
- Accessibility helper copy for key shell controls.
- Manual model onboarding guidance using architecture-recommended defaults.

This target depends only on `Shared` and SwiftUI. It must not import MLX,
Persistence, Workspace, Tooling, Agents, GRDB, or process/filesystem runtime
modules directly.
Native macOS aesthetic only; no inference logic in views (§17).
