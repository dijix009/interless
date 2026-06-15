# Interless — Performance, RAM & Coding-Quality Audit

> **Status (shipped):** the Tier-0/1/2 perf+RAM items and the coding-quality workstream
> (token-fitting, todos, abstractive compaction, repo-map retrieval, act→verify, patch
> creation) landed via PRs #6, #7, #9 and the `chore/hardening-and-validation` branch
> (semaphore/unload/restore/embedder-id/watcher hardening). Remaining future work: the full
> edit→verify→**fix** loop, patch delete/rename + fuzzy hunks, snippet region expansion,
> `SessionRunner.drain` context, per-surface host views, KV prefix-reuse. This document is
> kept as the original audit record; line numbers are from the audited revision and drift.

Goal lens: **minimal RAM while delivering powerful local coding/chat — useful on an
8 GB Mac, scaling up.** Findings below are ranked by leverage toward that goal, not by
file. Each item has a concrete location and fix.

Severity: 🔴 critical · 🟠 high · 🟡 medium · ⚪ low.

---

## Tier 0 — Architectural, highest leverage

### A1 🔴 Monolithic observable model rebuilt on every streamed token
`AppCore/WorkspaceSessionModel.swift:18` (one `ObservableObject`, 40 `@Published`),
`:149-194` (`viewState`), `App/InterlessApp.swift` (`WorkspaceShell` reads `session.viewState`).

Every `@Published` mutation — including `chatMessages[i].text += token` on **each streamed
token** — invalidates the whole shell and rebuilds the ~45-field `WorkspaceViewState`
value struct, copying `fileTree`, `fileTreeRows`, `chatMessages`, `diffFiles`, `diffLines`,
`searchHits`, `selectedFileText`, etc. The rebuild also recomputes `FileTreeNode.filtered`,
`FileTreeModel.visibleRows` (walks up to 20 k rows), and `estimatedContextWindowUsage()`
(`:1709`, joins/counts the whole transcript) **per token**. This is the dominant
perf + RAM-churn cost during chat/coding.

**Fix:** split into focused `@Observable` sub-models (chat, file tree, diff, health) so token
streaming only invalidates the chat surface. Memoize derived values (`fileTreeRows`, filtered
tree, context-usage) and recompute only when inputs change. Don't funnel the tree/transcript
through one giant copied value struct.

### A2 🔴 Token budget never enforced before send; KV cache silently drops the *front*
`Agents/ModelAgents.swift:140-156`, `MLXEngine/MLXBackend.swift:226-263`,
estimator `Agents/ConversationContextBuilder.swift:366-368`.

`contextTokenBudget` is passed only as `GenerateParameters.maxKVSize`, which makes MLX use a
**rotating** KV cache that evicts the *oldest* tokens once full — i.e. it drops the system
prompt and task framing mid-prompt instead of compacting. The full message array is tokenized
whole with no pre-send count and no truncation. All budgeting uses `chars/4`, which
under-counts code/JSON/CJK by 30-60 %, so the over-budget prompt is silently truncated at the
worst end. This is the single biggest *coding-quality* risk.

**Fix:** before streaming, count real tokens with the loaded tokenizer (`context.tokenizer`,
already reachable at `MLXBackend.swift:140`). If `input + maxTokens > window`, compact/drop
oldest **tool/history** messages while **pinning** the system prompt and latest user request;
or throw a typed `contextOverflow`. Don't rely on the rotating cache for correctness.

---

## Tier 1 — RAM scaling cliffs (break on 8 GB / large repos)

### B1 🔴 Semantic search loads the entire embedding table into RAM per query
`Persistence/GRDBWorkspaceIndexStore.swift:166-183`.

`SELECT path, dimensions, vector FROM file_embedding` with **no LIMIT**, `Row.fetchAll`,
decode every BLOB, build an `EmbeddingVector` per row (which **re-normalizes** — another full
copy + reduce + map), collect *all* hits, then sort and `prefix(limit)`. At ~50 k files × 768
dims that is ~150 MB of Float arrays materialized for one query. Scales linearly, no cap.

**Fix:** `Row.fetchCursor` (one vector at a time) + a bounded top-`limit` min-heap; dot-product
directly over the raw `Data` via `withUnsafeBytes` (vectors are already normalized on write —
skip re-normalization); consider `vDSP_dotpr`. (`Shared/EmbeddingVector.swift:4-15` should add a
raw/unnormalized init.)

