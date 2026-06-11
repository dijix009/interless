import Foundation
import Testing
import Shared
import Tooling

struct ToolingTests {
    @Test func readsWorkspaceContainedFile() async throws {
        let temp = try TempWorkspace()
        try temp.write("hello", to: "a.txt")
        let loop = try ToolExecutionLoop(root: temp.url)

        let result = try await loop.execute(.readFile(path: "a.txt"))

        #expect(result.stdout == "hello")
    }

    @Test func readFileUsesBoundedRead() async throws {
        let temp = try TempWorkspace()
        try temp.write(String(repeating: "x", count: 1_000), to: "large.txt")
        let loop = try ToolExecutionLoop(
            root: temp.url,
            policy: ToolExecutionPolicy(maxOutputBytes: 16))

        let result = try await loop.execute(.readFile(path: "large.txt"))

        #expect(result.stdout.count == 16)
    }

    @Test func rejectsOutsideRootPath() async throws {
        let temp = try TempWorkspace()
        let outside = temp.url.deletingLastPathComponent().appendingPathComponent("outside-\(UUID().uuidString).txt")
        try "secret".write(to: outside, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: outside) }
        let loop = try ToolExecutionLoop(root: temp.url)

        do {
            _ = try await loop.execute(.readFile(path: outside.path))
            Issue.record("expected outside-root rejection")
        } catch let error as ToolError {
            #expect(error == .pathOutsideWorkspace(outside.path))
        }
    }

    @Test func writeFileIsDeniedByDefaultAndAllowedByPolicy() async throws {
        let temp = try TempWorkspace()
        let dryRun = try ToolExecutionLoop(root: temp.url)
        await #expect(throws: ToolError.writeDenied) {
            _ = try await dryRun.execute(.writeFile(path: "new.txt", contents: "nope"))
        }

        let writer = try ToolExecutionLoop(root: temp.url, policy: ToolExecutionPolicy(allowsWrites: true))
        let result = try await writer.execute(.writeFile(path: "new.txt", contents: "ok"))

        #expect(result.didWrite)
        #expect(try String(contentsOf: temp.url.appendingPathComponent("new.txt"), encoding: .utf8) == "ok")
    }

    @Test func askWritePolicyRequiresAuthorizerAndResumesOnDecision() async throws {
        let temp = try TempWorkspace()
        let askPolicy = ToolExecutionPolicy(writePermission: .ask)
        let missingAuthorizer = try ToolExecutionLoop(root: temp.url, policy: askPolicy)

        do {
            _ = try await missingAuthorizer.execute(.writeFile(path: "blocked.txt", contents: "nope"))
            Issue.record("expected ask policy without authorizer to deny")
        } catch let error as ToolError {
            guard case .permissionDenied = error else {
                Issue.record("expected permissionDenied, got \(error)")
                return
            }
        }

        let recorder = PermissionRecorder()
        let allowed = try ToolExecutionLoop(
            root: temp.url,
            policy: askPolicy,
            permissionAuthorizer: { request in
                await recorder.record(request)
                return .allowOnce
            })
        let result = try await allowed.execute(.writeFile(path: "allowed.txt", contents: "ok"))
        #expect(result.didWrite)
        #expect(try String(contentsOf: temp.url.appendingPathComponent("allowed.txt"), encoding: .utf8) == "ok")
        #expect(await recorder.toolNames == ["writeFile"])

        let denied = try ToolExecutionLoop(
            root: temp.url,
            policy: askPolicy,
            permissionAuthorizer: { _ in .deny })
        do {
            _ = try await denied.execute(.writeFile(path: "denied.txt", contents: "nope"))
            Issue.record("expected denied authorizer to deny")
        } catch let error as ToolError {
            guard case .permissionDenied = error else {
                Issue.record("expected permissionDenied, got \(error)")
                return
            }
        }
    }

    @Test func writeFileRecordsMutationBeforeWriting() async throws {
        let temp = try TempWorkspace()
        let recorder = MutationRecorderSpy()
        let writer = try ToolExecutionLoop(
            root: temp.url,
            policy: ToolExecutionPolicy(allowsWrites: true),
            mutationRecorder: { paths, reason in
                await recorder.record(paths: paths, reason: reason)
            })

        let result = try await writer.execute(.writeFile(path: "new.txt", contents: "ok"))

        #expect(result.snapshotID == "snapshot-1")
        #expect(await recorder.calls == [.init(paths: ["new.txt"], reason: "write_file")])
        #expect(try String(contentsOf: temp.url.appendingPathComponent("new.txt"), encoding: .utf8) == "ok")
    }

    @Test func writeFileRejectsContentsOverPolicyCap() async throws {
        let temp = try TempWorkspace()
        let loop = try ToolExecutionLoop(
            root: temp.url,
            policy: ToolExecutionPolicy(allowsWrites: true, maxWriteBytes: 4))

        await #expect(throws: ToolError.writeTooLarge(bytes: 5, limit: 4)) {
            _ = try await loop.execute(.writeFile(path: "too-large.txt", contents: "12345"))
        }
    }

    @Test func editFileAndApplyPatchSnapshotBeforeMutating() async throws {
        let temp = try TempWorkspace()
        try temp.write("hello\nworld\n", to: "file.txt")
        let recorder = MutationRecorderSpy()
        let loop = try ToolExecutionLoop(
            root: temp.url,
            policy: ToolExecutionPolicy(allowsWrites: true),
            mutationRecorder: { paths, reason in
                await recorder.record(paths: paths, reason: reason)
            })

        let edit = try await loop.execute(.editFile(path: "file.txt", old: "world", new: "edited"))
        let patch = try await loop.execute(.applyPatch(patch: """
        diff --git a/file.txt b/file.txt
        --- a/file.txt
        +++ b/file.txt
        @@ -1,2 +1,2 @@
         hello
        -edited
        +patched
        """))

        #expect(edit.didWrite)
        #expect(patch.didWrite)
        #expect(edit.snapshotID == "snapshot-1")
        #expect(patch.snapshotID == "snapshot-2")
        #expect(await recorder.calls == [
            .init(paths: ["file.txt"], reason: "edit_file"),
            .init(paths: ["file.txt"], reason: "apply_patch"),
        ])
        #expect(try String(contentsOf: temp.url.appendingPathComponent("file.txt"), encoding: .utf8) == "hello\npatched\n")
    }

    @Test func applyPatchCreatesNewFileFromPureAdditionHunks() async throws {
        let temp = try TempWorkspace()
        let loop = try ToolExecutionLoop(
            root: temp.url,
            policy: ToolExecutionPolicy(allowsWrites: true))
        let result = try await loop.execute(.applyPatch(patch: """
        diff --git a/new/Created.txt b/new/Created.txt
        --- /dev/null
        +++ b/new/Created.txt
        @@ -0,0 +1,2 @@
        +first line
        +second line
        """))
        #expect(result.didWrite)
        #expect(result.stdout.contains("verified Created.txt"))
        #expect(try String(contentsOf: temp.url.appendingPathComponent("new/Created.txt"), encoding: .utf8) == "first line\nsecond line\n")
    }

    @Test func managedOutputStoreRetainsBoundedOutputRefs() async throws {
        let temp = try TempWorkspace()
        try temp.write("0123456789", to: "large.txt")
        let store = ManagedToolOutputStore(maxEntries: 1, maxBytesPerStream: 4)
        let loop = try ToolExecutionLoop(root: temp.url, managedOutputStore: store)

        let result = try await loop.execute(.readFile(path: "large.txt"))
        let ref = try #require(result.outputRef)
        let stored = try #require(await store.output(id: ref.id))

        #expect(ref.stdoutBytes == 10)
        #expect(ref.isTruncated)
        #expect(stored.stdout == "0123")
        #expect(await store.allRefs().map(\.id) == [ref.id])
    }

    @Test func todoQuestionAndTaskUseSettlementHandlers() async throws {
        let temp = try TempWorkspace()
        let jobID = UUID()
        let loop = try ToolExecutionLoop(
            root: temp.url,
            settlementHandlers: ToolSettlementHandlers(
                updateTodos: { items in
                    "persisted \(items.count) todos"
                },
                askQuestion: { request in
                    #expect(request.prompt == "Proceed?")
                    #expect(request.options == ["yes", "no"])
                    return ToolQuestionResponse(answer: "yes")
                },
                scheduleTask: { prompt in
                    ToolTaskSettlement(jobID: jobID, status: "queued", message: prompt)
                }))

        let todo = try await loop.execute(.todo(items: [
            ToolTodoItem(title: "Inspect", status: .inProgress),
        ]))
        let question = try await loop.execute(.question(prompt: "Proceed?", options: ["yes", "no"]))
        let task = try await loop.execute(.task(prompt: "Summarize"))

        #expect(todo.stdout == "persisted 1 todos")
        #expect(question.stdout == "yes")
        #expect(task.stdout.contains(jobID.uuidString))
        #expect(task.stdout.contains("status: queued"))
        #expect(task.stdout.contains("Summarize"))
    }

    @Test func questionAndTaskHaveDeterministicNoUIFallbacks() async throws {
        let temp = try TempWorkspace()
        let loop = try ToolExecutionLoop(root: temp.url)

        let todo = try await loop.execute(.todo(items: [
            ToolTodoItem(title: "Inspect", status: .pending),
        ]))
        #expect(todo.stdout == "1. [pending] Inspect")
        await #expect(throws: ToolError.settlementUnavailable("question requires UI")) {
            _ = try await loop.execute(.question(prompt: "Proceed?"))
        }
        await #expect(throws: ToolError.settlementUnavailable("task scheduling unavailable")) {
            _ = try await loop.execute(.task(prompt: "Summarize"))
        }
    }

    @Test func rejectsUnallowlistedShellCommand() async throws {
        let temp = try TempWorkspace()
        let loop = try ToolExecutionLoop(root: temp.url)

        do {
            _ = try await loop.execute(.shell(command: ["rm", "-rf", "."]))
            Issue.record("expected command denial")
        } catch let error as ToolError {
            #expect(error == .commandDenied(["rm", "-rf", "."]))
        }
    }

    @Test func grepSearchesPlainTextWithBounds() async throws {
        let temp = try TempWorkspace()
        try temp.write("alpha\nneedle one\n", to: "Sources/A.swift")
        try temp.write("needle two\nneedle three\n", to: "Sources/B.swift")
        try temp.write("needle ignored\n", to: ".build/Generated.swift")
        let loop = try ToolExecutionLoop(root: temp.url)

        let result = try await loop.execute(.grep(pattern: "needle", path: "Sources", maxResults: 2))

        #expect(result.stdout.contains("Sources/A.swift:2:needle one"))
        #expect(result.stdout.contains("Sources/B.swift:1:needle two"))
        #expect(!result.stdout.contains("needle three"))
        #expect(!result.stdout.contains(".build"))
    }

    @Test func globFindsWorkspacePathsWithBounds() async throws {
        let temp = try TempWorkspace()
        try temp.write("a", to: "Sources/A.swift")
        try temp.write("b", to: "Sources/Nested/B.swift")
        try temp.write("c", to: "Tests/C.swift")
        try temp.write("d", to: ".git/Hidden.swift")
        let loop = try ToolExecutionLoop(root: temp.url)

        let result = try await loop.execute(.glob(pattern: "Sources/**/*.swift", maxResults: 10))

        #expect(result.stdout.split(separator: "\n").map(String.init) == ["Sources/A.swift", "Sources/Nested/B.swift"])
        #expect(!result.stdout.contains(".git"))
    }

    @Test func capturesStdoutStderrAndExitCode() async throws {
        let temp = try TempWorkspace()
        let policy = ToolExecutionPolicy(networkEnabled: true, allowedCommands: [
            ToolCommandPattern(executable: "/bin/sh"),
        ])
        let loop = try ToolExecutionLoop(root: temp.url, policy: policy)

        let result = try await loop.execute(.shell(command: ["/bin/sh", "-c", "echo out; echo err >&2; exit 7"]))

        #expect(result.exitCode == 7)
        #expect(result.stdout.contains("out"))
        #expect(result.stderr.contains("err"))
    }

    @Test func enforcesTimeout() async throws {
        let temp = try TempWorkspace()
        let policy = ToolExecutionPolicy(timeoutSeconds: 0.1, allowedCommands: [
            ToolCommandPattern(executable: "/bin/sleep", requiresNetworkPermission: false),
        ])
        let loop = try ToolExecutionLoop(root: temp.url, policy: policy)

        do {
            _ = try await loop.execute(.shell(command: ["/bin/sleep", "2"]))
            Issue.record("expected timeout")
        } catch let error as ToolError {
            #expect(error == .timedOut(command: ["/bin/sleep", "2"], seconds: 0.1))
        }
    }

    @Test func supportsCancellation() async throws {
        let temp = try TempWorkspace()
        let policy = ToolExecutionPolicy(timeoutSeconds: 5, allowedCommands: [
            ToolCommandPattern(executable: "/bin/sleep", requiresNetworkPermission: false),
        ])
        let loop = try ToolExecutionLoop(root: temp.url, policy: policy)

        let task = Task {
            try await loop.execute(.shell(command: ["/bin/sleep", "2"]))
        }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("expected cancellation")
        } catch let error as ToolError {
            #expect(error == .cancelled)
        }
    }

    @Test func gitStatusAndDiffRunInsideWorkspace() async throws {
        let temp = try TempWorkspace()
        try await temp.run(["git", "init"])
        try temp.write("one\n", to: "tracked.txt")

        let loop = try ToolExecutionLoop(root: temp.url)
        let status = try await loop.execute(.gitStatus)
        #expect(status.stdout.contains("tracked.txt"))

        try await temp.run(["git", "add", "tracked.txt"])
        try temp.write("two\n", to: "tracked.txt")
        let diff = try await loop.execute(.gitDiff(path: "tracked.txt"))
        #expect(diff.stdout.contains("-one"))
        #expect(diff.stdout.contains("+two"))
    }

    @Test func runTestsUsesAllowlistedScript() async throws {
        let temp = try TempWorkspace()
        try FileManager.default.createDirectory(at: temp.url.appendingPathComponent("scripts"), withIntermediateDirectories: true)
        try temp.write("#!/usr/bin/env bash\necho fake tests \"$@\"\n", to: "scripts/test.sh")
        try await temp.run(["chmod", "+x", "scripts/test.sh"])
        let loop = try ToolExecutionLoop(root: temp.url, policy: ToolExecutionPolicy(networkEnabled: true))

        let result = try await loop.execute(.runTests(arguments: ["--filter", "Fake"]))

        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("fake tests --filter Fake"))
    }

    @Test func networkRiskCommandsAreDeniedByDefault() async throws {
        let temp = try TempWorkspace()
        try FileManager.default.createDirectory(at: temp.url.appendingPathComponent("scripts"), withIntermediateDirectories: true)
        try temp.write("#!/usr/bin/env bash\necho should-not-run\n", to: "scripts/test.sh")
        try await temp.run(["chmod", "+x", "scripts/test.sh"])
        let loop = try ToolExecutionLoop(root: temp.url)

        await #expect(throws: ToolError.networkDisabled(["./scripts/test.sh"])) {
            _ = try await loop.execute(.runTests(arguments: []))
        }
    }

    @Test func workspaceRegistryMapsValidModelCalls() throws {
        let registry = WorkspaceToolRegistry()
        let trustedRegistry = WorkspaceToolRegistry(policy: ToolExecutionPolicy(networkEnabled: true))

        #expect(try registry.request(from: ModelToolCall(
            name: "read_file",
            arguments: ["path": .string("README.md")])) == .readFile(path: "README.md"))
        #expect(try registry.request(from: ModelToolCall(name: "git_status")) == .gitStatus)
        #expect(try registry.request(from: ModelToolCall(
            name: "git_diff",
            arguments: ["path": .string("Sources/App.swift")])) == .gitDiff(path: "Sources/App.swift"))
        #expect(try registry.request(from: ModelToolCall(
            name: "grep",
            arguments: [
                "pattern": .string("needle"),
                "path": .string("Sources"),
                "max_results": .int(3),
            ])) == .grep(pattern: "needle", path: "Sources", maxResults: 3))
        #expect(try registry.request(from: ModelToolCall(
            name: "glob",
            arguments: [
                "pattern": .string("**/*.swift"),
                "max_results": .int(4),
            ])) == .glob(pattern: "**/*.swift", path: nil, maxResults: 4))
        #expect(try trustedRegistry.request(from: ModelToolCall(
            name: "edit_file",
            arguments: [
                "path": .string("README.md"),
                "old": .string("old"),
                "new": .string("new"),
                "replace_all": .bool(true),
            ])) == .editFile(path: "README.md", old: "old", new: "new", replaceAll: true))
        #expect(try trustedRegistry.request(from: ModelToolCall(
            name: "apply_patch",
            arguments: ["patch": .string("diff")])) == .applyPatch(patch: "diff"))
        #expect(try registry.request(from: ModelToolCall(
            name: "todo",
            arguments: ["items": .array([
                .object(["title": .string("Inspect"), "status": .string("inProgress")]),
            ])])) == .todo(items: [ToolTodoItem(title: "Inspect", status: .inProgress)]))
        #expect(try registry.request(from: ModelToolCall(
            name: "task",
            arguments: ["prompt": .string("Summarize")])) == .task(prompt: "Summarize"))
        #expect(try registry.request(from: ModelToolCall(
            name: "question",
            arguments: [
                "prompt": .string("Proceed?"),
                "options": .array([.string("yes"), .string("no")]),
            ])) == .question(prompt: "Proceed?", options: ["yes", "no"]))
        #expect(try trustedRegistry.request(from: ModelToolCall(
            name: "run_tests",
            arguments: ["arguments": .array([.string("--filter"), .string("Fake")])])) == .runTests(arguments: ["--filter", "Fake"]))
        #expect(try trustedRegistry.request(from: ModelToolCall(
            name: "shell",
            arguments: ["command": .array([.string("git"), .string("status")])])) == .shell(command: ["git", "status"]))
    }

    @Test func workspaceRegistryRejectsUnknownAndMalformedCalls() {
        let registry = WorkspaceToolRegistry()

        #expect(throws: ToolError.unknownTool("nope")) {
            _ = try registry.request(from: ModelToolCall(name: "nope"))
        }
        #expect(throws: ToolError.invalidToolArguments(tool: "read_file", reason: "missing required string 'path'")) {
            _ = try registry.request(from: ModelToolCall(name: "read_file"))
        }
        #expect(throws: ToolError.invalidToolArguments(tool: "shell", reason: "'command' must be an array of strings")) {
            _ = try registry.request(from: ModelToolCall(name: "shell", arguments: ["command": .string("git status")]))
        }
        #expect(throws: ToolError.invalidToolArguments(tool: "grep", reason: "'max_results' must be an integer")) {
            _ = try registry.request(from: ModelToolCall(
                name: "grep",
                arguments: ["pattern": .string("needle"), "max_results": .string("ten")]))
        }
        #expect(throws: ToolError.invalidToolArguments(tool: "todo", reason: "'items[0]' must include a non-empty title")) {
            _ = try registry.request(from: ModelToolCall(
                name: "todo",
                arguments: ["items": .array([.object(["status": .string("pending")])])]))
        }
    }

    @Test func writeToolIsAdvertisedOnlyWhenWritesAllowed() async throws {
        let readOnly = WorkspaceToolRegistry(policy: .default)
        let writable = WorkspaceToolRegistry(policy: ToolExecutionPolicy(allowsWrites: true))
        let askWritable = WorkspaceToolRegistry(policy: ToolExecutionPolicy(writePermission: .ask))

        #expect(!readOnly.definitions.map(\.name).contains("write_file"))
        #expect(writable.definitions.map(\.name).contains("write_file"))
        #expect(askWritable.definitions.map(\.name).contains("write_file"))
        #expect(writable.definitions.map(\.name).contains("edit_file"))
        #expect(writable.definitions.map(\.name).contains("apply_patch"))
        #expect(readOnly.definitions.map(\.name).contains("todo"))
        #expect(readOnly.definitions.map(\.name).contains("task"))
        #expect(readOnly.definitions.map(\.name).contains("question"))

        let temp = try TempWorkspace()
        let loop = try ToolExecutionLoop(root: temp.url)
        let request = try writable.request(from: ModelToolCall(
            name: "write_file",
            arguments: ["path": .string("a.txt"), "contents": .string("blocked")]))

        await #expect(throws: ToolError.writeDenied) {
            _ = try await loop.execute(request)
        }
    }

    @Test func scopedRegistryRejectsStaleToolCalls() throws {
        let registry = WorkspaceToolRegistry(generation: 7)

        #expect(registry.scopedRegistry.registration(name: "read_file")?.scope == .workspace)
        #expect(try registry.request(
            from: ModelToolCall(name: "read_file", arguments: ["path": .string("README.md")]),
            generation: 7) == .readFile(path: "README.md"))
        #expect(throws: ToolError.staleToolCall(name: "read_file", expectedGeneration: 7, actualGeneration: 6)) {
            _ = try registry.request(
                from: ModelToolCall(name: "read_file", arguments: ["path": .string("README.md")]),
                generation: 6)
        }
    }

    @Test func permissionCoordinatorCentralizesPolicyDecisions() {
        let readOnly = ToolPermissionCoordinator(policy: .default)
        #expect(readOnly.evaluate(.readFile(path: "README.md")).effect == .allow)
        #expect(readOnly.evaluate(.writeFile(path: "README.md", contents: "x")).effect == .deny)
        #expect(readOnly.evaluate(.shell(command: ["swift", "test"])).effect == .deny)

        let trusted = ToolPermissionCoordinator(policy: ToolExecutionPolicy(allowsWrites: true, networkEnabled: true))
        #expect(trusted.evaluate(.writeFile(path: "README.md", contents: "x")).effect == .allow)
        #expect(trusted.evaluate(.shell(command: ["swift", "test"])).effect == .allow)
    }

    @Test func networkRiskToolsAreAdvertisedOnlyWhenNetworkIsEnabled() {
        let defaultDefinitions = WorkspaceToolRegistry(policy: .default).definitions.map(\.name)
        #expect(!defaultDefinitions.contains("run_tests"))
        #expect(!defaultDefinitions.contains("shell"))

        let trustedDefinitions = WorkspaceToolRegistry(policy: ToolExecutionPolicy(networkEnabled: true)).definitions.map(\.name)
        #expect(trustedDefinitions.contains("run_tests"))
        #expect(trustedDefinitions.contains("shell"))
    }

    @Test func networkRiskModelCallsAreRejectedByDefaultPolicy() throws {
        let registry = WorkspaceToolRegistry(policy: .default)

        #expect(throws: ToolError.networkDisabled(["./scripts/test.sh"])) {
            _ = try registry.request(from: ModelToolCall(name: "run_tests"))
        }
        #expect(try registry.request(from: ModelToolCall(
            name: "shell",
            arguments: ["command": .array([.string("git"), .string("status")])])) == .shell(command: ["git", "status"]))
        #expect(throws: ToolError.networkDisabled(["swift", "test"])) {
            _ = try registry.request(from: ModelToolCall(
                name: "shell",
                arguments: ["command": .array([.string("swift"), .string("test")])]))
        }
    }
}

private actor MutationRecorderSpy {
    struct Call: Sendable, Equatable {
        var paths: [String]
        var reason: String
    }

    private(set) var calls: [Call] = []

    func record(paths: [String], reason: String) -> String {
        calls.append(Call(paths: paths, reason: reason))
        return "snapshot-\(calls.count)"
    }
}

private actor PermissionRecorder {
    private(set) var toolNames: [String] = []

    func record(_ request: ToolPermissionRequest) {
        toolNames.append(request.request.displayName)
    }
}

private final class TempWorkspace {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("if-tooling-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    func write(_ text: String, to path: String) throws {
        let fileURL = url.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    func run(_ command: [String]) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = command
        process.currentDirectoryURL = url
        try process.run()
        process.waitUntilExit()
    }
}
