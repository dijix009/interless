import Foundation
import Shared

public struct ToolTodoItem: Sendable, Equatable, Codable, Hashable {
    public enum Status: String, Sendable, Equatable, Codable, Hashable, CaseIterable {
        case pending
        case inProgress
        case completed
    }

    public var title: String
    public var status: Status

    public init(title: String, status: Status = .pending) {
        self.title = title
        self.status = status
    }
}

public enum ToolRequest: Sendable, Equatable, Codable {
    case readFile(path: String)
    case writeFile(path: String, contents: String)
    case editFile(path: String, old: String, new: String, replaceAll: Bool = false)
    case applyPatch(patch: String)
    case grep(pattern: String, path: String? = nil, maxResults: Int? = nil)
    case glob(pattern: String, path: String? = nil, maxResults: Int? = nil)
    case todo(items: [ToolTodoItem])
    case task(prompt: String)
    case question(prompt: String, options: [String] = [])
    case gitStatus
    case gitDiff(path: String?)
    case runTests(arguments: [String] = [])
    case shell(command: [String])

    public var displayName: String {
        switch self {
        case .readFile: return "readFile"
        case .writeFile: return "writeFile"
        case .editFile: return "editFile"
        case .applyPatch: return "applyPatch"
        case .grep: return "grep"
        case .glob: return "glob"
        case .todo: return "todo"
        case .task: return "task"
        case .question: return "question"
        case .gitStatus: return "gitStatus"
        case .gitDiff: return "gitDiff"
        case .runTests: return "runTests"
        case .shell: return "shell"
        }
    }
}

public struct ToolFileChange: Sendable, Equatable, Codable, Hashable {
    public enum Operation: String, Sendable, Equatable, Codable, Hashable, CaseIterable {
        case created
        case edited
    }

    public var path: String
    public var operation: Operation
    public var snapshotID: String?

    public init(path: String, operation: Operation, snapshotID: String? = nil) {
        self.path = path
        self.operation = operation
        self.snapshotID = snapshotID
    }
}

public struct ToolResult: Sendable, Equatable, Codable {
    public var request: ToolRequest
    public var exitCode: Int32?
    public var stdout: String
    public var stderr: String
    public var didWrite: Bool
    public var timedOut: Bool
    public var snapshotID: String?
    public var outputRef: ManagedToolOutputRef?
    public var fileChanges: [ToolFileChange]

    public init(
        request: ToolRequest,
        exitCode: Int32? = nil,
        stdout: String = "",
        stderr: String = "",
        didWrite: Bool = false,
        timedOut: Bool = false,
        snapshotID: String? = nil,
        outputRef: ManagedToolOutputRef? = nil,
        fileChanges: [ToolFileChange] = []
    ) {
        self.request = request
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.didWrite = didWrite
        self.timedOut = timedOut
        self.snapshotID = snapshotID
        self.outputRef = outputRef
        self.fileChanges = fileChanges
    }

    private enum CodingKeys: String, CodingKey {
        case request, exitCode, stdout, stderr, didWrite, timedOut, snapshotID, outputRef, fileChanges
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        request = try container.decode(ToolRequest.self, forKey: .request)
        exitCode = try container.decodeIfPresent(Int32.self, forKey: .exitCode)
        stdout = try container.decode(String.self, forKey: .stdout)
        stderr = try container.decode(String.self, forKey: .stderr)
        didWrite = try container.decode(Bool.self, forKey: .didWrite)
        timedOut = try container.decode(Bool.self, forKey: .timedOut)
        snapshotID = try container.decodeIfPresent(String.self, forKey: .snapshotID)
        outputRef = try container.decodeIfPresent(ManagedToolOutputRef.self, forKey: .outputRef)
        fileChanges = try container.decodeIfPresent([ToolFileChange].self, forKey: .fileChanges) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(request, forKey: .request)
        try container.encodeIfPresent(exitCode, forKey: .exitCode)
        try container.encode(stdout, forKey: .stdout)
        try container.encode(stderr, forKey: .stderr)
        try container.encode(didWrite, forKey: .didWrite)
        try container.encode(timedOut, forKey: .timedOut)
        try container.encodeIfPresent(snapshotID, forKey: .snapshotID)
        try container.encodeIfPresent(outputRef, forKey: .outputRef)
        try container.encode(fileChanges, forKey: .fileChanges)
    }
}

