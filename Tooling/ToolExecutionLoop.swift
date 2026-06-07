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
            let snapshotID = try await recordMutation(paths: [relativePath(for: url)], reason: "write_file")
            try contents.write(to: url, atomically: true, encoding: .utf8)
            return await manage(ToolResult(request: request, stdout: path, didWrite: true, snapshotID: snapshotID))

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

        case let .task(prompt):
            guard let scheduleTask = settlementHandlers.scheduleTask else {
                throw ToolError.settlementUnavailable("task scheduling unavailable")
            }
            let settlement = try await scheduleTask(prompt)
            return await manage(ToolResult(
                request: request,
                stdout: "job_id: \(settlement.jobID.uuidString)\nstatus: \(settlement.status)\n\(settlement.message)"))

        case let .question(prompt, options):
            guard let askQuestion = settlementHandlers.askQuestion else {
                throw ToolError.settlementUnavailable("question requires UI")
            }
            let response = try await askQuestion(ToolQuestionRequest(prompt: prompt, options: options))
            return await manage(ToolResult(request: request, stdout: response.answer))

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

        let parent = candidate.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath()
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
        guard contents.contains(old) else { throw ToolError.editTargetNotFound(path: path) }
        let updated = replaceAll
            ? contents.replacingOccurrences(of: old, with: new)
            : replaceFirst(old, with: new, in: contents)
        let byteCount = updated.utf8.count
        guard byteCount <= policy.maxWriteBytes else {
            throw ToolError.writeTooLarge(bytes: byteCount, limit: policy.maxWriteBytes)
        }
        let snapshotID = try await recordMutation(paths: [relativePath(for: url)], reason: "edit_file")
        try updated.write(to: url, atomically: true, encoding: .utf8)
        return ToolResult(request: request, stdout: path, didWrite: true, snapshotID: snapshotID)
    }

    private func replaceFirst(_ target: String, with replacement: String, in text: String) -> String {
        guard let range = text.range(of: target) else { return text }
        var copy = text
        copy.replaceSubrange(range, with: replacement)
        return copy
    }

    private func applyPatch(_ patch: String, request: ToolRequest) async throws -> ToolResult {
        guard patch.utf8.count <= policy.maxWriteBytes else {
            throw ToolError.writeTooLarge(bytes: patch.utf8.count, limit: policy.maxWriteBytes)
        }
        let files = try parseUnifiedPatch(patch)
        guard !files.isEmpty else { throw ToolError.patchRejected("patch does not contain file hunks") }
        let paths = files.map(\.path)
        let urls = try files.map { try resolve(path: $0.path, mustExist: true) }
        let snapshotID = try await recordMutation(paths: paths, reason: "apply_patch")
        for (filePatch, url) in zip(files, urls) {
            let contents = try String(contentsOf: url, encoding: .utf8)
            let updated = try apply(filePatch, to: contents)
            guard updated.utf8.count <= policy.maxWriteBytes else {
                throw ToolError.writeTooLarge(bytes: updated.utf8.count, limit: policy.maxWriteBytes)
            }
            try updated.write(to: url, atomically: true, encoding: .utf8)
        }
        return ToolResult(
            request: request,
            stdout: paths.joined(separator: "\n"),
            didWrite: true,
            snapshotID: snapshotID)
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
        var path: String
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
        var currentPath: String?
        var currentHunks: [ParsedPatchHunk] = []
        var currentHunk: ParsedPatchHunk?

        func finishHunk() {
            if let hunk = currentHunk {
                currentHunks.append(hunk)
                currentHunk = nil
            }
        }

        func finishFile() {
            finishHunk()
            if let path = currentPath, !currentHunks.isEmpty {
                files.append(ParsedPatchFile(path: path, hunks: currentHunks))
            }
            currentPath = nil
            currentHunks = []
        }

        for line in lines {
            if line.hasPrefix("diff --git ") {
                finishFile()
                continue
            }
            if line.hasPrefix("+++ ") {
                finishFile()
                let rawPath = String(line.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
                guard rawPath != "/dev/null" else {
                    throw ToolError.patchRejected("creating files from patches is not supported yet")
                }
                currentPath = stripPatchPrefix(rawPath)
                continue
            }
            if line.hasPrefix("@@ ") {
                finishHunk()
                currentHunk = ParsedPatchHunk(oldStart: try parseOldStart(line), lines: [])
                continue
            }
            guard currentPath != nil, currentHunk != nil else { continue }
            guard let marker = line.first, marker == " " || marker == "-" || marker == "+" else {
                if line.hasPrefix("\\ No newline") { continue }
                throw ToolError.patchRejected("unsupported patch line: \(line)")
            }
            currentHunk?.lines.append(ParsedPatchLine(marker: marker, text: String(line.dropFirst())))
        }
        finishFile()
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
        guard let start = Int(number), start > 0 else {
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
                    guard cursor < original.count, original[cursor] == line.text else {
                        throw ToolError.patchRejected("context mismatch in \(patch.path)")
                    }
                    output.append(original[cursor])
                    cursor += 1
                case "-":
                    guard cursor < original.count, original[cursor] == line.text else {
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

    private func run(command: [String], request: ToolRequest) async throws -> ToolResult {
        guard !command.isEmpty else { throw ToolError.invalidCommand }
        try policy.validate(command: command)
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
            let exit = try await waitForProcess(box, command: command)
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            stdout.append(stdoutPipe.fileHandleForReading.availableData)
            stderr.append(stderrPipe.fileHandleForReading.availableData)
            return ToolResult(
                request: request,
                exitCode: exit,
                stdout: stdout.stringValue,
                stderr: stderr.stringValue)
        } catch {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            box.terminate()
            if error is CancellationError { throw ToolError.cancelled }
            throw error
        }
    }

    private func waitForProcess(_ box: RunningProcess, command: [String]) async throws -> Int32 {
        let timeoutSeconds = policy.timeoutSeconds
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
