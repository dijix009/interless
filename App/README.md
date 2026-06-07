# App/

Application lifecycle target for the native SwiftUI shell.

Implemented in Phase 4a-4e:
- `InterlessApp` SwiftPM executable entry point.
- Window lifecycle and menu commands.
- Native workspace folder picker.
- Delegation into `AppCore.WorkspaceSessionModel`.
- One-time launch restoration hook for the last workspace.
- Menu shortcuts for workspace, command palette, git refresh, chat cancellation,
  model settings, model load/unload, and model-load cancellation.
- Menu/toolbar wiring for patch review and explicit apply/discard workflows.
- SwiftPM bundle packaging remains script-driven through `scripts/package-app.sh`;
  this target does not own distribution signing policy.

This target may wire UI and app lifecycle concerns, but it must not contain
inference, indexing, persistence, or tool execution algorithms.

Application lifecycle ownership only (ARCHITECTURE.md §6): bootstrap, dependency
injection, window lifecycle, crash recovery, state restoration. This is where the
real object graph is wired (e.g. `InferenceController(backend: MLXBackend(), …)`
and the `MemoryPressureMonitor`).

Must **not** contain inference, workspace, or orchestration logic.