public enum ToolError: Error, Sendable, Equatable {
    case invalidCommand
    case commandDenied([String])
    case networkDisabled([String])
    case unknownTool(String)
    case invalidToolArguments(tool: String, reason: String)
    case pathOutsideWorkspace(String)
    case pathNotFound(String)
    case writeDenied
    case permissionDenied(String)
    case settlementUnavailable(String)
    case writeTooLarge(bytes: Int, limit: Int)
    case editTargetNotFound(path: String)
    case patchRejected(String)
    case staleToolCall(name: String, expectedGeneration: Int, actualGeneration: Int)
    case timedOut(command: [String], seconds: Double)
    case launchFailed(command: [String], reason: String)
    case cancelled
}

public struct ToolCommandPattern: Sendable, Equatable, Codable {
    public var executable: String
    public var argumentsPrefix: [String]
    /// True for commands that may execute workspace-controlled code or otherwise
    /// use ambient process networking. The app does not currently launch tools
    /// inside an OS network sandbox, so these commands require explicit trust.
    public var requiresNetworkPermission: Bool

    public init(
        executable: String,
        argumentsPrefix: [String] = [],
        requiresNetworkPermission: Bool = true
    ) {
        self.executable = executable
        self.argumentsPrefix = argumentsPrefix
        self.requiresNetworkPermission = requiresNetworkPermission
    }

    private enum CodingKeys: String, CodingKey {
        case executable
        case argumentsPrefix
        case requiresNetworkPermission
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.executable = try container.decode(String.self, forKey: .executable)
        self.argumentsPrefix = try container.decodeIfPresent([String].self, forKey: .argumentsPrefix) ?? []
        self.requiresNetworkPermission = try container.decodeIfPresent(
            Bool.self,
            forKey: .requiresNetworkPermission
        ) ?? true
    }

    public func matches(_ command: [String]) -> Bool {
        guard command.first == executable else { return false }
        let arguments = Array(command.dropFirst())
        guard arguments.count >= argumentsPrefix.count else { return false }
        return Array(arguments.prefix(argumentsPrefix.count)) == argumentsPrefix
    }
}

public struct ToolExecutionPolicy: Sendable, Equatable, Codable {
    public var allowsWrites: Bool
    public var networkEnabled: Bool
    public var writePermission: ToolPermissionEffect
    public var networkPermission: ToolPermissionEffect
    public var timeoutSeconds: Double
    public var maxOutputBytes: Int
    public var maxWriteBytes: Int
    public var allowedCommands: [ToolCommandPattern]

    public init(
        allowsWrites: Bool = false,
        networkEnabled: Bool = false,
        writePermission: ToolPermissionEffect? = nil,
        networkPermission: ToolPermissionEffect? = nil,
        timeoutSeconds: Double = 30,
        maxOutputBytes: Int = 64 * 1024,
        maxWriteBytes: Int = 1 * 1024 * 1024,
        allowedCommands: [ToolCommandPattern] = Self.defaultAllowedCommands
    ) {
        self.allowsWrites = allowsWrites
        self.networkEnabled = networkEnabled
        self.writePermission = writePermission ?? (allowsWrites ? .allow : .deny)
        self.networkPermission = networkPermission ?? (networkEnabled ? .allow : .deny)
        self.timeoutSeconds = timeoutSeconds
        self.maxOutputBytes = max(0, maxOutputBytes)
        self.maxWriteBytes = max(0, maxWriteBytes)
        self.allowedCommands = allowedCommands
    }

    public var canRequestWrites: Bool {
        writePermission != .deny
    }

    public var canRequestNetwork: Bool {
        networkPermission != .deny
    }

