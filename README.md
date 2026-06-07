# Interless

Interless is a native macOS agent workspace for Apple Silicon. It is built with
Swift 6, SwiftUI, actors, AsyncSequence, SQLite/FTS5, FSEvents, libgit2-style git
providers, TextKit-oriented previews, and in-process MLX inference.

There is no Electron shell, no browser UI, no React/CSS/HTML app surface, no
JavaScript plugin runtime, and no local HTTP module transport.

## Current Status

Interless is usable as a local native app and as a small CLI harness. The current
app supports local chat, workspace-aware code chat, durable native sessions,
manual MLX model loading/downloading, workspace indexing, bounded tools, patch
review, and local diagnostics.

The implementation is still in active migration. Some configured surfaces exist
as native foundations but are not yet full end-to-end product features.

## Quick Start

For a first local test on Apple Silicon:

```sh
git clone https://github.com/JeromeDassy/interless.git interless
cd interless
swift build
./scripts/test.sh
SKIP_SIGN=1 ./scripts/package-app.sh
open .build/app/Interless.app
```

In the app:

1. Open Settings -> Model & Context.
2. Paste `mlx-community/gemma-2-2b-it-4bit` or
   `mlx-community/Llama-3.2-1B-Instruct-4bit` as the chat model ID.
3. Choose `q4` quantization.
4. Press Load. If the model is not already cached, Interless downloads it first.
5. Use Chat mode for plain local chat.
6. Open a folder and switch to Code mode for workspace-aware chat and tools.

The packaged app path is:

```text
.build/app/Interless.app
```

## Requirements

- macOS 15 or newer.
- Apple Silicon Mac.
- Swift 6 toolchain.
- Full Xcode, not only Command Line Tools, for MLX GPU inference and release app
  packaging through `xcodebuild`.
- Network access for first-time SwiftPM dependency resolution and Hugging Face
  model downloads.
- Enough unified memory for the model you choose. Small q4 models can run on
  low-memory Macs; large planning models can require 64 GB or more.

## First-Time Xcode Setup

After installing Xcode, run:

```sh
sudo xcode-select -s /Applications/Xcode.app
sudo xcodebuild -license accept
sudo xcodebuild -runFirstLaunch
xcodebuild -downloadComponent MetalToolchain
xcrun metal --version
```

If `xcrun metal --version` fails with a missing Metal toolchain error, rerun the
Metal component download after Xcode first launch completes.

## Install And Run

Clone the repo and build the app:

```sh
git clone https://github.com/JeromeDassy/interless.git interless
cd interless
swift build
```

Run from SwiftPM:

```sh
swift run Interless
```

Build a local `.app` bundle:

```sh
SKIP_SIGN=1 ./scripts/package-app.sh
open .build/app/Interless.app
```

The packaged app is written to:

```text
.build/app/Interless.app
```

By default the packaging script uses `xcodebuild`, which is the right path for
MLX. For a SwiftPM-only package build you can use:

```sh
BUILD_SYSTEM=swiftpm SKIP_SIGN=1 ./scripts/package-app.sh
```

## First App Setup

1. Open Interless.
2. Open Settings.
3. Go to Model & Context.
4. Paste a Hugging Face MLX model ID into the model field.
5. Optionally save a Hugging Face token in the Keychain if the model requires
   authentication.
6. Press Load. Models are not downloaded or loaded automatically.
7. Use Chat mode for plain local chat, or Code mode after opening a workspace.
8. Use the Chat/Code selector in Model & Context to set separate answer-token
   and context-window limits.
9. Keep write/process permissions disabled until you intentionally need tools
   that can mutate files or run workspace commands.

Recommended first model IDs:

| Model ID | Why use it first |
|---|---|
| `mlx-community/Llama-3.2-1B-Instruct-4bit` | Small, fast, simple chat smoke test. |
| `mlx-community/Qwen2.5-0.5B-Instruct-4bit` | Very small utility-model smoke test. |
| `mlx-community/gemma-2-2b-it-4bit` | Good download-flow test for a small instruction model. |
| `Qwen/Qwen3-4B-MLX-4bit` | Reasoning control test with None/Low/Medium/High options. |

Interless stores local app data under Application Support:

```text
~/Library/Application Support/Interless/
```

Workspace indexes are stored per workspace digest under:

```text
~/Library/Application Support/Interless/workspaces/
```

Hugging Face models are discovered from the standard cache locations:

```text
$HF_HUB_CACHE
$HF_HOME/hub
~/.cache/huggingface/hub
~/Library/Caches/huggingface/hub
```

## Settings Guide

The current settings surface intentionally shows only sections that have native
settings behind them:

| Section | What it controls today |
|---|---|
| Appearance | Native UI density and visual preferences that are implemented. |
| Chat | Chat rendering, stream display, diff presentation, and tool-card defaults. |
| Model & Context | Local MLX model IDs, quantization, Hugging Face token, load/unload/download, Chat/Code max answer tokens, Chat/Code context windows, and resource profile. |
| Sessions | Local durable session persistence and session counts. |
| Behavior | Write/process permissions, policy count, and max tool iterations. |
| MCP | Configured MCP metadata/status. Live MCP tools are not enabled yet. |
| Usage | Health, diagnostics, metrics, recovery, and local status. |

Token and context settings use `Automatic` when set to `0`.

| Setting | Range | Notes |
|---|---:|---|
| Chat max answer | 128-32,768 tokens | Used for plain Chat mode. |
| Code max answer | 128-32,768 tokens | Used for workspace Code mode. |
| Chat max context window | 1,024-131,072 tokens | Used for plain Chat mode; the resource profile still applies as a safety cap. |
| Code max context window | 1,024-131,072 tokens | Used for workspace Code mode; the resource profile still applies as a safety cap. |

Reasoning-capable models can consume much of the answer budget inside a thinking
trace. If a response ends before the final answer, either increase the max
answer-token setting or choose Reasoning: None.

## Features That Work

### Native App

- Native SwiftUI macOS shell.
- Chat and Code modes.
- Plain chat sessions separated from workspace/code sessions.
- Durable native sessions with persisted message parts and event records.
- Session list with selection, rename, delete, and mode separation.
- Compact OpenChamber-inspired workspace layout.
- Settings modal with Appearance, Chat, Model & Context, Sessions, Behavior,
  MCP status, and Usage.
- Right inspector is a Code-mode surface and stays closed by default.
- Local health, recovery, metrics, event replay, and redacted diagnostics export.

### Model Runtime

- In-process MLX model loading through the Swift MLX stack.
- Manual model load, unload, and cancellation.
- Hugging Face download progress shown as `Downloading model - xx%`.
- Keychain-backed Hugging Face token storage.
- Single-agent mode for small-memory systems.
- Separate model fields for orchestrator, utility, and embeddings.
- q4, q6, and q8 quantization settings.
- Resource profiles: Automatic, Small RAM, Balanced, Large RAM.
- Separate max answer-token settings for Chat and Code.
- Max context-window setting, still capped by the active resource profile.
- Reasoning picker with None, Low, Medium, High where the selected model supports
  reasoning.
- Context usage meter in the composer. The value is an estimate from current
  prompt/session/workspace context, not a tokenizer-exact MLX count.

### Workspace

- Open and restore local workspaces.
- File tree scanning with `.gitignore` and `.opencodeignore` support.
- FSEvents-based workspace watching.
- SQLite-backed workspace index with FTS5.
- Lexical, structured, and semantic/hybrid search foundations.
- Swift symbol/comment/import/reference extraction through tree-sitter.
- Safe file previews with binary, symlink, size, and workspace-boundary checks.
- `AGENTS.md` and configured instruction discovery for prompt context.
- Prompt reference expansion for local files/directories and bounded attachments.

### Tools And Agent Runtime

- Native agent routing with orchestrator/utility roles.
- Agent catalog and configurable agent prompts.
- Async token streaming.
- Retry policy for transient generation errors.
- Scoped model-callable tools:
  - `read_file`
  - `write_file`
  - `edit_file`
  - `apply_patch`
  - `grep`
  - `glob`
  - `todo`
  - `task`
  - `question`
  - `git_status`
  - `git_diff`
  - `run_tests`
  - `shell`
- Central permission policy with allow, ask, and deny effects.
- Interactive ask prompts for write/process permissions.
- Bounded managed tool output storage.
- Stale tool-call rejection.
- Todo, question, and task settlements surfaced through native UI state.

