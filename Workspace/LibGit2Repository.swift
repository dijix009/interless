import Foundation
import Shared

public enum GitRepositoryBackend: String, Sendable, Equatable, Codable {
    case libgit2
    case processFallback
}

public enum GitRepositoryError: Error, Sendable, Equatable {
    case pathOutsideRepository(String)
    case commandFailed(String)
}

public actor LibGit2Repository: GitMetadataProvider {
    public nonisolated let backend: GitRepositoryBackend
    private let fallback: ProcessGitMetadata
    private let gitURL: URL
    private let timeout: Duration
    private let runner = ProcessRunner()

    public init(
        gitPath: String = "/usr/bin/git",
        timeout: Duration = .seconds(5),
        backend: GitRepositoryBackend = .processFallback
    ) {
        self.gitURL = URL(fileURLWithPath: gitPath)
        self.timeout = timeout
        self.backend = backend
        self.fallback = ProcessGitMetadata(gitPath: gitPath, timeout: timeout)
    }

    public func snapshot(root: URL) async -> GitStatus {
        await fallback.snapshot(root: root)
    }

    public func diff(root: URL, path: String? = nil) async throws -> String {
        let resolvedRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        var arguments = ["-C", resolvedRoot.path, "-c", "core.quotepath=false", "diff"]
        if let path {
            try validate(path: path, root: resolvedRoot)
            arguments += ["--", path]
        }
        let result = try await runner.run(executableURL: gitURL, arguments: arguments, timeout: timeout)
        guard result.exitCode == 0 else {
            throw GitRepositoryError.commandFailed(String(decoding: result.stderr, as: UTF8.self))
        }
        return String(decoding: result.stdout, as: UTF8.self)
    }

    public func worktrees(root: URL) async throws -> [WorkspaceWorktree] {
        try await WorktreeCoordinator(root: root).list()
    }

    private func validate(path: String, root: URL) throws {
        guard !path.hasPrefix("/") else { throw GitRepositoryError.pathOutsideRepository(path) }
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        guard !components.contains("..") else { throw GitRepositoryError.pathOutsideRepository(path) }
        let candidate = root.appendingPathComponent(path).standardizedFileURL
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard candidate.path == root.path || candidate.path.hasPrefix(rootPath) else {
            throw GitRepositoryError.pathOutsideRepository(path)
        }
    }
}
