/// Typed failures from the workspace engine (ARCHITECTURE.md §15 — failures must
/// not crash the host process).
public enum WorkspaceError: Error, Sendable, Equatable {
    case rootNotFound(String)
    case rootNotDirectory(String)
    case gitUnavailable
    case gitTimedOut(command: String)
    case gitFailed(command: String, exitCode: Int32, stderr: String)
    case cancelled
    case scanFailed(path: String, underlying: String)
}
