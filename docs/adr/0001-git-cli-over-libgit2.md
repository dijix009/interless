# ADR 0001: Git integration via the `git` CLI instead of libgit2

**Status:** Accepted (Phase 2a)

## Context
ARCHITECTURE.md §4 lists **libgit2** for Git integration. Phase 2 needs only
repository *metadata*: is-repository, current branch, HEAD SHA, and porcelain
status. There is currently **no maintained Swift binding for libgit2** (SwiftGit2
is Swift-4-era, last released 2019), and vendoring libgit2 itself means shipping a
binary XCFramework (libgit2 + OpenSSL + libssh2) — a heavy, build-complex dependency
for metadata we can obtain trivially.

## Decision
Read git metadata by invoking the system `git` CLI (`/usr/bin/git`, which ships
with macOS/Xcode) via `Foundation.Process`, behind the `GitMetadataProvider` seam
(`Workspace/GitMetadataProvider.swift`). The concrete implementation is
`ProcessGitMetadata`; `ProcessRunner` handles safe async stdout capture, timeout,
and cancellation (absolute path, `-C <root>`, no PATH search — §14).

## Consequences
- Zero dependency; available on every macOS dev machine.
- Sufficient for metadata; **not** intended for high-frequency or in-process
  diff/blame.
- Behind the seam, a future libgit2-backed `GitMetadataProvider` can replace this
  without touching callers — honoring the spec's libgit2 intent when fast
  diff/blame is needed (a later phase).
- This is a deliberate, recorded deviation from §4.