### B2 🔴 Full reindex holds the whole index + several large sets in RAM
`Persistence/GRDBWorkspaceIndexStore.swift:99-110` (`knownFileStates`),
`Workspace/WorkspaceIndexer.swift:76-77,114`.

A reindex pulls **all** rows into `[FileIndexState]`, builds a full path→state `Dictionary`,
accumulates a `Set<String>` of every scanned path, then `Set(known).subtracting(seen)` — multiple
repo-sized collections alive for the whole scan, defeating the "O(1) streaming" claim.

**Fix:** keep comparison data in SQLite — per-entry `fileState(path:)` (indexed) or windowed
prefetch; compute deletions in SQL (stamp a `seenAt` epoch on upsert/skip, `DELETE WHERE seenAt <
scanStart`) instead of diffing two in-RAM sets.

### B3 🟠 Subprocess stdout/stderr read fully into memory, no cap
`Workspace/ProcessRunner.swift:64-66`.

Temp-file redirection correctly avoids the pipe deadlock, but `Data(contentsOf: outURL)` slurps
the entire output. Large `git diff`, `run_tests`, or `shell` output (tens–hundreds of MB)
materializes at once.

**Fix:** add `maxOutputBytes`; read a bounded prefix from the temp files via `FileHandle`, set a
`truncated` flag on `Result`.

### B4 🟠 Four stacked unbounded token-stream buffers
`MLXEngine/MLXBackend.swift:117`, `MLXEngine/InferenceController.swift:111`,
`Agents/ModelAgents.swift:125`, `Agents/AgentOrchestrator.swift:87` — all
`bufferingPolicy: .unbounded`.

If the main-thread UI consumer (made slow by A1) can't keep up with token production, chunks pile
up across all four buffers — an unbounded heap spike exactly when memory is tightest. The
controller also re-buffers every backend chunk into a second unbounded stream.

**Fix:** bounded `.bufferingNewest(n)` (a few hundred) on each; have `InferenceController.generate`
forward the backend stream instead of re-yielding chunk-by-chunk.

### B5 🟠 SessionEventLog grows unbounded; per-subscriber stream buffer unbounded
`Core/SessionEventLog.swift:264,269-278` (history never pruned), `:324-332` (default `.unbounded`
stream).

Unlike `EventBus`/`TaskScheduler`/`MetricsRecorder`/`RecoveryJournal` (all retention-capped),
`eventsBySession[id]` is appended forever, each `SessionEvent` carrying a `payload` dict. This is
the largest in-memory growth vector for long sessions. A stalled subscriber's stream buffer also
grows without bound.

**Fix:** add a `retentionLimit` and prune the tail after append (keep `last.sequence` for replay);
create the stream with `.bufferingNewest(N)`.

### B6 🟠 Tool outputs accumulate unbounded across loop iterations
`Agents/ModelAgents.swift:208-231`.

Each iteration appends assistant + `.tool` messages and **re-sends the entire growing array**.
Up to ~20 messages × ~32 KiB each ≈ 600 KiB re-tokenized and re-sent every turn — multiplying KV
RAM + latency and feeding the small model stale noise.

**Fix:** track a running token budget across iterations; replace older tool messages with their
`ManagedToolOutputStore` preview (240-char + retrievable ref) and let the model re-fetch on demand.

### B7 🟠 Snippet extraction decodes whole buffers + splits all lines, unbounded concurrency
`Workspace/SnippetExtractor.swift:31-39`, `Workspace/WorkspaceIndexer.swift:243-249`.

Reads up to 256–512 KB per hit, `String(decoding:)` the whole buffer, `split("\n")` all lines —
just to find the first matching line. Run concurrently for up to `limit` hits (defaults to **50**,
ignoring `maxSearchResults` of 4–12). Peak ≈ `limit × (read + String + line array)`.

**Fix:** scan chunk-by-chunk, stop at first match; bound the task group to `maxSearchResults`; pass
`limit = budget.maxSearchResults`.

---

## Tier 2 — Performance

### C1 🟠 No proactive MLX allocator cap — eviction is purely reactive
`MLXEngine/MLXBackend.swift:200-206,52`.

Only `MLX.Memory.cacheLimit` (recycle pool) is set. There is no hard allocation ceiling, so MLX
can allocate weights+KV+activations past the point the OS starts swapping; the §8 watermarks only
react afterward. `smallRAM` sets `mlxGPUCacheLimitBytes: 128 MB` but nothing caps real allocation.

