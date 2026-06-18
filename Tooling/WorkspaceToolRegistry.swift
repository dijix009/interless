import Foundation
import Shared

public struct WorkspaceToolRegistry: Sendable, Equatable {
    public var policy: ToolExecutionPolicy
    public var advertisesTools: Bool
    /// Whether to advertise `recall_history` — only when a session store with
    /// message embeddings is available (else the tool would always return empty).
    public var advertisesRecall: Bool
    /// Whether to advertise the `task` sub-agent tool. False for sub-agents
    /// themselves so a read-only sub-agent cannot spawn another (no recursion).
    public var advertisesSubagent: Bool
    public var generation: Int

    public init(policy: ToolExecutionPolicy = .default, advertisesTools: Bool = true, advertisesRecall: Bool = false, advertisesSubagent: Bool = true, generation: Int = 1) {
        self.policy = policy
        self.advertisesTools = advertisesTools
        self.advertisesRecall = advertisesRecall
        self.advertisesSubagent = advertisesSubagent
        self.generation = generation
    }

    public var definitions: [ToolDefinition] {
        guard advertisesTools else { return [] }
        return makeRegistry(advertisedOnly: true).definitions
    }

    public var scopedRegistry: ScopedToolRegistry {
        makeRegistry(advertisedOnly: false)
    }

    public func request(from call: ModelToolCall) throws -> ToolRequest {
        try request(from: call, generation: generation)
    }

    public func request(from call: ModelToolCall, generation actualGeneration: Int) throws -> ToolRequest {
        try scopedRegistry.request(from: call, generation: actualGeneration)
    }

    private func makeRegistry(advertisedOnly: Bool) -> ScopedToolRegistry {
        var registry = ScopedToolRegistry(generation: generation)
        func include(_ definition: ToolDefinition, scope: ToolScope, advertised: Bool = true, decode: @escaping @Sendable (ModelToolCall) throws -> ToolRequest) {
            guard !advertisedOnly || advertised else { return }
            registry = registry.registering(definition: definition, scope: scope, decode: decode)
        }

        include(readFileDefinition, scope: .workspace) { call in
            .readFile(path: try requiredString("path", in: call))
        }
        include(writeFileDefinition, scope: .workspace, advertised: policy.canRequestWrites) { call in
            .writeFile(
                path: try requiredString("path", in: call),
                contents: try requiredString("contents", in: call))
        }
        include(editFileDefinition, scope: .workspace, advertised: policy.canRequestWrites) { call in
            .editFile(
                path: try requiredString("path", in: call),
                old: try requiredString("old", in: call),
                new: try requiredString("new", in: call),
                replaceAll: try optionalBool("replace_all", in: call) ?? false)
        }
        include(applyPatchDefinition, scope: .workspace, advertised: policy.canRequestWrites) { call in
            .applyPatch(patch: try requiredString("patch", in: call))
        }
        include(grepDefinition, scope: .workspace) { call in
            .grep(
                pattern: try requiredString("pattern", in: call),
                path: try optionalString("path", in: call),
                maxResults: try optionalInt("max_results", in: call))
        }
        include(globDefinition, scope: .workspace) { call in
            .glob(
                pattern: try requiredString("pattern", in: call),
                path: try optionalString("path", in: call),
                maxResults: try optionalInt("max_results", in: call))
        }
        include(todoDefinition, scope: .session) { call in
            .todo(items: try requiredTodoItems("items", in: call))
        }
        include(taskDefinition, scope: .agent, advertised: advertisesSubagent) { call in
            .task(
                prompt: try requiredString("prompt", in: call),
                agent: try optionalString("agent", in: call))
        }
        include(questionDefinition, scope: .session) { call in
            .question(
                prompt: try requiredString("prompt", in: call),
                options: try optionalStringArray("options", in: call) ?? [])
        }
        include(recallHistoryDefinition, scope: .session, advertised: advertisesRecall) { call in
            .recall(
                query: try requiredString("query", in: call),
                limit: try optionalInt("limit", in: call) ?? 5)
        }
        include(gitStatusDefinition, scope: .workspace) { _ in .gitStatus }
        include(gitDiffDefinition, scope: .workspace) { call in
            .gitDiff(path: try optionalString("path", in: call))
        }
        include(runTestsDefinition, scope: .workspace, advertised: policy.canRequestNetwork) { call in
            let arguments = try optionalStringArray("arguments", in: call) ?? []
            try policy.validate(command: ["./scripts/test.sh"] + arguments)
            return .runTests(arguments: arguments)
        }
        include(shellDefinition, scope: .workspace, advertised: policy.canRequestNetwork) { call in
            let command = try requiredStringArray("command", in: call)
            try policy.validate(command: command)
            return .shell(command: command)
        }
        return registry
    }
}