    private enum CodingKeys: String, CodingKey {
        case allowsWrites
        case networkEnabled
        case writePermission
        case networkPermission
        case timeoutSeconds
        case maxOutputBytes
        case maxWriteBytes
        case allowedCommands
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            allowsWrites: try container.decodeIfPresent(Bool.self, forKey: .allowsWrites) ?? false,
            networkEnabled: try container.decodeIfPresent(Bool.self, forKey: .networkEnabled) ?? false,
            writePermission: try container.decodeIfPresent(ToolPermissionEffect.self, forKey: .writePermission),
            networkPermission: try container.decodeIfPresent(ToolPermissionEffect.self, forKey: .networkPermission),
            timeoutSeconds: try container.decodeIfPresent(Double.self, forKey: .timeoutSeconds) ?? 30,
            maxOutputBytes: try container.decodeIfPresent(Int.self, forKey: .maxOutputBytes) ?? 64 * 1024,
            maxWriteBytes: try container.decodeIfPresent(Int.self, forKey: .maxWriteBytes) ?? 1 * 1024 * 1024,
            allowedCommands: try container.decodeIfPresent([ToolCommandPattern].self, forKey: .allowedCommands) ?? Self.defaultAllowedCommands)
    }

    public init(
        allowsWrites: Bool = false,
        resourceBudget: ResourceBudget,
        networkEnabled: Bool = false,
        writePermission: ToolPermissionEffect? = nil,
        networkPermission: ToolPermissionEffect? = nil,
        timeoutSeconds: Double = 30,
        allowedCommands: [ToolCommandPattern] = Self.defaultAllowedCommands
    ) {
        self.init(
            allowsWrites: allowsWrites,
            networkEnabled: networkEnabled,
            writePermission: writePermission,
            networkPermission: networkPermission,
            timeoutSeconds: timeoutSeconds,
            maxOutputBytes: resourceBudget.maxToolOutputBytes,
            maxWriteBytes: resourceBudget.maxIndexedFileSizeBytes,
            allowedCommands: allowedCommands)
    }

    public static let defaultAllowedCommands: [ToolCommandPattern] = [
        ToolCommandPattern(executable: "swift", argumentsPrefix: ["test"]),
        ToolCommandPattern(executable: "swift", argumentsPrefix: ["build"]),
        ToolCommandPattern(executable: "git", argumentsPrefix: ["status"], requiresNetworkPermission: false),
        ToolCommandPattern(executable: "git", argumentsPrefix: ["diff"], requiresNetworkPermission: false),
        ToolCommandPattern(executable: "./scripts/test.sh"),
    ]

    public static let `default` = ToolExecutionPolicy()

    public func allows(command: [String]) -> Bool {
        (try? validate(command: command)) != nil
    }

    public func validate(command: [String]) throws {
        guard let pattern = matchingPattern(for: command) else { throw ToolError.commandDenied(command) }
        guard canRequestNetwork || !pattern.requiresNetworkPermission else {
            throw ToolError.networkDisabled(command)
        }
    }

    public func matchingPattern(for command: [String]) -> ToolCommandPattern? {
        allowedCommands.first { $0.matches(command) }
    }
}

public struct ToolPermissionRequest: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var request: ToolRequest
    public var title: String
    public var message: String

    public init(
        id: UUID = UUID(),
        request: ToolRequest,
        title: String,
        message: String
    ) {
        self.id = id
        self.request = request
        self.title = title
        self.message = message
    }
}

public enum ToolPermissionResolution: Sendable, Equatable {
    case allowOnce
    case deny
}

public typealias ToolPermissionAuthorizer = @Sendable (ToolPermissionRequest) async -> ToolPermissionResolution

public struct ToolQuestionRequest: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var prompt: String
    public var options: [String]

    public init(id: UUID = UUID(), prompt: String, options: [String] = []) {
        self.id = id
        self.prompt = prompt
        self.options = options
    }
}

public struct ToolQuestionResponse: Sendable, Equatable {
    public var answer: String

    public init(answer: String) {
        self.answer = answer
    }
}

public struct ToolTaskSettlement: Sendable, Equatable {
    public var jobID: UUID
    public var status: String
    public var message: String

    public init(jobID: UUID = UUID(), status: String, message: String) {
        self.jobID = jobID
        self.status = status
        self.message = message
    }
}

public struct ToolSettlementHandlers: Sendable {
    public var updateTodos: (@Sendable ([ToolTodoItem]) async throws -> String)?
    public var askQuestion: (@Sendable (ToolQuestionRequest) async throws -> ToolQuestionResponse)?
    public var scheduleTask: (@Sendable (String) async throws -> ToolTaskSettlement)?

    public init(
        updateTodos: (@Sendable ([ToolTodoItem]) async throws -> String)? = nil,
        askQuestion: (@Sendable (ToolQuestionRequest) async throws -> ToolQuestionResponse)? = nil,
        scheduleTask: (@Sendable (String) async throws -> ToolTaskSettlement)? = nil
    ) {
        self.updateTodos = updateTodos
        self.askQuestion = askQuestion
        self.scheduleTask = scheduleTask
    }

    public static let empty = ToolSettlementHandlers()
}
