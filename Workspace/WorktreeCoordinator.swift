import Foundation

public enum WorktreeCoordinatorError: Error, Sendable, Equatable {
    case notARepository
    case invalidPath(String)
    case rootWorktreeRemovalDenied
    case gitUnavailable
    case gitFailed(command: String, exitCode: Int32, stderr: String)
    case gitTimedOut(command: String)
}

public struct WorkspaceWorktree: Sendable, Equatable, Codable, Identifiable {
    public var id: String { path }
    public var path: String
    public var branch: String?
    public var headSHA: String?
    public var isBare: Bool
    public var isDetached: Bool

    public init(
        path: String,
        branch: String? = nil,
        headSHA: String? = nil,
        isBare: Bool = false,
        isDetached: Bool = false
    ) {
        self.path = path
        self.branch = branch
        self.headSHA = headSHA
        self.isBare = isBare
        self.isDetached = isDetached
    }
}

public actor WorktreeCoordinator {
    private let root: URL
    private let gitURL: URL
    private let timeout: Duration
    private let runner: ProcessRunner

    public init(
        root: URL,
        gitPath: String = "/usr/bin/git",
        timeout: Duration = .seconds(10),
        runner: ProcessRunner = ProcessRunner()
    ) {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        self.gitURL = URL(fileURLWithPath: gitPath)
        self.timeout = timeout
        self.runner = runner
    }

    public func list() async throws -> [WorkspaceWorktree] {
        let result = try await git(["worktree", "list", "--porcelain"])
        let text = String(decoding: result.stdout, as: UTF8.self)
        return Self.parsePorcelainList(text)
    }

    @discardableResult
    public func add(path: URL, branch: String? = nil, newBranch: String? = nil) async throws -> WorkspaceWorktree {
        let target = try validatedWorktreePath(path)
        var arguments = ["worktree", "add"]
        if let newBranch, !newBranch.isEmpty {
            arguments += ["-b", newBranch]
        }
        arguments.append(target.path)
        if let branch, !branch.isEmpty {
            arguments.append(branch)
        }
        _ = try await git(arguments)
        return WorkspaceWorktree(path: target.path, branch: newBranch ?? branch)
    }

    public func remove(path: URL, force: Bool = false) async throws {
        let target = try validatedWorktreePath(path)
        guard target.path != root.path else {
            throw WorktreeCoordinatorError.rootWorktreeRemovalDenied
        }
        var arguments = ["worktree", "remove"]
        if force { arguments.append("--force") }
        arguments.append(target.path)
        _ = try await git(arguments)
    }

    public func prune() async throws {
        _ = try await git(["worktree", "prune"])
    }

    static func parsePorcelainList(_ text: String) -> [WorkspaceWorktree] {
        var worktrees: [WorkspaceWorktree] = []
        var current: WorkspaceWorktree?

        func finish() {
            if let current {
                worktrees.append(current)
            }
            current = nil
        }

        for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.isEmpty {
                finish()
                continue
            }
            if let path = line.dropPrefix("worktree ") {
                finish()
                current = WorkspaceWorktree(path: path)
            } else if let head = line.dropPrefix("HEAD ") {
                current?.headSHA = head
            } else if let branch = line.dropPrefix("branch ") {
                current?.branch = branch.replacingOccurrences(of: "refs/heads/", with: "")
            } else if line == "bare" {
                current?.isBare = true
            } else if line == "detached" {
                current?.isDetached = true
            }
        }
        finish()
        return worktrees
    }

    private func git(_ arguments: [String]) async throws -> ProcessRunner.Result {
        guard FileManager.default.isExecutableFile(atPath: gitURL.path) else {
            throw WorktreeCoordinatorError.gitUnavailable
        }
        let command = ["-C", root.path] + arguments
        let result = try await runner.run(executableURL: gitURL, arguments: command, timeout: timeout)
        if result.timedOut {
            throw WorktreeCoordinatorError.gitTimedOut(command: command.joined(separator: " "))
        }
        guard result.exitCode == 0 else {
            throw WorktreeCoordinatorError.gitFailed(
                command: command.joined(separator: " "),
                exitCode: result.exitCode,
                stderr: String(decoding: result.stderr, as: UTF8.self))
        }
        return result
    }

    private func validatedWorktreePath(_ path: URL) throws -> URL {
        let resolved = path.standardizedFileURL.resolvingSymlinksInPath()
        guard resolved.path.hasPrefix("/") else {
            throw WorktreeCoordinatorError.invalidPath(path.path)
        }
        guard resolved.path != root.path else {
            throw WorktreeCoordinatorError.invalidPath(path.path)
        }
        return resolved
    }
}

private extension String {
    func dropPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count))
    }
}