private func requiredString(_ key: String, in call: ModelToolCall) throws -> String {
    guard let value = call.arguments[key] else {
        throw ToolError.invalidToolArguments(tool: call.name, reason: "missing required string '\(key)'")
    }
    guard let string = value.stringValue else {
        throw ToolError.invalidToolArguments(tool: call.name, reason: "'\(key)' must be a string")
    }
    return string
}

private func optionalString(_ key: String, in call: ModelToolCall) throws -> String? {
    guard let value = call.arguments[key], value != .null else { return nil }
    guard let string = value.stringValue else {
        throw ToolError.invalidToolArguments(tool: call.name, reason: "'\(key)' must be a string")
    }
    return string
}

private func requiredStringArray(_ key: String, in call: ModelToolCall) throws -> [String] {
    guard let strings = try optionalStringArray(key, in: call) else {
        throw ToolError.invalidToolArguments(tool: call.name, reason: "missing required string array '\(key)'")
    }
    return strings
}

private func optionalStringArray(_ key: String, in call: ModelToolCall) throws -> [String]? {
    guard let value = call.arguments[key], value != .null else { return nil }
    guard let strings = value.stringArrayValue else {
        throw ToolError.invalidToolArguments(tool: call.name, reason: "'\(key)' must be an array of strings")
    }
    return strings
}

private func optionalInt(_ key: String, in call: ModelToolCall) throws -> Int? {
    guard let value = call.arguments[key], value != .null else { return nil }
    guard case let .int(int) = value else {
        throw ToolError.invalidToolArguments(tool: call.name, reason: "'\(key)' must be an integer")
    }
    return int
}

private func optionalBool(_ key: String, in call: ModelToolCall) throws -> Bool? {
    guard let value = call.arguments[key], value != .null else { return nil }
    guard case let .bool(bool) = value else {
        throw ToolError.invalidToolArguments(tool: call.name, reason: "'\(key)' must be a boolean")
    }
    return bool
}

private func requiredTodoItems(_ key: String, in call: ModelToolCall) throws -> [ToolTodoItem] {
    guard let value = call.arguments[key] else {
        throw ToolError.invalidToolArguments(tool: call.name, reason: "missing required todo array '\(key)'")
    }
    guard case let .array(values) = value else {
        throw ToolError.invalidToolArguments(tool: call.name, reason: "'\(key)' must be an array of todo objects")
    }
    return try values.enumerated().map { index, value in
        guard case let .object(object) = value,
              let title = object["title"]?.stringValue,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolError.invalidToolArguments(tool: call.name, reason: "'\(key)[\(index)]' must include a non-empty title")
        }
        let statusText = object["status"]?.stringValue ?? ToolTodoItem.Status.pending.rawValue
        guard let status = ToolTodoItem.Status(rawValue: statusText) else {
            throw ToolError.invalidToolArguments(tool: call.name, reason: "'\(key)[\(index)].status' is unsupported")
        }
        return ToolTodoItem(title: title, status: status)
    }
}

private let readFileDefinition = ToolDefinition(
    name: "read_file",
    description: "Read a UTF-8 text file inside the workspace.",
    parameters: objectSchema(
        properties: ["path": stringSchema("Workspace-relative file path to read.")],
        required: ["path"]))

private let writeFileDefinition = ToolDefinition(
    name: "write_file",
    description: "Write UTF-8 text to a file inside the workspace when writes are explicitly enabled.",
    parameters: objectSchema(
        properties: [
            "path": stringSchema("Workspace-relative file path to write."),
            "contents": stringSchema("Full UTF-8 file contents."),
        ],
        required: ["path", "contents"]))

private let editFileDefinition = ToolDefinition(
    name: "edit_file",
    description: "Replace text inside a UTF-8 workspace file when writes are explicitly enabled. `old` must match a single, unique span; if it occurs more than once the edit is rejected — add surrounding context to disambiguate, or set `replace_all` to replace every occurrence.",
    parameters: objectSchema(
        properties: [
            "path": stringSchema("Workspace-relative file path to edit."),
            "old": stringSchema("Exact text to replace. Include enough surrounding context to be unique in the file."),
            "new": stringSchema("Replacement text."),
            "replace_all": booleanSchema("Replace every occurrence instead of requiring a unique single match."),
        ],
        required: ["path", "old", "new"]))

private let applyPatchDefinition = ToolDefinition(
    name: "apply_patch",
    description: "Apply a bounded unified diff to workspace files when writes are explicitly enabled. Supports editing, creating (`--- /dev/null`), deleting (`+++ /dev/null`), and git renames (`rename from`/`rename to`). Context lines are matched whitespace- and line-ending-tolerant, and a multi-file patch applies atomically (all files or none).",
    parameters: objectSchema(
        properties: ["patch": stringSchema("Unified diff text.")],
        required: ["patch"]))

