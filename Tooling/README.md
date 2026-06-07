# Tooling/

Restricted tool execution subsystem (ARCHITECTURE.md §10, Phase 3).

Implemented:
- Workspace-scoped read file and policy-gated write file.
- Git status/diff wrappers.
- Test runner and restricted shell execution.
- Command allowlist, timeout, cancellation, stdout/stderr capture, and output caps.
- Default policy denies writes and network-oriented commands.
- `WorkspaceToolRegistry` for model-callable tool schemas and validation.

Model-callable tools:
- `read_file(path)`
- `write_file(path, contents)` only advertised when `allowsWrites == true`
- `git_status()`
- `git_diff(path?)`
- `run_tests(arguments?)` only advertised when `networkEnabled == true`
- `shell(command)` only advertised when `networkEnabled == true`

All model calls are converted to `ToolRequest` and still pass through the same path containment, symlink escape, write policy, timeout, and command allowlist checks.
Because tools run as local child processes rather than inside an OS network sandbox, commands that may execute workspace-controlled code require `networkEnabled == true`; the default policy keeps them unavailable.
