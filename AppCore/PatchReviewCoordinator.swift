import Foundation
import Shared
import UI
import Workspace

public enum PatchReviewError: Error, Sendable, Equatable, CustomStringConvertible {
    case writesDisabled
    case noAcceptedHunks
    case invalidPath(String)
    case pathEscapesWorkspace(String)
    case binaryPatchUnsupported(String)
    case staleContext(String)
    case malformedPatch(String)
    case fileTooLarge(path: String, bytes: Int, limit: Int)

    public var description: String {
        switch self {
        case .writesDisabled:
            return "Write tools are disabled."
        case .noAcceptedHunks:
            return "No accepted hunks to apply."
        case .invalidPath(let path):
            return "Invalid patch path: \(path)"
        case .pathEscapesWorkspace(let path):
            return "Patch path escapes the workspace: \(path)"
        case .binaryPatchUnsupported(let path):
            return "Binary patch is unsupported: \(path)"
        case .staleContext(let path):
            return "Patch context no longer matches: \(path)"
        case .malformedPatch(let reason):
            return "Malformed patch: \(reason)"
        case .fileTooLarge(let path, let bytes, let limit):
            return "Patch target is too large to apply safely: \(path) (\(bytes) bytes, limit \(limit) bytes)"
        }
    }
}

public struct PatchApplyResult: Sendable, Equatable {
    public var filesChanged: Int
    public var hunksApplied: Int
    public var snapshotID: UUID?

    public init(filesChanged: Int, hunksApplied: Int, snapshotID: UUID? = nil) {
        self.filesChanged = filesChanged
        self.hunksApplied = hunksApplied
        self.snapshotID = snapshotID
    }
}

public struct PatchReviewCoordinator: Sendable {
    public var root: URL
    public var allowsWrites: Bool
    public var maxTargetFileBytes: Int
    public var snapshotStore: WorkspaceSnapshotStore?

    public init(
        root: URL,
        allowsWrites: Bool,
        maxTargetFileBytes: Int = ResourceBudget.balanced.maxIndexedFileSizeBytes,
        snapshotStore: WorkspaceSnapshotStore? = nil
    ) {
        self.root = root
        self.allowsWrites = allowsWrites
        self.maxTargetFileBytes = max(0, maxTargetFileBytes)
        self.snapshotStore = snapshotStore
    }

    public static func parseUnifiedDiff(_ diff: String, title: String = "Patch Proposal") -> PatchProposal {
        var files: [PatchFile] = []
        var diagnostics: [String] = []
        var currentFile: PatchFile?
        var currentHunk: PatchHunk?
        var hunkID = 0
        var lineID = 0

        func finishHunk() {
            guard let hunk = currentHunk else { return }
            currentFile?.hunks.append(hunk)
            currentHunk = nil
        }

        func finishFile() {
            finishHunk()
            guard let file = currentFile else { return }
            files.append(file)
            currentFile = nil
        }

        for raw in diff.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.hasPrefix("diff --git") {
                finishFile()
                let parsed = parseDiffHeader(line)
                currentFile = PatchFile(oldPath: parsed.oldPath, newPath: parsed.newPath)
                continue
            }

            if line.hasPrefix("Binary files") {
                currentFile?.diagnostics.append("Binary patches are unsupported.")
                continue
            }

            if line.hasPrefix("--- ") {
                if currentFile == nil { currentFile = PatchFile(oldPath: "", newPath: "") }
                currentFile?.oldPath = stripDiffPath(String(line.dropFirst(4)))
                continue
            }

            if line.hasPrefix("+++ ") {
                if currentFile == nil { currentFile = PatchFile(oldPath: "", newPath: "") }
                currentFile?.newPath = stripDiffPath(String(line.dropFirst(4)))
                continue
            }

            if line.hasPrefix("@@") {
                finishHunk()
                guard let range = parseHunkHeader(line) else {
                    diagnostics.append("Could not parse hunk header: \(line)")
                    continue
                }
                currentHunk = PatchHunk(
                    id: hunkID,
                    header: line,
                    oldStart: range.oldStart,
                    oldCount: range.oldCount,
                    newStart: range.newStart,
                    newCount: range.newCount,
                    lines: [])
                hunkID += 1
                continue
            }

            guard currentHunk != nil else { continue }
            if line.hasPrefix("+") {
                currentHunk?.lines.append(.init(id: lineID, kind: .addition, text: String(line.dropFirst())))
            } else if line.hasPrefix("-") {
                currentHunk?.lines.append(.init(id: lineID, kind: .deletion, text: String(line.dropFirst())))
            } else if line.hasPrefix(" ") {
                currentHunk?.lines.append(.init(id: lineID, kind: .context, text: String(line.dropFirst())))
            } else if line == "\\ No newline at end of file" {
                continue
            } else if line.isEmpty {
                currentHunk?.lines.append(.init(id: lineID, kind: .context, text: ""))
            } else {
                diagnostics.append("Unexpected patch line: \(line)")
            }
            lineID += 1
        }