### Git And Review

- Git status and diff loading.
- Diff parsing and grouped diff presentation.
- Patch review with explicit accept/reject hunk state.
- Snapshot-before-mutation for write/edit/patch paths.
- Revert support through workspace snapshots.
- Worktree coordination foundations.

### Configuration

- JSON config discovery and hot reload.
- Deterministic precedence:
  - global config
  - user config
  - workspace config
- Policy evaluation with last-match behavior.
- Configured agents, model defaults, max steps, permissions, MCP metadata,
  formatter definitions, LSP definitions, and bounded tool output settings.
- JavaScript and TypeScript plugins are explicitly rejected.

## What Does Not Work Yet

- No cloud/provider inference. Models run locally in-process through MLX.
- No OpenCode/OpenChamber data importer. They are product/design references only.
- No Electron, webview, browser, React, HTML, or CSS UI runtime.
- No JavaScript or TypeScript plugin execution.
- No local HTTP module transport.
- No full MCP tool/resource execution runtime yet. MCP settings/status can be
  represented, and remote entries stay untrusted unless explicitly enabled.
- No web search/web fetch tools in the app.
- No native terminal surface yet.
- No voice input.
- No PR browser, remote tunnel, or PWA flow.
- No full multi-run launcher yet.
- No legacy `PersistedConversation` import in the new durable session UI.
- LSP and formatter configuration foundations exist, but broad language-server
  diagnostics and formatter execution are still limited.
- Skills/references/native extension catalogs are foundations, not a complete
  install/manage/run product surface.
- Large model compatibility depends on upstream `mlx-swift-lm` architecture
  support and your available unified memory.

## Model Support

Interless expects MLX-compatible Hugging Face model repositories that the native
Swift MLX stack can load. Use regular MLX q4, q6, or q8 checkpoints.

### Role Setup

Interless can run in either a small single-model setup or a larger role-specific
setup.

| Role | Required | Typical model |
|---|---:|---|
| Chat / Orchestrator | Yes | General instruction or reasoning model. |
| Utility | Optional in Small RAM mode | Smaller model for search, summaries, and simple tool decisions. |
| Embeddings | Optional | q8 embedding model for semantic retrieval. |

Small RAM mode uses the chat/orchestrator model for every agent task. Balanced
or larger profiles can use separate utility and embedding models when configured.

### Known Good Test/Development IDs

These IDs are useful for local testing because they are small or already wired
into tests/UI paths:

| Model ID | Use | Notes |
|---|---|---|
| `mlx-community/Llama-3.2-1B-Instruct-4bit` | Chat/small local tests | Small non-reasoning model. |
| `mlx-community/Qwen2.5-0.5B-Instruct-4bit` | Utility/tiny tests | Used by real-MLX integration tests. |
| `mlx-community/gemma-2-2b-it-4bit` | Download test/chat | Small enough for download-flow testing. |
| `Qwen/Qwen3-4B-MLX-4bit` | Reasoning tests | Shows None/Low/Medium/High reasoning options. |

The onboarding/catalog also includes architecture-target entries:

| Catalog ID | Intended Role | Notes |
|---|---|---|
| `Qwen3.6-35B-A3B` | Orchestrator | High-memory planning target. Use an actual MLX repo ID if downloading from Hugging Face. |
| `Qwen3.5-2B` | Utility | Small utility target. Use an actual MLX repo ID if downloading from Hugging Face. |
| `nomic-ai/nomic-embed-text-v1.5` | Embeddings | Optional semantic retrieval model. |

### Unsupported Models

- OptiQ or `mlx-optiq` mixed-precision checkpoints. Interless rejects model IDs
  containing `optiq` because the current Swift MLX path can produce corrupted
  output with those checkpoints.
- GGUF/GGML/Ollama model files.
- Python-only `mlx-lm` workflows that require custom Python runtime code.
- Non-MLX model repos that `mlx-swift-lm` cannot load.
- Remote/cloud model names that are not local MLX model repositories.

### Tool-Call Formats

Model settings can store a native tool-call format. Supported format labels are:

