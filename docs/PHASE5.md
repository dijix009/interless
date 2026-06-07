# Phase 5 — Reliability Foundation

Phase 5 adds local reliability infrastructure and adaptive low-memory behavior.
It starts with observability, then adds journal-based crash/failure recovery,
memory-policy enforcement, and optimization driven by local metrics. It does not
add telemetry, low-level crash hooks, or automatic model loading.

## 5a — delivered
- [x] `Core.EventBus` typed async event bus with bounded in-memory retention,
  multi-subscriber streams, and no global singleton.
- [x] `Core.TaskScheduler` lightweight tracked-task actor with priorities,
  active/recent snapshots, manual lifecycle tracking, and cancellation support
  for structured-concurrency tasks.
- [x] `Core.MetricsRecorder` fixed-size in-memory metrics recorder for counts,
  durations, gauges, measured operations, and aggregate summaries.
- [x] `AppCore.WorkspaceSessionModel` publishes events, records metrics, and
  tracks app operations for workspace open, indexing, search, file preview, git,
  chat, model load/unload, tool events, patch apply, failures, and cancellations.
- [x] `UI.HealthStatusView` presents active tasks, recent failures, event
  timeline, metric summaries, and memory summary state without importing runtime
  modules.
- [x] `WorkspaceCommand.openHealth`, toolbar/menu/command-palette access, and
  app health sheet wiring.
- [x] Fast tests for Core observability actors, AppCore health emissions, UI
  formatting, command palette health access, and import-boundary regressions.

## Later Phase 5
- [x] 5b: crash/failure journal and local recovery surfaces.
- [x] 5c: memory-policy enforcement using observed memory state.
- [x] 5d: indexing/tool/inference reliability tuning driven by metrics.
- [x] 5e: long-run soak tests and user-facing diagnostics export.

## 5b — delivered
- [x] `Core.RecoveryJournal` persists bounded, atomically-written JSON operation
  and failure records under a caller-provided path.
- [x] Live app journal path is
  `~/Library/Application Support/Interless/recovery-journal.json`.
- [x] Startup recovery detects active records from previous app runs and exposes
  them as explicit recovery items; nothing is retried automatically.
- [x] Journal metadata is sanitized: no prompts, source bodies, tool output,
  secrets, tokens, or credentials are persisted.
- [x] Corrupt journal files are renamed aside and replaced with a clean journal,
  with an app notice and health warning.
- [x] `WorkspaceSessionModel` records workspace open, indexing, search, file
  preview, git refresh, chat, model load/unload, tool execution, and patch apply
  outcomes.
- [x] `HealthStatusView` shows recovery items, warnings, and explicit
  retry/dismiss/clear actions while keeping `UI` presentation-only.

## 5c — delivered
- [x] `Shared.ResourceProfile`, `ResourceBudget`, and `MemoryPolicyState`
  provide UI-safe adaptive resource profiles.
- [x] Automatic profile resolution is 8GB-first: small-RAM on `<= 12GB`,
  balanced on `> 12GB && <= 32GB`, and large-RAM above `32GB`.
- [x] `Core.MemoryBudgetCoordinator` evaluates memory snapshots, records memory
  metrics/events, and cooldown-protects memory actions.
- [x] `InferenceController` enforces memory policy before backend work:
  request context/max-token caps, utility/embedding eviction actions, and
  reject-at-95% behavior.
- [x] Settings expose `Automatic`, `Small RAM`, `Balanced`, and `Large RAM`
  profiles; automatic remains the default.
- [x] Health surfaces show resolved profile, process/system memory, GPU/cache
  counters where available, and active pressure actions.

## 5d — delivered
- [x] Incremental indexing uses path-scoped file-state lookup and the real
  filesystem scanner can resolve a single changed path without walking the
  whole workspace.
- [x] Indexing applies profile-based file-size caps and records bytes/skipped
  metrics.
- [x] Search snippets use bounded prefix reads instead of loading whole files for
  excerpts.
- [x] Agent context and native tool feedback are profile-aware, with compact
  tool-result messages and context-character metrics.
- [x] Tool execution policy derives output caps from the active resource budget.
- [x] Chat transcript/tool-event presentation is bounded by the active profile to
  prevent unbounded UI/session growth.

## 5e — delivered
- [x] `Core.DiagnosticsExporter` builds schema-versioned, deterministic,
  redacted JSON bundles from app/build metadata, system info, workspace summary,
  events, task snapshots, metrics, memory policy state, recovery snapshots, and
  sanitized settings.
- [x] Default diagnostics exclude prompts, source bodies, file preview text, tool
  stdout/stderr, secrets/tokens, and full absolute paths. Workspace paths export
  as basename plus stable hash unless full paths are explicitly requested.
- [x] `WorkspaceSessionModel.exportDiagnostics(to:includeFullPaths:)` writes
  user-triggered local exports and surfaces success/failure notices.
- [x] `WorkspaceCommand.exportDiagnostics`, Health UI actions, command-palette
  access, and native save-panel menu wiring are implemented.
- [x] `scripts/soak-fast.sh` runs deterministic fake/local soak verification
  without network, GPU, or real model downloads.
- [x] `scripts/soak-mlx.sh` provides an explicit manual real-MLX soak harness
  gated by environment model IDs and Metal toolchain availability.

## Post-5e architecture compliance hardening — delivered
- [x] `Persistence.AppStore` stores conversations, conversation messages,
  prompt history, and model assignments at
  `~/Library/Application Support/Interless/app.sqlite`; prompt/chat history is
  enabled by default and can be disabled in settings.
- [x] `Security/` now contains a real Keychain-backed secret store exposed as
  the `InterlessSecurity` module, avoiding a module-name collision with
  Apple `Security.framework`.
- [x] Trusted process/network-capable tools are explicit: app settings and
  `interless-agent --allow-network-tools` opt into commands that may execute
  workspace code. Writes remain independently gated by `allowWrites`.
- [x] `MLXEngine` supports optional embedding model loading for
  `ModelRole.embeddings`; `Persistence` stores normalized vectors and AppCore
  uses hybrid lexical/semantic search when embeddings are loaded.
- [x] `Core.MetricKitBridge` forwards MetricKit metric/diagnostic payload counts
  into the local `MetricsRecorder`.
- [x] File preview uses a TextKit 2 AppKit bridge in `UI`, with syntax token
  generation performed outside the presentation layer.
- [x] Tool file reads and writes are bounded by policy/resource budgets.

## Boundaries
- Observability remains local-only: no telemetry or network reporting.
- Phase 5b persists only the recovery journal; metrics/events and memory policy
  state remain in-memory.
- Recovery is explicit and user-confirmed: no model auto-load, no chat replay,
  and no patch auto-apply.
- Memory policy may unload models or reject new inference under pressure, but it
  never downloads or loads models automatically.
- Diagnostics export is local-only and user-triggered; no telemetry, upload, or
  background reporting is added.
- Real-MLX soak remains opt-in/manual and separate from the fast suite.
- The task tracker uses Swift structured concurrency; it is not a custom thread
  pool.
- UI consumes presentation structs only. Runtime algorithms remain outside
  SwiftUI.
- The resolved MLX embedder registry currently exposes Nomic Embed Text v1/v1.5
  configs; users can provide another compatible embedding model ID manually.