        finishFile()
        if files.isEmpty && !diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            diagnostics.append("No file patches were found.")
        }
        return PatchProposal(title: title, files: files, diagnostics: diagnostics)
    }

    public func apply(_ proposal: PatchProposal) async throws -> PatchApplyResult {
        guard allowsWrites else { throw PatchReviewError.writesDisabled }
        let acceptedFiles = proposal.files.filter { !$0.acceptedHunks.isEmpty }
        guard !acceptedFiles.isEmpty else { throw PatchReviewError.noAcceptedHunks }
        let targetPaths = try acceptedFiles.map { file in
            if file.diagnostics.contains(where: { $0.localizedCaseInsensitiveContains("binary") }) {
                throw PatchReviewError.binaryPatchUnsupported(file.id)
            }
            return file.newPath == "/dev/null" ? file.oldPath : file.newPath
        }
        let snapshot = try await snapshotStore?.createSnapshot(
            paths: targetPaths,
            reason: "apply_patch")

        var filesChanged = 0
        var hunksApplied = 0
        for (file, targetPath) in zip(acceptedFiles, targetPaths) {
            let targetURL = try Self.resolve(root: root, relativePath: targetPath)
            let oldText = try Self.readTargetText(
                at: targetURL,
                relativePath: targetPath,
                maxBytes: maxTargetFileBytes)
            let newText = try Self.apply(hunks: file.acceptedHunks, to: oldText, path: targetPath)
            try FileManager.default.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try newText.write(to: targetURL, atomically: true, encoding: .utf8)
            filesChanged += 1
            hunksApplied += file.acceptedHunks.count
        }
        return PatchApplyResult(filesChanged: filesChanged, hunksApplied: hunksApplied, snapshotID: snapshot?.id)
    }

    private static func readTargetText(at url: URL, relativePath: String, maxBytes: Int) throws -> String {
        guard FileManager.default.fileExists(atPath: url.path) else { return "" }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard size <= maxBytes else {
            throw PatchReviewError.fileTooLarge(path: relativePath, bytes: size, limit: maxBytes)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func apply(hunks: [PatchHunk], to text: String, path: String) throws -> String {
        var lines = splitLines(text)
        for hunk in hunks {
            let oldBlock = hunk.lines.compactMap { line -> String? in
                line.kind == .addition ? nil : line.text
            }
            let newBlock = hunk.lines.compactMap { line -> String? in
                line.kind == .deletion ? nil : line.text
            }
            let start = find(oldBlock, in: lines, near: max(hunk.oldStart - 1, 0))
            guard let start else { throw PatchReviewError.staleContext(path) }
            lines.replaceSubrange(start..<(start + oldBlock.count), with: newBlock)
        }
        return lines.joined(separator: "\n") + (text.hasSuffix("\n") ? "\n" : "")
    }

    private static func splitLines(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if text.hasSuffix("\n") { lines.removeLast() }
        return lines
    }

    private static func find(_ needle: [String], in haystack: [String], near: Int) -> Int? {
        if needle.isEmpty { return min(near, haystack.count) }
        let candidates = Array(0...max(haystack.count - needle.count, 0)).sorted {
            abs($0 - near) < abs($1 - near)
        }
        return candidates.first { index in
            Array(haystack[index..<(index + needle.count)]) == needle
        }
    }

    private static func resolve(root: URL, relativePath: String) throws -> URL {
        let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "/dev/null", !trimmed.hasPrefix("/") else {
            throw PatchReviewError.invalidPath(relativePath)
        }
        let rootURL = root.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = rootURL.appendingPathComponent(trimmed).standardizedFileURL.resolvingSymlinksInPath()
        let rootPath = rootURL.path
        guard candidate.path == rootPath || candidate.path.hasPrefix(rootPath + "/") else {
            throw PatchReviewError.pathEscapesWorkspace(relativePath)
        }
        return candidate
    }

    private static func parseDiffHeader(_ line: String) -> (oldPath: String, newPath: String) {
        let parts = line.split(separator: " ").map(String.init)
        guard parts.count >= 4 else { return ("", "") }
        return (stripDiffPath(parts[2]), stripDiffPath(parts[3]))
    }

    private static func stripDiffPath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "/dev/null" { return trimmed }
        if trimmed.hasPrefix("a/") || trimmed.hasPrefix("b/") {
            return String(trimmed.dropFirst(2))
        }
        return trimmed
    }

    private static func parseHunkHeader(_ line: String) -> (oldStart: Int, oldCount: Int, newStart: Int, newCount: Int)? {
        let parts = line.split(separator: " ")
        guard parts.count >= 3,
              parts[1].hasPrefix("-"),
              parts[2].hasPrefix("+") else {
            return nil
        }
        guard let oldRange = parseRange(String(parts[1].dropFirst())),
              let newRange = parseRange(String(parts[2].dropFirst())) else {
            return nil
        }
        return (oldRange.start, oldRange.count, newRange.start, newRange.count)
    }

    private static func parseRange(_ text: String) -> (start: Int, count: Int)? {
        let parts = text.split(separator: ",", omittingEmptySubsequences: false)
        guard let start = Int(parts[0]) else { return nil }
        let count = parts.count > 1 ? (Int(parts[1]) ?? 1) : 1
        return (start, count)
    }
}