```text
json, lfm2, xml_function, glm4, gemma, kimi_k2, minimax_m2, mistral, llama3
```

For general testing, use `json` unless a specific model family requires a
family-specific format.

### Reasoning Behavior

Reasoning options are shown when the model ID indicates reasoning support, such
as `qwen3`, `qwq`, `thinking`, `reasoning`, or `deepseek-r`.

For Qwen3-style models:

- Reasoning None sends `/no_think` and strips `<think>...</think>` blocks from
  persisted/displayed output.
- Reasoning Low/Medium/High sends `/think` with bounded guidance.
- Reasoning consumes output tokens. If a model spends too many tokens thinking,
  raise the Chat or Code max answer-token setting in Settings -> Model & Context,
  or set reasoning back to None.

## Configuration Files

Interless reads JSON config from these locations, in order:

```text
/Library/Application Support/Interless/config.json
~/Library/Application Support/Interless/config.json
~/.interless/config.json
<workspace>/interless.json
<workspace>/.interless.json
<workspace>/.interless/config.json
<workspace>/.opencode.json
<workspace>/.opencode/config.json
```

Later files override or extend earlier files depending on the field. Workspace
config is watched and hot-reloaded.

Minimal example:

```json
{
  "model": "mlx-community/gemma-2-2b-it-4bit",
  "instructions": ["AGENTS.md"],
  "agents": {
    "general": {
      "model": "mlx-community/gemma-2-2b-it-4bit",
      "system": "Answer directly and keep responses concise.",
      "steps": 4
    },
    "plan": {
      "model": "Qwen/Qwen3-4B-MLX-4bit",
      "system": "Create implementation plans without editing files.",
      "steps": 6
    }
  },
  "experimental": {
    "policies": [
      { "effect": "deny", "action": "tool.write", "resource": "*" },
      { "effect": "ask", "action": "tool.network", "resource": "*" }
    ]
  },
  "tool_output": {
    "max_bytes": 65536
  }
}
```

Policy effects are `allow`, `ask`, or `deny`. Last matching policy wins.

## Build, Test, And Package

Fast build:

```sh
swift build
```

Fast model-free test suite:

```sh
./scripts/test.sh
```

Run a focused test:

```sh
./scripts/test.sh --filter AppCoreTests
```

Deterministic local soak:

```sh
./scripts/soak-fast.sh
```

Real MLX integration tests are opt-in and require full Xcode/Metal:

```sh
./scripts/test-integration.sh
```

Those tests download small MLX models on first run and exercise GPU token
streaming. They are intentionally not part of the default fast suite.

Package the macOS app:

```sh
SKIP_SIGN=1 ./scripts/package-app.sh
```

Package with signing:

```sh
SIGN_IDENTITY="Developer ID Application: Your Name" ./scripts/package-app.sh
```

Useful package variables:

| Variable | Default | Meaning |
|---|---|---|
| `CONFIGURATION` | `release` | Build configuration. |
| `OUTPUT_DIR` | `.build/app` | Destination for the `.app`. |
| `APP_NAME` | `Interless` | Bundle/executable name. |
| `BUNDLE_IDENTIFIER` | `dev.interless.app` | macOS bundle identifier. |
| `SKIP_SIGN` | `0` | Set `1` to skip codesigning. |
| `BUILD_SYSTEM` | `xcodebuild` | Use `xcodebuild` or `swiftpm`. |

## CLI

Run the agent CLI in fake mode:

```sh
swift run interless-agent --prompt "Summarize this workspace"
```

Run with a real MLX model:

```sh
swift run interless-agent \
  --model mlx-community/gemma-2-2b-it-4bit \
  --quantization q4 \
  --tool-call-format json \
  --prompt "Inspect the test status"
```

Useful CLI flags:

- `--workspace <path>` defaults to the current directory.
- `--kind <auto|architecture|plan|refactor|multiFileEdit|search|summarize|lint|test|simpleQuestion>`.
- `--model <id>` sets one model for all roles.
- `--orchestrator-model <id>` and `--utility-model <id>` override roles.
- `--embedding-model <id>` optionally loads embeddings.
- `--tool-call-format <format>` supports `json`, `lfm2`, `xml_function`,
  `glm4`, `gemma`, `kimi_k2`, `minimax_m2`, `mistral`, and `llama3`.
