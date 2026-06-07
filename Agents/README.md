# Agents/

Agent orchestration runtime (ARCHITECTURE.md §6, Phase 3).

Implemented:
- `Agent` / `StreamingAgent` protocols.
- `OrchestratorAgent` and `UtilityAgent` backed by an injected `AgentModelClient`.
- `AgentOrchestrator` for deterministic routing, context building, explicit pre-tool execution, retry, and streaming events.
- `ContextBuilder` for deterministic workspace-search context budgeting.
- Native model-decided tool loops using `TokenChunk.toolCall`.
- `AgentLoopPolicy` for tool iteration and per-iteration call limits.

Tool loop behavior:
- Explicit `AgentTask.toolRequests` still run before generation.
- Model-requested tools are executed through `Tooling.ToolExecutionLoop`.
- Tool results are appended to the chat as `.tool` messages, then the model regenerates.
- Writes stay denied unless the caller provides a write-enabled `ToolExecutionPolicy`.

This target must not import SwiftUI, Persistence, GRDB, or any MLX package directly.