**Fix:** also set `MLX.GPU.set(memoryLimit:)` derived from the resolved profile, leaving OS
headroom, so allocations throttle *before* swap.

### C2 🟠 Per-file SQLite transaction storm during indexing
`Persistence/GRDBWorkspaceIndexStore.swift:23-68` (one `dbWriter.write` per file: UPSERT +
SELECT-back for rowid + DELETE/INSERT FTS + per-symbol/per-reference INSERT in a loop).

A large repo = hundreds of thousands of fsync/WAL commits + thousands of single-row inserts. This
is the dominant indexing wall-clock cost.

**Fix:** batch 200–500 files per transaction; use `db.lastInsertedRowID` (drop the SELECT-back);
reuse prepared statements (`db.makeStatement`) across symbol/reference loops. Batch deletes too
(`:86-97`, `:114-117`).

### C3 🟠 `publish()` triggers full health-status fan-out on nearly every op
`AppCore/WorkspaceSessionModel.swift:542-562,2081-2084`.

Every `publish(_:)` awaits `refreshHealthStatus()` → `eventBus.recentEvents`, `taskScheduler.snapshot`,
`metricsRecorder.summaries`, `recoveryJournal.snapshot`, `memoryPolicy`, and
`durableEventCursorStates()` (loads sessions + up to 200 events each), rebuilds the whole
`HealthStatusViewState`, and assigns it — triggering another `viewState` rebuild — even when the
Health panel is closed.

**Fix:** only refresh when `isHealthPresented`; debounce; move health into its own observable.

### C4 🟠 Leaked subprocess timeout watchdog Tasks
`Workspace/ProcessRunner.swift:50-56`.

The watchdog `Task { sleep(timeout); … }` is never cancelled when the process finishes early. A 20 ms
`git status` with a 5 s timeout leaves a Task sleeping 5 s, retaining `ProcessControl`/`Process`.
Frequent git/worktree refreshes pile up hundreds of orphan sleeping Tasks.

**Fix:** capture the handle and `defer { watchdog.cancel() }` around the continuation, or cancel it in
`terminationHandler`.

### C5 🟠 Persistent orchestrator KV cache is dead code → full prompt reprocessed every turn
`Agents/ModelAgents.swift:156` (`reuseKVCache: false` hard-coded),
`MLXEngine/InferenceController.swift:229-231` (only forces `false` for non-orchestrator; never
re-enables).

The §8 "orchestrator persistent KV cache" optimization never runs: every turn the whole prompt is
re-prefilled from scratch — a large latency cost on local models (worst on small Macs). The
cancellation-handling bug in `MLXBackend.swift:227-252` (cache stored only on normal completion) is
therefore *latent* — it becomes live the moment reuse is enabled.

**Fix:** enable reuse with a prompt-prefix hash on the cache box, invalidating when the prefix
diverges; persist/clear the cache via `defer` so cancellation is deterministic. Or delete the unused
KV-reuse machinery to avoid confusion.

### C6 🟡 CodeStructureExtractor: per-line regex compilation + a reference per identifier
`Workspace/CodeStructureExtractor.swift:94-101,139-146,249-254,324-327`.

Lexical fallback compiles `NSRegularExpression` inside per-line loops (~9 regexes × N lines). It also
emits a `reference` for nearly every identifier token, producing thousands of `CodeReference`s per
file → dedup-set churn + FTS `references`-column bloat. (`try!` at `:326` will also crash on a bad
pattern.)

**Fix:** cache compiled regexes as `static let`; restrict references to imports/calls/type-uses; cap
per file. Make `visit` iterative or depth-bounded.

### C7 🟡 RecoveryJournal rewrites the whole file (pretty-printed) on every operation
`Core/RecoveryJournal.swift:162-165,287-293`.

`begin/finish/recordFailure` each re-encode up to 500 pretty-printed records and atomically rewrite
the file on the actor — I/O amplification + actor contention on a hot path.

**Fix:** debounce/coalesce writes; drop `.prettyPrinted`; encode/write off the critical section.

### C8 🟠 Session restore ignores the transcript budget
`AppCore/WorkspaceSessionModel.swift:2289-2290`.

`loadSession` assigns up to 500 mapped parts to `chatMessages` with no
`chatTranscriptRetainedCharacters` / `chatToolEventRetainedCount` applied (trimming only runs on
append). Restoring a long conversation blows the RAM budget until the next token append.

