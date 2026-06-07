# Phase 3 — Agent Runtime

Phase 3 delivers the library-level agent runtime without SwiftUI.

## 3a — delivered
- [x] `Tooling` target with restricted, workspace-scoped tool execution.
- [x] `Agents` target with `Agent`, orchestrator/utility agents, deterministic routing, context building, and retry policy.
- [x] Library/test harness surface; no executable target yet.
- [x] Fake-driven tests for routing, context budgeting, retry, dry-run writes, command allowlists, timeout, cancellation, and end-to-end agent flow.

## 3b — delivered
- [x] Native model-decided iterative tool loop using `MLXLMCommon.Generation.toolCall` events.
- [x] MLX-free shared tool-call values: `JSONValue`, `ToolDefinition`, `ModelToolCall`, and `ModelToolCallFormat`.
- [x] Tool schemas flow through `GenerationRequest.tools`; native tool calls flow through `TokenChunk.toolCall`.
- [x] Workspace tool registry advertises read/git tools by default, advertises test/shell tools only for explicitly trusted network-enabled policies, and only advertises write tools when writes are explicitly enabled.
- [x] Agent loop executes native tool calls, appends tool observations to chat history, and regenerates until the model stops requesting tools.
- [x] Minimal `interless-agent` CLI, fake by default and real-MLX capable with explicit model flags.
- [x] Fast fake-driven tests for shared values, backend tool-call bridging, registry validation, iterative tools, cancellation, and CLI behavior.

## 3c / later
- [ ] Richer task decomposition and multi-agent repair planning.
- [ ] Model-specific prompt tuning for tool-use reliability.
- [ ] Human review/apply workflow for code patches.
- [ ] Production composition in `App/` and SwiftUI surfaces.

## Out of scope
- SwiftUI chat/workspace shell.
- App production composition.
- Remote inference or network-enabled tools.