private let grepDefinition = ToolDefinition(
    name: "grep",
    description: "Search UTF-8 workspace files for a plain text pattern with bounded results.",
    parameters: objectSchema(
        properties: [
            "pattern": stringSchema("Plain text pattern to search for."),
            "path": stringSchema("Optional workspace-relative file or directory to search."),
            "max_results": integerSchema("Optional maximum result lines."),
        ],
        required: ["pattern"]))

private let globDefinition = ToolDefinition(
    name: "glob",
    description: "Find workspace files matching a glob pattern with bounded results.",
    parameters: objectSchema(
        properties: [
            "pattern": stringSchema("Glob pattern such as '*.swift' or 'Sources/**/*.swift'."),
            "path": stringSchema("Optional workspace-relative directory to search."),
            "max_results": integerSchema("Optional maximum matching paths."),
        ],
        required: ["pattern"]))

private let todoDefinition = ToolDefinition(
    name: "todo",
    description: "Publish the current task todo list for the session.",
    parameters: objectSchema(
        properties: [
            "items": arraySchema(
                items: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "title": stringSchema("Todo title."),
                        "status": stringSchema("pending, inProgress, or completed."),
                    ]),
                    "required": .array([.string("title")]),
                    "additionalProperties": .bool(false),
                ]),
                description: "Todo objects with title and optional status."),
        ],
        required: ["items"]))

private let taskDefinition = ToolDefinition(
    name: "task",
    description: "Delegate a focused sub-task to a read-only sub-agent that investigates the workspace in its own context and returns a concise summary. Use `explore` to locate/understand code and `review` to critique a change; the sub-agent cannot modify files. Prefer this for open-ended search or review so your own context stays lean — then act on the summary yourself.",
    parameters: objectSchema(
        properties: [
            "prompt": stringSchema("What the sub-agent should investigate or review."),
            "agent": stringSchema("Sub-agent type: 'explore' (default) or 'review'."),
        ],
        required: ["prompt"]))

private let questionDefinition = ToolDefinition(
    name: "question",
    description: "Ask the user a short clarification question through the native UI.",
    parameters: objectSchema(
        properties: [
            "prompt": stringSchema("Question text."),
            "options": arraySchema(
                items: .object(["type": .string("string")]),
                description: "Optional short answer choices."),
        ],
        required: ["prompt"]))

private let recallHistoryDefinition = ToolDefinition(
    name: "recall_history",
    description: "Search the FULL earlier conversation (beyond what's already in context) for "
        + "messages relevant to a topic, and get the matching turns back. Use when you need a "
        + "detail, decision, or value from earlier that you don't currently see. If results "
        + "conflict, the most recent is authoritative.",
    parameters: objectSchema(
        properties: [
            "query": stringSchema("What to look for in earlier conversation."),
            "limit": integerSchema("Optional max number of past turns to return (default 5, max 10)."),
        ],
        required: ["query"]))

private let gitStatusDefinition = ToolDefinition(
    name: "git_status",
    description: "Run git status --short in the workspace.",
    parameters: objectSchema(properties: [:], required: []))

private let gitDiffDefinition = ToolDefinition(
    name: "git_diff",
    description: "Run git diff for the whole workspace or one existing workspace file.",
    parameters: objectSchema(
        properties: ["path": stringSchema("Optional workspace-relative file path.")],
        required: []))

private let runTestsDefinition = ToolDefinition(
    name: "run_tests",
    description: "Run ./scripts/test.sh with optional safe arguments.",
    parameters: objectSchema(
        properties: [
            "arguments": arraySchema(
                items: .object(["type": .string("string")]),
                description: "Optional argument list for the test script."),
        ],
        required: []))

private let shellDefinition = ToolDefinition(
    name: "shell",
    description: "Run an allowlisted command inside the workspace.",
    parameters: objectSchema(
        properties: [
            "command": arraySchema(
                items: .object(["type": .string("string")]),
                description: "Command and arguments; must match the execution policy allowlist."),
        ],
        required: ["command"]))

private func objectSchema(properties: [String: JSONValue], required: [String]) -> JSONValue {
    .object([
        "type": .string("object"),
        "properties": .object(properties),
        "required": .array(required.map(JSONValue.string)),
        "additionalProperties": .bool(false),
    ])
}

private func stringSchema(_ description: String) -> JSONValue {
    .object([
        "type": .string("string"),
        "description": .string(description),
    ])
}

private func arraySchema(items: JSONValue, description: String) -> JSONValue {
    .object([
        "type": .string("array"),
        "items": items,
        "description": .string(description),
    ])
}

private func integerSchema(_ description: String) -> JSONValue {
    .object([
        "type": .string("integer"),
        "description": .string(description),
    ])
}

private func booleanSchema(_ description: String) -> JSONValue {
    .object([
        "type": .string("boolean"),
        "description": .string(description),
    ])
}