**Fix:** call `trimChatTranscript()` (or apply the budget) at the end of `loadSession`; derive the
load limit from the budget instead of a hardcoded 500.

### C9 🟡 ChatPaneView rebuilds a whole-transcript string each render
`UI/ChatPaneView.swift:135-138,168-169` (`scrollSignature` maps+joins every message per `body`,
i.e. per token during streaming).

**Fix:** use a cheap trigger — last message id + its `text.count`, or a token counter.

### C10 🟡 Redundant copies of the selected file and parsed diff
`AppCore/WorkspaceSessionModel.swift:713-714` (file text stored in `selectedFilePreview.text` **and**
`selectedFileText`, then copied a third time through `viewState`); `:1352-1362` + `PresentationModels`
(uncapped `diffLines`/`diffFiles`, re-derived into `inspectorDiff`/`inspectorGit` each rebuild).

**Fix:** drop `selectedFileText`; cap parsed diff size to a `ResourceBudget` line/byte budget; compute
inspector derivations lazily.

### C11 🟡 App bootstrap opens three persistence stores synchronously on the main thread
`App/InterlessApp.swift:10-15` (live app/session/config stores built in `init()` before first frame).

**Fix:** construct stores async (in `.task` or a background actor) and inject after first frame.

---

## Tier 3 — Correctness & risk

### D1 🔴 AsyncSemaphore can hand a permit to a cancelled waiter as success
`Core/AsyncSemaphore.swift:71-81`.

`signal()` resumes the FIFO head with success *without* decrementing `permits`. If it wins the lock
over a concurrent `onCancel`, a cancelled task "acquires" the permit and `wait()` returns normally
(no throw), violating the documented contract. Current callers (`InferenceController.generate`,
`WorkspaceIndexer`) are safe only because they arm `defer { signal() }` immediately; any future
caller that returns early on cancellation permanently leaks the permit → the gate deadlocks (no
further orchestrator inference / reindex ever runs).

**Fix:** on the grant path, re-check `Task.isCancelled` after resume and, if cancelled, `signal()` the
permit back and throw `CancellationError`; or have `signal()` skip cancelled waiters under the lock.

### D2 🟠 `unload` races concurrent `load`; may not free weights
`MLXEngine/InferenceController.swift:61-68,162-167`, `MLXEngine/MLXBackend.swift:166-174,216`.

`unload` clears `handles[role]` *before* awaiting `backend.unload` and is **not** serialized by
`loadGate`, so it can interleave with an in-flight `loadModel` → `handles`/backend `models`
inconsistency. `unload`'s `clearCache()` frees only the recycle pool; if an in-flight generation
`Task` still holds `loaded.container`, the multi-GB weights aren't freed when the watermark policy
expects it — defeating eviction on 8 GB.

**Fix:** serialize `unload`/`clearKVCache` through `loadGate`; cancel/await in-flight generation for the
role before releasing the container; add an eval/synchronize barrier.

### D3 🟠 Stale tool-call guard can never fire
`Agents/ModelAgents.swift:215`, `Tooling/ScopedToolRegistry.swift:63-72`.

The runner calls `request(from: call)`, which passes `self.generation` as **both** expected and actual,
so `staleToolCall` never triggers. If the registry/policy changes mid-session (write toggle, agent
switch), in-flight model tool calls against the old schema execute under the new policy.

**Fix:** thread the generation actually advertised to the model into `request(from:generation:)` and
reject on mismatch.

### D4 🟡 Quantization `advertisedBits` substring match → false-positive hard failure
`Shared/QuantizationLevel.swift:28-37`, `MLXEngine/MLXBackend.swift:68-71`.

Scanning for `q4`/`int8`/`4bit` anywhere in the repo id can false-match (e.g. an unrelated `q4` in a
name, or a `5bit` repo against any selectable level), throwing `quantizationMismatch`, which
`InferenceController:88` treats as **non-retryable** — the load fails outright.

**Fix:** anchor detection to a separator-bounded pattern; only reject when detected bits are a value the
app supports, else skip validation.

### D5 🟡 Watcher re-scan storms; full-reindex triggers not coalesced
`Workspace/WorkspaceWatcher.swift:47-62`.

Events arriving during an in-flight reindex schedule overlapping debounced tasks; any batch containing a
directory/rename forces a full repo rescan, so heavy churn (`git checkout`, build output) causes
repeated full reindexes.

