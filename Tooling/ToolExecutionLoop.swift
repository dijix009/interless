import Foundation
import os

public actor ToolExecutionLoop {
    public typealias MutationRecorder = @Sendable (_ paths: [String], _ reason: String) async throws -> String?

    private let root: URL
    private let rootPath: String
    private let mutationRecorder: MutationRecorder?
    private let permissionCoordinator: ToolPermissionCoordinator
    private let managedOutputStore: ManagedToolOutputStore?
    private let permissionAuthorizer: ToolPermissionAuthorizer?
    private let settlementHandlers: ToolSettlementHandlers
    public nonisolated let policy: ToolExecutionPolicy
    private let log = Logger(subsystem: "dev.interless", category: "tool execution")

    public init(
        root: URL,
        policy: ToolExecutionPolicy = .default,
        mutationRecorder: MutationRecorder? = nil,
        managedOutputStore: ManagedToolOutputStore? = nil,
        permissionAuthorizer: ToolPermissionAuthorizer? = nil,
        settlementHandlers: ToolSettlementHandlers = .empty
    ) throws {
        let resolvedRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolvedRoot.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ToolError.pathNotFound(root.path)
        }
        self.root = resolvedRoot
        self.rootPath = resolvedRoot.path.hasSuffix("/") ? resolvedRoot.path : resolvedRoot.path + "/"
        self.mutationRecorder = mutationRecorder
        self.permissionCoordinator = ToolPermissionCoordinator(policy: policy)
        self.managedOutputStore = managedOutputStore
        self.permissionAuthorizer = permissionAuthorizer
        self.settlementHandlers = settlementHandlers
        self.policy = policy
    }

    public func execute(_ request: ToolRequest) async throws -> ToolResult {
        try Task.checkCancellation()
        try await permissionCoordinator.authorize(request, authorizer: permissionAuthorizer)
        switch request {
        case let .readFile(path):
            let url = try resolve(path: path, mustExist: true)
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: policy.maxOutputBytes) ?? Data()
            let text = String(decoding: data.prefix(policy.maxOutputBytes), as: UTF8.self)
            return await manage(ToolResult(request: request, stdout: text))

        case let .writeFile(path, contents):
            let byteCount = contents.utf8.count
            guard byteCount <= policy.maxWriteBytes else {
                throw ToolError.writeTooLarge(bytes: byteCount, limit: policy.maxWriteBytes)
            }
            let url = try resolve(path: path, mustExist: false)
            let relativePath = relativePath(for: url)
            let operation: ToolFileChange.Operation = FileManager.default.fileExists(atPath: url.path) ? .edited : .created
            let snapshotID = try await recordMutation(paths: [relativePath], reason: "write_file")
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try contents.write(to: url, atomically: true, encoding: .utf8)
            let verification = Self.verifiedSummary(url: url).map { "\n" + $0 } ?? ""
            return await manage(ToolResult(
                request: request,
                stdout: path + verification,
                didWrite: true,
                snapshotID: snapshotID,
                fileChanges: [ToolFileChange(path: relativePath, operation: operation, snapshotID: snapshotID)]))

        case let .editFile(path, old, new, replaceAll):
            let result = try await editFile(path: path, old: old, new: new, replaceAll: replaceAll, request: request)
            return await manage(result)

        case let .applyPatch(patch):
            let result = try await applyPatch(patch, request: request)
            return await manage(result)

        case let .grep(pattern, path, maxResults):
            let output = try grep(pattern: pattern, path: path, maxResults: maxResults)
            return await manage(ToolResult(request: request, stdout: output))

        case let .glob(pattern, path, maxResults):
            let output = try glob(pattern: pattern, path: path, maxResults: maxResults)
            return await manage(ToolResult(request: request, stdout: output))

        case let .todo(items):
            if let updateTodos = settlementHandlers.updateTodos {
                let output = try await updateTodos(items)
                return await manage(ToolResult(request: request, stdout: output))
            }
            let output = items.enumerated().map { index, item in
                "\(index + 1). [\(item.status.rawValue)] \(item.title)"
            }.joined(separator: "\n")
            return await manage(ToolResult(request: request, stdout: output))

        case let .task(prompt, agent):
            guard let spawnSubagent = settlementHandlers.spawnSubagent else {
                throw ToolError.settlementUnavailable("sub-agent delegation unavailable")
            }
            let summary = try await spawnSubagent(prompt, agent)
            return await manage(ToolResult(
                request: request,
                stdout: String(summary.prefix(policy.maxOutputBytes))))

        case let .question(prompt, options):
            guard let askQuestion = settlementHandlers.askQuestion else {
                throw ToolError.settlementUnavailable("question requires UI")
            }
            let response = try await askQuestion(ToolQuestionRequest(prompt: prompt, options: options))
            return await manage(ToolResult(request: request, stdout: response.answer))

        case let .recall(query, limit):
            guard let recallHistory = settlementHandlers.recallHistory else {
                throw ToolError.settlementUnavailable("conversation recall unavailable")
            }
            let output = await recallHistory(query, max(1, min(limit, 10)))
            return await manage(ToolResult(request: request, stdout: output))

        case .gitStatus:
            return await manage(try await run(command: ["git", "status", "--short"], request: request))

        case let .gitDiff(path):
            if let path {
                _ = try resolve(path: path, mustExist: true)
                return await manage(try await run(command: ["git", "diff", "--", path], request: request))
            }
            return await manage(try await run(command: ["git", "diff"], request: request))

        case let .runTests(arguments):
            return await manage(try await run(command: ["./scripts/test.sh"] + arguments, request: request))

        case let .shell(command):
            return await manage(try await run(command: command, request: request))
        }
    }

    private func manage(_ result: ToolResult) async -> ToolResult {
        guard let managedOutputStore else { return result }
        var copy = result
        copy.outputRef = await managedOutputStore.store(result: result)
        return copy
    }

    private func resolve(path: String, mustExist: Bool) throws -> URL {
        let candidate: URL
        if path.hasPrefix("/") {
            candidate = URL(fileURLWithPath: path)
        } else {
            candidate = root.appendingPathComponent(path)
        }

        if mustExist {
            let resolved = candidate.standardizedFileURL.resolvingSymlinksInPath()
            guard FileManager.default.fileExists(atPath: resolved.path) else {
                throw ToolError.pathNotFound(path)
            }
            guard isInsideRoot(resolved) else {
                throw ToolError.pathOutsideWorkspace(path)
            }
            return resolved
        }

        // Walk up to the nearest EXISTING ancestor so files can be created in
        // not-yet-existing subdirectories (e.g. a patch adding new/Module/File).
        // Containment is checked on the resolved ancestor; the missing segments
        // below it cannot contain symlinks, and standardizedFileURL has already
        // normalized any ".." components.
        var parent = candidate.deletingLastPathComponent().standardizedFileURL
        while !FileManager.default.fileExists(atPath: parent.path), parent.path != "/" {
            parent = parent.deletingLastPathComponent()
        }
        parent = parent.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: parent.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ToolError.pathNotFound(parent.path)
        }
        guard isInsideRoot(parent) else {
            throw ToolError.pathOutsideWorkspace(path)
        }
        if FileManager.default.fileExists(atPath: candidate.path) {
            let resolved = candidate.standardizedFileURL.resolvingSymlinksInPath()
            guard isInsideRoot(resolved) else {
                throw ToolError.pathOutsideWorkspace(path)
            }
            return resolved
        }
        return candidate.standardizedFileURL
    }

    private func isInsideRoot(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return path == root.path || path.hasPrefix(rootPath)
    }

    private func relativePath(for url: URL) -> String {
        let path = url.standardizedFileURL.path
        if path == root.path { return "" }
        if path.hasPrefix(rootPath) {
            return String(path.dropFirst(rootPath.count))
        }
        return path
    }

    private func recordMutation(paths: [String], reason: String) async throws -> String? {
        try Task.checkCancellation()
        guard let mutationRecorder else { return nil }
        return try await mutationRecorder(paths, reason)
    }

    private func editFile(
        path: String,
        old: String,
        new: String,
        replaceAll: Bool,
        request: ToolRequest
    ) async throws -> ToolResult {
        guard !old.isEmpty else {
            throw ToolError.invalidToolArguments(tool: "edit_file", reason: "'old' must not be empty")
        }
        let url = try resolve(path: path, mustExist: true)
        let contents = try String(contentsOf: url, encoding: .utf8)

        let updated: String
        if replaceAll {
            guard contents.contains(old) else { throw ToolError.editTargetNotFound(path: path) }
            updated = contents.replacingOccurrences(of: old, with: new)
        } else {
            // Unique-match contract: a single exact match is replaced; multiple
            // matches are rejected so the model must disambiguate (an unattended
            // fix loop must never silently edit the wrong site). Only when there
            // is no exact match do we fall back to a conservative whitespace /
            // line-ending tolerant retry, which still requires a unique match.
            let matches = Self.exactRanges(of: old, in: contents)
            if matches.count == 1 {
                updated = Self.replacing(matches[0], in: contents, with: new)
            } else if matches.count > 1 {
                throw ToolError.ambiguousEditTarget(path: path, count: matches.count)
            } else if let tolerant = Self.tolerantUniqueRange(of: old, in: contents) {
                updated = Self.replacing(tolerant, in: contents, with: new)
            } else {
                throw ToolError.editTargetNotFound(path: path)
            }
        }

        let byteCount = updated.utf8.count
        guard byteCount <= policy.maxWriteBytes else {
            throw ToolError.writeTooLarge(bytes: byteCount, limit: policy.maxWriteBytes)
        }
        let snapshotID = try await recordMutation(paths: [relativePath(for: url)], reason: "edit_file")
        try updated.write(to: url, atomically: true, encoding: .utf8)
        let verification = Self.verifiedSummary(url: url).map { "\n" + $0 } ?? ""
        return ToolResult(
            request: request,
            stdout: path + verification,
            didWrite: true,
            snapshotID: snapshotID,
            fileChanges: [ToolFileChange(path: relativePath(for: url), operation: .edited, snapshotID: snapshotID)])
    }

    private static func replacing(_ range: Range<String.Index>, in text: String, with replacement: String) -> String {
        var copy = text
        copy.replaceSubrange(range, with: replacement)
        return copy
    }

    /// All non-overlapping exact ranges of `target` in `text` (bounded by file size).
    private static func exactRanges(of target: String, in text: String) -> [Range<String.Index>] {
        guard !target.isEmpty else { return [] }
        var ranges: [Range<String.Index>] = []
        var searchStart = text.startIndex
        while searchStart < text.endIndex,
              let range = text.range(of: target, range: searchStart..<text.endIndex) {
            ranges.append(range)
            searchStart = range.upperBound > range.lowerBound
                ? range.upperBound
                : text.index(after: range.lowerBound)
        }
        return ranges
    }

    /// Conservative tolerant match, used only after an exact match fails: compares
    /// `target` against `text` under CRLF→LF and per-line trailing-whitespace
    /// normalization. Returns the real (un-normalized) range to replace only when
    /// the normalized match is unique; otherwise nil (it never guesses).
    private static func tolerantUniqueRange(of target: String, in text: String) -> Range<String.Index>? {
        let (normHay, map) = normalizedWithMap(text)
        let (normNeedle, _) = normalizedWithMap(target)
        guard !normNeedle.isEmpty else { return nil }
        var match: Range<String.Index>?
        var searchStart = normHay.startIndex
        while searchStart < normHay.endIndex,
              let range = normHay.range(of: normNeedle, range: searchStart..<normHay.endIndex) {
            if match != nil { return nil }   // ambiguous → refuse
            match = range
            searchStart = range.upperBound > range.lowerBound
                ? range.upperBound
                : normHay.index(after: range.lowerBound)
        }
        guard let match else { return nil }
        let lower = normHay.distance(from: normHay.startIndex, to: match.lowerBound)
        let upper = normHay.distance(from: normHay.startIndex, to: match.upperBound)
        return map[lower]..<map[upper]
    }

    /// Builds a normalized copy of `s` (CR dropped; horizontal whitespace that ends
    /// a line removed) plus a map from each normalized character offset back to its
    /// originating `String.Index`. Normalization only DROPS characters, so the map
    /// is exact and a normalized range maps to a real original range. The map has a
    /// trailing sentinel entry (`endIndex`) for exclusive upper bounds.
    private static func normalizedWithMap(_ s: String) -> (text: String, map: [String.Index]) {
        var text = ""
        text.reserveCapacity(s.count)
        var map: [String.Index] = []
        map.reserveCapacity(s.count + 1)
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if c == "\r" {
                i = s.index(after: i)
                continue
            }
            if c == " " || c == "\t" {
                var j = i
                while j < s.endIndex, s[j] == " " || s[j] == "\t" {
                    j = s.index(after: j)
                }
                let endsLine = j == s.endIndex || s[j] == "\n" || s[j] == "\r"
                if endsLine {
                    i = j
                    continue
                }
                var k = i
                while k < j {
                    text.append(s[k])
                    map.append(k)
                    k = s.index(after: k)
                }
                i = j
                continue
            }
            text.append(c)
            map.append(i)
            i = s.index(after: i)
        }
        map.append(s.endIndex)
        return (text, map)
    }

    private func applyPatch(_ patch: String, request: ToolRequest) async throws -> ToolResult {
        guard patch.utf8.count <= policy.maxWriteBytes else {
            throw ToolError.writeTooLarge(bytes: patch.utf8.count, limit: policy.maxWriteBytes)
        }
        let files = try parseUnifiedPatch(patch)
        guard !files.isEmpty else { throw ToolError.patchRejected("patch does not contain file hunks") }

        // Phase 1 — plan: resolve paths and compute the full new state IN MEMORY.
        // Nothing is written until every file validates, so a context mismatch in a
        // later file cannot leave earlier files partially written (atomic apply).
        struct PlannedChange {
            let targetURL: URL
            let targetPath: String
            let operation: ToolFileChange.Operation
            let newContents: String?     // nil ⇒ delete
            let sourceURL: URL?          // rename source to remove
            let sourcePath: String?
        }

        func additionOnlyContents(_ filePatch: ParsedPatchFile) -> String {
            filePatch.hunks.flatMap { $0.lines.map(\.text) }.joined(separator: "\n") + "\n"
        }

        var planned: [PlannedChange] = []
        var snapshotPaths: [String] = []

        for filePatch in files {
            switch filePatch.op {
            case .delete:
                let target = try resolve(path: filePatch.path, mustExist: true)
                let rel = relativePath(for: target)
                snapshotPaths.append(rel)
                planned.append(PlannedChange(
                    targetURL: target, targetPath: rel, operation: .deleted,
                    newContents: nil, sourceURL: nil, sourcePath: nil))

            case .rename:
                guard let oldPath = filePatch.oldPath else {
                    throw ToolError.patchRejected("rename patch missing source path")
                }
                let source = try resolve(path: oldPath, mustExist: true)
                let target = try resolve(path: filePatch.path, mustExist: false)
                let sourceContents = try String(contentsOf: source, encoding: .utf8)
                let newContents = filePatch.hunks.isEmpty
                    ? sourceContents
                    : try apply(filePatch, to: sourceContents)
                try ensureWithinWriteLimit(newContents)
                let sourceRel = relativePath(for: source)
                let targetRel = relativePath(for: target)
                snapshotPaths.append(sourceRel)
                snapshotPaths.append(targetRel)
                planned.append(PlannedChange(
                    targetURL: target, targetPath: targetRel, operation: .renamed,
                    newContents: newContents, sourceURL: source, sourcePath: sourceRel))

            case .create:
                let target = try resolve(path: filePatch.path, mustExist: false)
                guard !FileManager.default.fileExists(atPath: target.path) else {
                    throw ToolError.patchRejected("\(filePatch.path) already exists")
                }
                guard filePatch.hunks.allSatisfy({ $0.lines.allSatisfy { $0.marker == "+" } }) else {
                    throw ToolError.patchRejected("\(filePatch.path) creation must contain only addition lines")
                }
                let newContents = additionOnlyContents(filePatch)
                try ensureWithinWriteLimit(newContents)
                let rel = relativePath(for: target)
                snapshotPaths.append(rel)
                planned.append(PlannedChange(
                    targetURL: target, targetPath: rel, operation: .created,
                    newContents: newContents, sourceURL: nil, sourcePath: nil))

            case .edit:
                let target = try resolve(path: filePatch.path, mustExist: false)
                let rel = relativePath(for: target)
                if FileManager.default.fileExists(atPath: target.path) {
                    let contents = try String(contentsOf: target, encoding: .utf8)
                    let newContents = try apply(filePatch, to: contents)
                    try ensureWithinWriteLimit(newContents)
                    snapshotPaths.append(rel)
                    planned.append(PlannedChange(
                        targetURL: target, targetPath: rel, operation: .edited,
                        newContents: newContents, sourceURL: nil, sourcePath: nil))
                } else {
                    // No explicit create marker but the file is missing: allow only
                    // pure-addition hunks to create it (back-compat with old behavior).
                    guard filePatch.hunks.allSatisfy({ $0.lines.allSatisfy { $0.marker == "+" } }) else {
                        throw ToolError.patchRejected("\(filePatch.path) does not exist; only pure-addition hunks can create it")
                    }
                    let newContents = additionOnlyContents(filePatch)
                    try ensureWithinWriteLimit(newContents)
                    snapshotPaths.append(rel)
                    planned.append(PlannedChange(
                        targetURL: target, targetPath: rel, operation: .created,
                        newContents: newContents, sourceURL: nil, sourcePath: nil))
                }
            }
        }

        // Phase 2 — commit: snapshot, then mutate the filesystem.
        let snapshotID = try await recordMutation(paths: snapshotPaths, reason: "apply_patch")
        var headerLines: [String] = []
        var verifiedLines: [String] = []
        var changes: [ToolFileChange] = []
        for change in planned {
            switch change.operation {
            case .deleted:
                try FileManager.default.removeItem(at: change.targetURL)
                headerLines.append("deleted \(change.targetPath)")
            default:
                if let newContents = change.newContents {
                    try FileManager.default.createDirectory(
                        at: change.targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try newContents.write(to: change.targetURL, atomically: true, encoding: .utf8)
                }
                if change.operation == .renamed,
                   let source = change.sourceURL,
                   source.standardizedFileURL != change.targetURL.standardizedFileURL {
                    try? FileManager.default.removeItem(at: source)
                    headerLines.append("renamed \(change.sourcePath ?? "?") → \(change.targetPath)")
                } else {
                    headerLines.append(change.targetPath)
                }
                if let line = Self.verifiedSummary(url: change.targetURL) { verifiedLines.append(line) }
            }
            changes.append(ToolFileChange(path: change.targetPath, operation: change.operation, snapshotID: snapshotID))
        }

        let verification = verifiedLines.joined(separator: "\n")
        return ToolResult(
            request: request,
            stdout: headerLines.joined(separator: "\n") + (verification.isEmpty ? "" : "\n" + verification),
            didWrite: true,
            snapshotID: snapshotID,
            fileChanges: changes)
    }

    /// Post-write verification line fed back to the model: re-reads the file so
    /// the loop confirms what is actually on disk (act → verify), cheaply.
    private static func verifiedSummary(url: URL) -> String? {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let lineCount = contents.utf8.reduce(into: 0) { if $1 == 0x0A { $0 += 1 } }
        return "verified \(url.lastPathComponent): \(lineCount) lines, \(contents.utf8.count) bytes on disk"
    }

    private func grep(pattern: String, path: String?, maxResults: Int?) throws -> String {
        let needle = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return "" }
        let limit = boundedResultLimit(maxResults)
        let files = try candidateFiles(path: path)
        var lines: [String] = []
        for file in files {
            if lines.count >= limit { break }
            guard let text = try boundedTextFile(at: file) else { continue }
            let relative = relativePath(for: file)
            for (offset, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                if line.localizedStandardContains(needle) {
                    lines.append("\(relative):\(offset + 1):\(line)")
                    if lines.count >= limit { break }
                }
            }
        }
        return truncateOutput(lines.joined(separator: "\n"))
    }

    private func glob(pattern: String, path: String?, maxResults: Int?) throws -> String {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let limit = boundedResultLimit(maxResults)
        let regex = try NSRegularExpression(pattern: globRegex(trimmed))
        let files = try candidateFiles(path: path)
        var matches: [String] = []
        for file in files {
            let relative = relativePath(for: file)
            let range = NSRange(relative.startIndex..<relative.endIndex, in: relative)
            if regex.firstMatch(in: relative, range: range) != nil {
                matches.append(relative)
                if matches.count >= limit { break }
            }
        }
        return truncateOutput(matches.joined(separator: "\n"))
    }

    private func candidateFiles(path: String?) throws -> [URL] {
        let start = try path.map { try resolve(path: $0, mustExist: true) } ?? root
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: start.path, isDirectory: &isDirectory) else {
            throw ToolError.pathNotFound(path ?? root.path)
        }
        if !isDirectory.boolValue {
            return [start]
        }
        guard let enumerator = FileManager.default.enumerator(
            at: start,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey],
            options: [],
            errorHandler: { _, _ in true })
        else { return [] }

        var files: [URL] = []
        while let object = enumerator.nextObject() {
            guard files.count < 5_000, let url = object as? URL else { break }
            let name = url.lastPathComponent
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            if values?.isDirectory == true {
                if [".git", ".interless", ".build", "node_modules"].contains(name) {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard values?.isRegularFile == true, isInsideRoot(url) else { continue }
            files.append(url.standardizedFileURL)
        }
        return files.sorted { relativePath(for: $0) < relativePath(for: $1) }
    }

    private func boundedTextFile(at url: URL) throws -> String? {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard size <= policy.maxWriteBytes else { return nil }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: min(policy.maxOutputBytes, max(8_192, policy.maxWriteBytes))) ?? Data()
        if data.prefix(8_192).contains(0) { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func boundedResultLimit(_ proposed: Int?) -> Int {
        min(max(proposed ?? 100, 0), 1_000)
    }

    private func truncateOutput(_ text: String) -> String {
        guard text.utf8.count > policy.maxOutputBytes else { return text }
        let prefix = text.utf8.prefix(max(0, policy.maxOutputBytes))
        return String(decoding: prefix, as: UTF8.self)
    }

    private func globRegex(_ pattern: String) -> String {
        var output = "^"
        var index = pattern.startIndex
        while index < pattern.endIndex {
            let character = pattern[index]
            let next = pattern.index(after: index)
            if character == "*" {
                if next < pattern.endIndex, pattern[next] == "*" {
                    let afterGlobstar = pattern.index(after: next)
                    if afterGlobstar < pattern.endIndex, pattern[afterGlobstar] == "/" {
                        output += "(?:.*/)?"
                        index = pattern.index(after: afterGlobstar)
                    } else {
                        output += ".*"
                        index = afterGlobstar
                    }
                } else {
                    output += "[^/]*"
                    index = next
                }
            } else if character == "?" {
                output += "[^/]"
                index = next
            } else {
                output += NSRegularExpression.escapedPattern(for: String(character))
                index = next
            }
        }
        output += "$"
        return output
    }

    private struct ParsedPatchFile {
        enum Op {
            case edit
            case create
            case delete
            case rename
        }
        var path: String          // destination path (file removed for `.delete`)
        var oldPath: String?      // rename source
        var op: Op
        var hunks: [ParsedPatchHunk]
    }

    private struct ParsedPatchHunk {
        var oldStart: Int
        var lines: [ParsedPatchLine]
    }

    private struct ParsedPatchLine {
        var marker: Character
        var text: String
    }

    private func parseUnifiedPatch(_ patch: String) throws -> [ParsedPatchFile] {
        let lines = patch.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var files: [ParsedPatchFile] = []

        // Per-file accumulators, reset by finishFile().
        var headerOld: String?      // from "diff --git a/old"
        var headerNew: String?      // from "diff --git b/new"
        var minusPath: String?      // from "--- "  (raw, may be /dev/null)
        var plusPath: String?       // from "+++ "  (raw, may be /dev/null)
        var renameFrom: String?
        var renameTo: String?
        var explicitDelete = false  // "deleted file mode"
        var explicitCreate = false  // "new file mode"
        var hunks: [ParsedPatchHunk] = []
        var currentHunk: ParsedPatchHunk?
        var started = false

        func finishHunk() {
            if let hunk = currentHunk {
                hunks.append(hunk)
                currentHunk = nil
            }
        }

        func resolved(_ raw: String?) -> String? {
            guard let raw, raw != "/dev/null" else { return nil }
            return stripPatchPrefix(raw)
        }

        func reset() {
            headerOld = nil; headerNew = nil
            minusPath = nil; plusPath = nil
            renameFrom = nil; renameTo = nil
            explicitDelete = false; explicitCreate = false
            hunks = []; currentHunk = nil
            started = false
        }

        func finishFile() throws {
            finishHunk()
            guard started else { return }
            let isRename = renameFrom != nil && renameTo != nil
            let isDelete = explicitDelete || plusPath == "/dev/null"
            let isCreate = explicitCreate || minusPath == "/dev/null"
            let dest = resolved(plusPath) ?? renameTo.map(stripPatchPrefix) ?? headerNew
            let src = resolved(minusPath) ?? renameFrom.map(stripPatchPrefix) ?? headerOld

            if isRename {
                guard let to = renameTo.map(stripPatchPrefix) ?? dest else {
                    throw ToolError.patchRejected("rename patch missing destination path")
                }
                files.append(ParsedPatchFile(
                    path: to, oldPath: renameFrom.map(stripPatchPrefix) ?? src, op: .rename, hunks: hunks))
            } else if isDelete {
                guard let path = src ?? dest else {
                    throw ToolError.patchRejected("delete patch missing path")
                }
                files.append(ParsedPatchFile(path: path, oldPath: nil, op: .delete, hunks: hunks))
            } else if isCreate {
                guard let path = dest ?? src else {
                    throw ToolError.patchRejected("create patch missing path")
                }
                files.append(ParsedPatchFile(path: path, oldPath: nil, op: .create, hunks: hunks))
            } else if !hunks.isEmpty {
                guard let path = dest ?? src else {
                    throw ToolError.patchRejected("patch missing file path")
                }
                files.append(ParsedPatchFile(path: path, oldPath: nil, op: .edit, hunks: hunks))
            }
            // else: a metadata-only section (e.g. mode change) → nothing to apply.
            reset()
        }

        for line in lines {
            if line.hasPrefix("diff --git ") {
                try finishFile()
                started = true
                let rest = String(line.dropFirst("diff --git ".count))
                let parts = rest.split(separator: " ", maxSplits: 1).map(String.init)
                if parts.count == 2 {
                    headerOld = stripPatchPrefix(parts[0])
                    headerNew = stripPatchPrefix(parts[1])
                }
                continue
            }
            if line.hasPrefix("rename from ") {
                renameFrom = String(line.dropFirst("rename from ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                started = true
                continue
            }
            if line.hasPrefix("rename to ") {
                renameTo = String(line.dropFirst("rename to ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                started = true
                continue
            }
            if line.hasPrefix("deleted file mode") { explicitDelete = true; started = true; continue }
            if line.hasPrefix("new file mode") { explicitCreate = true; started = true; continue }
            if line.hasPrefix("--- ") {
                // In a plain unified diff (no "diff --git"), a fresh "--- " after a
                // completed file section starts the next file.
                if headerOld == nil, headerNew == nil, plusPath != nil || !hunks.isEmpty || currentHunk != nil {
                    try finishFile()
                }
                minusPath = String(line.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
                started = true
                continue
            }
            if line.hasPrefix("+++ ") {
                plusPath = String(line.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
                started = true
                continue
            }
            if line.hasPrefix("@@ ") {
                finishHunk()
                currentHunk = ParsedPatchHunk(oldStart: try parseOldStart(line), lines: [])
                started = true
                continue
            }
            // Inside a hunk: body lines. Outside a hunk: ignore git metadata
            // (index, similarity index, old/new mode, Binary files, …).
            guard currentHunk != nil else { continue }
            guard let marker = line.first, marker == " " || marker == "-" || marker == "+" else {
                if line.hasPrefix("\\ No newline") { continue }
                throw ToolError.patchRejected("unsupported patch line: \(line)")
            }
            currentHunk?.lines.append(ParsedPatchLine(marker: marker, text: String(line.dropFirst())))
        }
        try finishFile()
        return files
    }

    private func stripPatchPrefix(_ rawPath: String) -> String {
        if rawPath.hasPrefix("a/") || rawPath.hasPrefix("b/") {
            return String(rawPath.dropFirst(2))
        }
        return rawPath
    }

    private func parseOldStart(_ header: String) throws -> Int {
        let parts = header.split(separator: " ")
        guard let oldPart = parts.first(where: { $0.hasPrefix("-") }) else {
            throw ToolError.patchRejected("missing old range in hunk header")
        }
        let number = oldPart.dropFirst().split(separator: ",").first.map(String.init) ?? "1"
        // `-0,0` is the standard header for file-creation patches (no old lines).
        guard let start = Int(number), start >= 0 else {
            throw ToolError.patchRejected("invalid old range in hunk header")
        }
        return start
    }

    private func apply(_ patch: ParsedPatchFile, to contents: String) throws -> String {
        let original = contents.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var output: [String] = []
        var cursor = 0

        for hunk in patch.hunks {
            let hunkStart = max(0, hunk.oldStart - 1)
            guard hunkStart >= cursor, hunkStart <= original.count else {
                throw ToolError.patchRejected("hunk for \(patch.path) is outside the file")
            }
            while cursor < hunkStart {
                output.append(original[cursor])
                cursor += 1
            }
            for line in hunk.lines {
                switch line.marker {
                case " ":
                    guard cursor < original.count, Self.lineMatches(original[cursor], line.text) else {
                        throw ToolError.patchRejected("context mismatch in \(patch.path)")
                    }
                    output.append(original[cursor])   // preserve the file's real content
                    cursor += 1
                case "-":
                    guard cursor < original.count, Self.lineMatches(original[cursor], line.text) else {
                        throw ToolError.patchRejected("remove mismatch in \(patch.path)")
                    }
                    cursor += 1
                case "+":
                    output.append(line.text)
                default:
                    throw ToolError.patchRejected("unsupported patch marker in \(patch.path)")
                }
            }
        }
        while cursor < original.count {
            output.append(original[cursor])
            cursor += 1
        }
        return output.joined(separator: "\n")
    }

    /// Conservative tolerant line equality for patch context/remove lines: exact
    /// first, then CRLF→LF and trailing-whitespace-insensitive.
    private static func lineMatches(_ a: String, _ b: String) -> Bool {
        a == b || normalizedLine(a) == normalizedLine(b)
    }

    private static func normalizedLine(_ s: String) -> String {
        var t = Substring(s)
        if t.hasSuffix("\r") { t = t.dropLast() }
        while let last = t.last, last == " " || last == "\t" { t = t.dropLast() }
        return String(t)
    }

    private func ensureWithinWriteLimit(_ contents: String) throws {
        let bytes = contents.utf8.count
        guard bytes <= policy.maxWriteBytes else {
            throw ToolError.writeTooLarge(bytes: bytes, limit: policy.maxWriteBytes)
        }
    }

    private func run(command: [String], request: ToolRequest) async throws -> ToolResult {
        guard !command.isEmpty else { throw ToolError.invalidCommand }
        try policy.validate(command: command)
        let captured = try await runProcessCapturing(command: command, timeoutSeconds: policy.timeoutSeconds)
        return ToolResult(
            request: request,
            exitCode: captured.exitCode,
            stdout: captured.stdout,
            stderr: captured.stderr)
    }

    /// Runs `command` and captures bounded stdout/stderr + exit code. Does NOT
    /// validate against the policy — the caller is responsible for that (so the
    /// verify loop can run whitelisted build/test commands under verifyPermission
    /// rather than the network gate).
    private func runProcessCapturing(command: [String], timeoutSeconds: Double) async throws -> (exitCode: Int32, stdout: String, stderr: String) {
        log.debug("tool start \(command.joined(separator: " "), privacy: .public)")

        let stdout = OutputBuffer(limit: policy.maxOutputBytes)
        let stderr = OutputBuffer(limit: policy.maxOutputBytes)
        let process = Process()
        process.currentDirectoryURL = root
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = command

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            stdout.append(handle.availableData)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            stderr.append(handle.availableData)
        }

        let box = RunningProcess(process)
        do {
            try process.run()
        } catch {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            throw ToolError.launchFailed(command: command, reason: String(describing: error))
        }

        do {
            let exit = try await waitForProcess(box, command: command, timeoutSeconds: timeoutSeconds)
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            stdout.append(stdoutPipe.fileHandleForReading.availableData)
            stderr.append(stderrPipe.fileHandleForReading.availableData)
            return (exit, stdout.stringValue, stderr.stringValue)
        } catch {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            box.terminate()
            if error is CancellationError { throw ToolError.cancelled }
            throw error
        }
    }

    /// Harness-driven verification for the autonomous fix loop: runs the policy's
    /// verify commands in order (e.g. `swift build`, then the test script),
    /// short-circuiting on the first failure so a broken build never triggers a
    /// slow test run. Returns nil when verification is disabled (verifyPermission
    /// is `.deny`, or no whitelisted command runs). Only commands that also match
    /// `allowedCommands` execute; gated by verifyPermission, not networkPermission.
    public func verify(changedPaths: [String]) async -> VerificationOutcome? {
        guard policy.verifyPermission != .deny else { return nil }
        var ran: [String] = []
        for command in policy.verifyCommands where !command.isEmpty {
            guard policy.matchingPattern(for: command) != nil else { continue }
            let label = command.joined(separator: " ")
            ran.append(label)
            do {
                let result = try await runProcessCapturing(command: command, timeoutSeconds: policy.verifyTimeoutSeconds)
                if result.exitCode != 0 {
                    return VerificationOutcome(
                        passed: false,
                        summary: "`\(label)` failed (exit \(result.exitCode))",
                        details: Self.combinedTail(stdout: result.stdout, stderr: result.stderr, limit: policy.maxOutputBytes))
                }
            } catch {
                return VerificationOutcome(
                    passed: false,
                    summary: "`\(label)` could not run",
                    details: String(describing: error))
            }
        }
        guard !ran.isEmpty else { return nil }
        return VerificationOutcome(passed: true, summary: "passed: \(ran.joined(separator: ", "))")
    }

    /// Keeps the trailing (most relevant) portion of combined command output.
    private static func combinedTail(stdout: String, stderr: String, limit: Int) -> String {
        let combined = [stdout, stderr]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        guard limit > 0, combined.utf8.count > limit else { return combined }
        return "…(truncated)\n" + String(decoding: Array(combined.utf8).suffix(limit), as: UTF8.self)
    }

    private func waitForProcess(_ box: RunningProcess, command: [String], timeoutSeconds: Double) async throws -> Int32 {
        return try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: Int32.self) { group in
                group.addTask {
                    await box.waitUntilExit()
                }
                group.addTask {
                    try await Task.sleep(for: .milliseconds(Int(timeoutSeconds * 1000)))
                    box.terminate()
                    throw ToolError.timedOut(command: command, seconds: timeoutSeconds)
                }
                guard let result = try await group.next() else { throw ToolError.cancelled }
                group.cancelAll()
                return result
            }
        } onCancel: {
            box.terminate()
        }
    }
}

private final class RunningProcess: @unchecked Sendable {
    private let lock = NSLock()
    private let process: Process
    private var continuation: CheckedContinuation<Int32, Never>?

    init(_ process: Process) {
        self.process = process
    }

    func waitUntilExit() async -> Int32 {
        await withCheckedContinuation { continuation in
            lock.withLock {
                self.continuation = continuation
            }
            process.terminationHandler = { [weak self] process in
                guard let self else { return }
                let saved = self.lock.withLock {
                    let continuation = self.continuation
                    self.continuation = nil
                    return continuation
                }
                saved?.resume(returning: process.terminationStatus)
            }
            if !process.isRunning {
                let saved = lock.withLock {
                    let continuation = self.continuation
                    self.continuation = nil
                    return continuation
                }
                saved?.resume(returning: process.terminationStatus)
            }
        }
    }

    func terminate() {
        if process.isRunning {
            process.terminate()
        }
    }
}

private final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var data = Data()

    init(limit: Int) {
        self.limit = limit
    }

    func append(_ newData: Data) {
        guard !newData.isEmpty, limit > 0 else { return }
        lock.withLock {
            let remaining = limit - data.count
            guard remaining > 0 else { return }
            data.append(newData.prefix(remaining))
        }
    }

    var stringValue: String {
        lock.withLock { String(decoding: data, as: UTF8.self) }
    }
}
