# Phase 4 — Native SwiftUI Shell

Phase 4a delivered the first runnable native macOS shell as a SwiftPM executable.
Phase 4b hardens that shell for daily workspace use while keeping packaging,
patch apply, and model onboarding polish out of scope.

## 4a — delivered
- [x] `Interless` SwiftUI executable.
- [x] `UI` target with presentation-only `WorkspaceView`, `ChatPaneView`, `FileTreeView`, `DiffViewer`, `CommandPalette`, and `ModelSettingsView`.
- [x] `AppCore` target with `AppPreferences`, live dependency composition, and `WorkspaceSessionModel`.
- [x] Settings-first model loading; no automatic downloads or model loads on launch.
- [x] Live workspace composition for persistence, scanner/indexer, FSEvents watcher, restricted tooling, inference controller, and agent orchestrator.
- [x] Streaming chat state, tool event display, workspace search, file preview, git status, and diff rendering.
- [x] Fast tests for preferences, session behavior, fake dependency wiring, UI formatters, command filtering, and settings validation.

## 4b — delivered
- [x] Automatic last-workspace restoration with a dismissible notice when the saved path is unavailable.
- [x] Persisted recent workspaces, selected file, search query, command recents, and lightweight layout preferences.
- [x] App-level notice and activity state for indexing, search, git refresh, model loading, and chat.
- [x] Manual-only model loading with explicit cancellation and clearer status/errors.
- [x] Safe file preview path: workspace containment, symlink escape rejection, size cap, binary detection, and truncation markers.
- [x] File-tree filtering, selectable search hits, selected-file restoration, and safer empty/error states.
- [x] Grouped diff presentation with file/hunk sections and addition/deletion counts.
- [x] Command palette fuzzy ranking, recents, disabled reasons, keyboard selection, and additional shell commands.
- [x] Collapsed/de-emphasized chat tool events while preserving event order.
- [x] Fast tests for restoration, safe previews, notices, cancellation, UI filtering/ranking/grouping, and the `UI` import boundary.

## 4c — delivered
- [x] SwiftPM app bundle packaging through `scripts/package-app.sh`; no Xcode project required.
- [x] Bundle metadata in `Resources/AppBundle/Info.plist`, app entitlements, and source icon resource.
- [x] Release build, `.app` assembly, bundle validation, and optional local ad-hoc signing.
- [x] `swift run Interless` remains supported; packaging is additive.

Package locally:

```sh
SKIP_SIGN=1 ./scripts/package-app.sh
open .build/app/Interless.app
```

## 4d — delivered
- [x] Human patch review value types for proposals, files, hunks, lines, diagnostics, and summary counts.
- [x] `AppCore` patch coordinator for unified diff parsing, accepted-hunk state, workspace-contained apply, stale-context rejection, and symlink escape protection.
- [x] Patch review UI with file/hunk review, accept/reject controls, disabled apply reasons, and explicit apply/discard actions.
- [x] Patch apply requires `allowWrites = true`; no auto-apply behavior was added.

## 4e — delivered
- [x] Flattened visible-row file tree with persisted disclosure state, bounded rendering, filtering, and selection restoration.
- [x] Accessibility helper copy and labels for command palette, file tree, patch review, model settings, and status state.
- [x] Keyboard-accessible patch/model/workspace commands remain routed through app/session actions.
- [x] Model onboarding guidance using `ARCHITECTURE.md` recommended model roles, quantization, memory notes, and manual-load behavior.

## Later Phase 4
- [ ] Distribution signing/notarization and installer/DMG workflow.
- [ ] Advanced editor features beyond patch review, such as inline editing and richer merge conflict handling.
- [ ] Deeper visual polish and full performance profiling on very large repositories.
- [ ] Real MLX download-progress plumbing if the upstream seam exposes reliable progress events.

## Boundaries
- `App/` owns lifecycle and dependency injection only.
- `UI/` remains presentation-only and imports no runtime modules.
- Runtime algorithms stay in `MLXEngine`, `Workspace`, `Persistence`, `Agents`, and `Tooling`.
