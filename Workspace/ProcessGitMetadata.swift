import Foundation
import os
import Shared

/// Git repository metadata via the system `git` CLI (ARCHITECTURE.md §9; see
/// `docs/adr/0001-git-cli-over-libgit2.md`). The only file spawning `git`.
public actor ProcessGitMetadata: GitMetadataProvider {

    private let gitURL: URL
    private let timeout: Duration
    private let runner = ProcessRunner()
    private let log = Logger(subsystem: "dev.interless", category: "workspace")

    public init(gitPath: String = "/usr/bin/git", timeout: Duration = .seconds(5)) {
        self.gitURL = URL(fileURLWithPath: gitPath)
        self.timeout = timeout
    }

    public func snapshot(root: URL) async -> GitStatus {
        guard FileManager.default.isExecutableFile(atPath: gitURL.path) else {
            log.notice("git not found at \(self.gitURL.path, privacy: .public)")
            return .notARepository
        }
        guard let inside = await git(root, ["rev-parse", "--is-inside-work-tree"]),
              inside.exitCode == 0,
              trimmed(inside.stdout) == "true"
        else {
            return .notARepository
        }

        let branch = await git(root, ["rev-parse", "--abbrev-ref", "HEAD"])
            .flatMap { $0.exitCode == 0 ? trimmed($0.stdout) : nil }
            .flatMap { $0 == "HEAD" ? nil : $0 }            // "HEAD" ⇒ detached
        let head = await git(root, ["rev-parse", "HEAD"])
            .flatMap { $0.exitCode == 0 ? trimmed($0.stdout) : nil }
        let entries = await git(root, ["status", "--porcelain", "-z", "--untracked-files=all"])
            .map { Self.parsePorcelainZ($0.stdout) } ?? []

        return GitStatus(isRepository: true, branch: branch, headSHA: head, entries: entries)
    }

    /// Run `git -C <root> -c core.quotepath=false <args>`. Returns nil on spawn
    /// failure/timeout (caller degrades gracefully — never throws out of snapshot).
    private func git(_ root: URL, _ args: [String]) async -> ProcessRunner.Result? {
        do {
            let result = try await runner.run(
                executableURL: gitURL,
                arguments: ["-C", root.path, "-c", "core.quotepath=false"] + args,
                timeout: timeout)
            if result.timedOut { log.error("git timed out: \(args.joined(separator: " "), privacy: .public)") }
            return result
        } catch {
            log.error("git failed to launch: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    private func trimmed(_ data: Data) -> String {
        String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Parse `git status --porcelain -z` output: NUL-separated `"XY path"` records.
    /// (Rename records carry an extra path field; treated leniently in 2a.)
    static func parsePorcelainZ(_ data: Data) -> [GitStatus.Entry] {
        let text = String(decoding: data, as: UTF8.self)
        return text.split(separator: "\0", omittingEmptySubsequences: true).compactMap { field in
            guard field.count >= 4 else { return nil }
            let xy = String(field.prefix(2))
            let path = String(field.dropFirst(3))   // skip "XY "
            return GitStatus.Entry(path: path, xy: xy)
        }
    }
}