**Fix:** track an in-flight flag and merge events into the next batch; coalesce create+delete of the same
path; collapse repeated full-reindex requests into one.

### D6 🟡 Embedding forward pass has no sub-batching
`MLXEngine/MLXBackend.swift:141-161`.

`embed` pads the whole `texts` batch to the longest sequence and runs one forward pass → peak activation
`batch × maxLen × hidden` with no chunking; a repo-indexing batch spikes memory to the worst-case input.

**Fix:** fixed-size sub-batches (optionally length-bucketed) with `eval()`/cache-clear between them.

### D7 ⚪ nomic embedder fast-path id never matches (dead optimization)
`MLXEngine/MLXBackend.swift:73-76` checks `id == "nomic_text_v1_5"`, but the catalog/UI use
`nomic-ai/nomic-embed-text-v1.5`, so the tuned config is never used.

### D8 ⚪ Other unbounded-but-cardinality-bounded maps
`Core/SessionEventLog` (see B5), `Workspace/LanguageServerCoordinator.swift:53` (`diagnosticsByPath`
never evicted on close/delete), `Agents/ContextEpochStore.swift:61` (append via `existing + [epoch]`,
O(n) realloc, no cap). UTF-8 boundary truncation in `ManagedToolOutputStore.swift:77-81` and
`ToolExecutionLoop.truncateOutput` can emit U+FFFD.

### D9 ⚪ Metrics/scheduler minor wrinkles
`Core/MetricsRecorder.swift:92-109` records cancelled-op latency as a normal sample (skews averages);
`Core/TaskScheduler.swift:111-114` `cancel` writes terminal state then the task's own handler double-finishes
(guarded, but loses real terminal state).

---

## Coding-quality gaps vs Claude Code / Codex (strategic, for local-model project management)

1. **Real token accounting + deterministic compaction** (A2). Today: `chars/4` + a rotating cache that
   drops the system prompt. This is the #1 quality blocker.
2. **Live plan/todo carried in-context.** `todo` tool persists `SessionTodo`
   (`WorkspaceSessionModel.swift:2477`) but it is never re-injected into later turns
   (`ModelAgents.messages(for:)`), so the agent forgets its own plan.
3. **Repo-map / structural retrieval.** Code context is a single FTS query, top-8, snippet-truncated
   (`Agents/ContextBuilder.swift:69-81`) — no symbol/def-ref graph, no neighbor/region expansion, no MMR
   dedup, no edit-recency ranking. Conversation retrieval has adjacency expansion but code does not.
4. **Abstractive rolling summarization.** "Summary" is `String.prefix(2400)` of the oldest messages
   (`ConversationContextBuilder.swift:370-374`); Simple mode ignores compaction entirely.
5. **Real sub-agent delegation.** `SubagentDispatcher`/`task` tool exist, but `task` only schedules an
   opaque background job; the catalog routes subagents and primaries both to `.utility`
   (`AgentCatalog.swift:52-58`), collapsing delegation to one role. No spawn → isolated-context →
   return-summary loop.
6. **Edit → verify → fix loop.** No automatic re-read/build/test gate after a write/patch; `run_tests`
   is gated behind network permission and isn't wired into a self-correction loop.
7. **Robust multi-file patching.** `apply_patch` is strict-context unified-diff only — no create
   (`/dev/null` rejected, `ToolExecutionLoop.swift:412-414`), no delete/rename, no fuzzy/whitespace
   hunk matching, first-occurrence string replace with no occurrence verification.
8. **Context not consistent across paths.** `PromptExpander` resolves `@file` mentions into
   `renderedContext` but `expandedPrompt == originalPrompt` and the assembly path never consumes it
   (`PromptExpander.swift:219-221`); `SessionRunner.drain` (`:55`) executes prompts context-blind.

---

## Suggested order of attack

1. **A1** (split the observable model) and **A2** (real token budgeting) — biggest wins for both "powerful"
   and "low RAM" simultaneously.
2. **B1–B7** RAM cliffs — these are what actually OOM an 8 GB Mac on a real repo.
3. **C1/C5** (MLX allocator cap + enable persistent KV reuse) — make small Macs both safe and fast.
4. **D1/D2/D3** correctness — cheap, prevent deadlocks/garbage under cancellation and policy changes.
5. Coding-quality gaps 1→3→2 — the path to Claude Code/Codex-level project management locally.