- `--allow-writes` allows write/edit/patch tools.
- `--allow-network-tools` allows trusted process tools such as
  `./scripts/test.sh`.
- `--max-tool-iterations <n>` defaults to `4`.

## Safety Model

- File reads and writes are workspace-contained.
- Writes are denied by default.
- Process/network tools are denied by default.
- `ask` permissions suspend the tool call until the user allows or denies it.
- Tool output is bounded and retained through managed output references.
- Patches and writes snapshot files before mutation.
- Diagnostics exports are local and redacted by default.
- Prompts, source bodies, tool output, secrets, and full paths are excluded from
  default diagnostics exports.

## Troubleshooting

### The app says Loading model for a long time

When the model is not in the Hugging Face cache, Interless downloads it before
loading. The composer should show `Downloading model - xx%` during that phase.
If it does not progress, check network access, model ID spelling, and whether the
model requires a Hugging Face token.

### The answer stops inside reasoning or `<think>`

Reasoning models spend output tokens on the thinking trace. Raise Chat or Code
max answer tokens in Settings -> Model & Context, or choose Reasoning: None. For
Qwen3-style models, None sends `/no_think` and strips think blocks from the
persisted/displayed answer.

### The context meter looks approximate

The context meter estimates prompt/session/workspace context usage before MLX
tokenization. It is useful as a pressure indicator, but exact token counts depend
on the selected model tokenizer.

### A model ID is hidden or rejected

Interless filters known-unsafe IDs such as OptiQ checkpoints. Use a regular MLX
q4/q6/q8 Hugging Face repo instead.

### Xcode or Metal errors during build/package

Make sure the full Xcode app is selected and the Metal toolchain is installed:

```sh
sudo xcode-select -s /Applications/Xcode.app
sudo xcodebuild -runFirstLaunch
xcodebuild -downloadComponent MetalToolchain
xcrun metal --version
```

## Repository Layout

| Path | Role |
|---|---|
| `Shared/` | Value types shared across modules: model roles, generation requests, tokens, resources, compatibility. |
| `Core/` | Event bus, config, policy, recovery, diagnostics, metrics, session event/export infrastructure. |
| `MLXEngine/` | In-process MLX inference, model loading, memory coordination, embedding support. |
| `Workspace/` | Scanner, ignore rules, FSEvents, git providers, worktrees, snapshots, formatter/LSP foundations. |
| `Persistence/` | SQLite app/session/config stores and workspace index schema. |
| `Tooling/` | Scoped tool registry, policy enforcement, bounded execution, tool settlements. |
| `Security/` | Keychain-backed secret storage. |
| `Agents/` | Agent routing, context building, prompt expansion, tool loop, retry policy. |
| `UI/` | Pure SwiftUI presentation models and views. |
| `AppCore/` | App preferences, dependency composition, observable workspace/session model. |
| `App/` | SwiftUI app lifecycle, menus, window wiring. |
| `AgentCLI/`, `InterlessAgentCLI/` | Command-line agent harness. |
| `Tests/` | Fast unit/integration tests plus gated real-MLX tests. |

## Fresh Install Reset

To simulate a first launch, quit Interless, then remove local app state:

```sh
rm -rf ~/Library/Application\ Support/Interless
defaults delete dev.interless.app 2>/dev/null || true
```

If you packaged with a custom `BUNDLE_IDENTIFIER`, delete that defaults domain
instead of `dev.interless.app`.

This does not remove Hugging Face model caches. To remove downloaded models,
delete the relevant model directories from your Hugging Face cache.

## Contributing Rules

- Keep runtime code native Swift.
- Do not add Electron, React, HTML/CSS app surfaces, WebViews, JavaScript plugin
  execution, or local HTTP module transport.
- Keep `UI` presentation-only. It must not import MLX, Workspace, Persistence,
  Tooling, Agents, GRDB, or process/filesystem runtime modules.
- Keep `MLXEngine` as the only module that imports MLX.
- Keep workspace scanning/search/git concerns in `Workspace`.
- Keep tool containment, policy, cancellation, and bounded output in `Tooling`.
- Run `./scripts/test.sh` before packaging or handing off feature work.
