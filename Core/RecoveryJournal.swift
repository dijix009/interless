import Foundation

public enum RecoveryJournalError: Error, Sendable, Equatable {
    case recordNotFound(UUID)
}

public enum RecoveryJournalRecordKind: String, Sendable, Codable, Equatable, CaseIterable {
    case operation
    case failure
}

public enum RecoveryOperationKind: String, Sendable, Codable, Equatable, CaseIterable {
    case workspaceOpen
    case indexing
    case search
    case filePreview
    case gitRefresh
    case chat
    case modelLoad
    case modelUnload
    case toolExecution
    case patchApply
}

public enum RecoveryOperationStatus: String, Sendable, Codable, Equatable, CaseIterable {
    case active
    case completed
    case failed
    case cancelled
    case unfinishedPreviousRun
    case acknowledged
}

public enum RecoveryActionKind: String, Sendable, Codable, Equatable, CaseIterable {
    case retryWorkspaceOpen
    case retryIndexing
    case retrySearch
    case retryFilePreview
    case retryGitRefresh
    case retryModelLoad
    case reviewPatch
    case openHealth
    case dismiss
}

public struct RecoveryOperationToken: Sendable, Codable, Equatable, Hashable {
    public var id: UUID

    public init(id: UUID) {
        self.id = id
    }
}

public struct RecoveryJournalRecord: Identifiable, Sendable, Codable, Equatable {
    public var id: UUID
    public var appRunID: UUID
    public var recordKind: RecoveryJournalRecordKind
    public var operationKind: RecoveryOperationKind
    public var status: RecoveryOperationStatus
    public var title: String
    public var message: String?
    public var metadata: [String: String]
    public var startedAt: Date
    public var endedAt: Date?
    public var actionKind: RecoveryActionKind?
    public var isAcknowledged: Bool

    public init(
        id: UUID = UUID(),
        appRunID: UUID,
        recordKind: RecoveryJournalRecordKind,
        operationKind: RecoveryOperationKind,
        status: RecoveryOperationStatus,
        title: String,
        message: String? = nil,
        metadata: [String: String] = [:],
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        actionKind: RecoveryActionKind? = nil,
        isAcknowledged: Bool = false
    ) {
        self.id = id
        self.appRunID = appRunID
        self.recordKind = recordKind
        self.operationKind = operationKind
        self.status = status
        self.title = title
        self.message = message
        self.metadata = metadata
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.actionKind = actionKind
        self.isAcknowledged = isAcknowledged
    }
}

public struct RecoveryJournalSnapshot: Sendable, Codable, Equatable {
    public var records: [RecoveryJournalRecord]
    public var recoveryItems: [RecoveryJournalRecord]
    public var corruptionArchiveURL: URL?

    public init(
        records: [RecoveryJournalRecord],
        recoveryItems: [RecoveryJournalRecord],
        corruptionArchiveURL: URL? = nil
    ) {
        self.records = records
        self.recoveryItems = recoveryItems
        self.corruptionArchiveURL = corruptionArchiveURL
    }
}

public actor RecoveryJournal {
    private struct JournalFile: Codable {
        var records: [RecoveryJournalRecord]
    }

    private static let allowedMetadataKeys: Set<String> = [
        "workspacePath",
        "relativePath",
        "modelRole",
        "modelID",
        "operation",
        "action",
        "tool",
        "exitCode",
    ]

    private let fileURL: URL
    private let retentionLimit: Int
    private let appRunID: UUID
    private var records: [RecoveryJournalRecord]?
    private var corruptionArchiveURL: URL?

    public init(fileURL: URL, retentionLimit: Int = 500, appRunID: UUID = UUID()) {
        self.fileURL = fileURL
        self.retentionLimit = max(1, retentionLimit)
        self.appRunID = appRunID
    }

    public static func live() -> RecoveryJournal {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return RecoveryJournal(fileURL: base.appendingPathComponent("Interless/recovery-journal.json"))
    }

    @discardableResult
    public func beginOperation(
        kind: RecoveryOperationKind,
        title: String,
        metadata: [String: String] = [:]
    ) async throws -> RecoveryOperationToken {
        try loadIfNeeded()
        let record = RecoveryJournalRecord(
            appRunID: appRunID,
            recordKind: .operation,
            operationKind: kind,
            status: .active,
            title: sanitize(title),
            metadata: sanitize(metadata),
            actionKind: actionKind(for: kind))
        records?.append(record)
        prune()
        try persist()
        return RecoveryOperationToken(id: record.id)
    }

    public func finishOperation(
        _ token: RecoveryOperationToken,
        status: RecoveryOperationStatus,
        message: String? = nil
    ) async throws {
        try loadIfNeeded()
        guard let index = records?.firstIndex(where: { $0.id == token.id }) else {
            throw RecoveryJournalError.recordNotFound(token.id)
        }
        var record = records?[index]
        record?.status = status
        record?.endedAt = Date()
        record?.message = message.map(sanitize)
        if status == .completed || status == .cancelled {
            record?.isAcknowledged = true
        }
        if let record {
            records?[index] = record
        }
        try persist()
    }

    @discardableResult
    public func recordFailure(
        kind: RecoveryOperationKind,
        title: String,
        message: String,
        metadata: [String: String] = [:]
    ) async throws -> RecoveryJournalRecord {
        try loadIfNeeded()
        let record = RecoveryJournalRecord(
            appRunID: appRunID,
            recordKind: .failure,
            operationKind: kind,
            status: .failed,
            title: sanitize(title),
            message: sanitize(message),
            metadata: sanitize(metadata),
            endedAt: Date(),
            actionKind: actionKind(for: kind))
        records?.append(record)
        prune()
        try persist()
        return record
    }

    public func recoverUnfinishedOperations() async throws -> [RecoveryJournalRecord] {
        try loadIfNeeded()
        var changed = false
        let now = Date()
        for index in records?.indices ?? Array<RecoveryJournalRecord>().indices {
            guard var record = records?[index],
                  record.status == .active,
                  record.appRunID != appRunID else {
                continue
            }
            record.status = .unfinishedPreviousRun
            record.endedAt = now
            records?[index] = record
            changed = true
        }
        if changed {
            try persist()
        }
        return recoveryItems(from: records ?? [])
    }

    public func snapshot(limit: Int? = nil) async throws -> RecoveryJournalSnapshot {
        try loadIfNeeded()
        let maxCount = max(0, limit ?? records?.count ?? 0)
        let currentRecords = Array((records ?? []).suffix(maxCount))
        return RecoveryJournalSnapshot(
            records: currentRecords,
            recoveryItems: recoveryItems(from: currentRecords),
            corruptionArchiveURL: corruptionArchiveURL)
    }

    public func acknowledge(_ id: UUID) async throws {
        try loadIfNeeded()
        guard let index = records?.firstIndex(where: { $0.id == id }) else {
            throw RecoveryJournalError.recordNotFound(id)
        }
        guard var record = records?[index] else { return }
        record.isAcknowledged = true
        record.status = .acknowledged
        if record.endedAt == nil {
            record.endedAt = Date()
        }
        records?[index] = record
        try persist()
    }

    public func clearAcknowledged() async throws {
        try loadIfNeeded()
        records = (records ?? []).filter { !$0.isAcknowledged && $0.status != .acknowledged }
        try persist()
    }

    private func loadIfNeeded() throws {
        guard records == nil else { return }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            records = []
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            records = try JSONDecoder.recoveryJournalDecoder.decode(JournalFile.self, from: data).records
        } catch {
            let archiveURL = corruptArchiveURL()
            try? FileManager.default.createDirectory(
                at: archiveURL.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try? FileManager.default.moveItem(at: fileURL, to: archiveURL)
            corruptionArchiveURL = archiveURL
            records = []
            try persist()
        }
    }

    private func persist() throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let data = try JSONEncoder.recoveryJournalEncoder.encode(JournalFile(records: records ?? []))
        try data.write(to: fileURL, options: [.atomic])
    }

    private func prune() {
        guard let count = records?.count, count > retentionLimit else { return }
        records?.removeFirst(count - retentionLimit)
    }

    private func recoveryItems(from records: [RecoveryJournalRecord]) -> [RecoveryJournalRecord] {
        records.filter { record in
            !record.isAcknowledged && (record.status == .unfinishedPreviousRun || record.status == .failed)
        }
    }

    private func sanitize(_ metadata: [String: String]) -> [String: String] {
        metadata.reduce(into: [:]) { result, pair in
            guard Self.allowedMetadataKeys.contains(pair.key) else { return }
            result[pair.key] = sanitize(pair.value)
        }
    }

    private func sanitize(_ value: String) -> String {
        let redactedKeys = ["token", "secret", "password", "credential", "authorization"]
        let lowercased = value.lowercased()
        if redactedKeys.contains(where: { lowercased.contains($0) }) {
            return "[redacted]"
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 240 else { return trimmed }
        return "\(trimmed.prefix(240))..."
    }

    private func actionKind(for kind: RecoveryOperationKind) -> RecoveryActionKind {
        switch kind {
        case .workspaceOpen: return .retryWorkspaceOpen
        case .indexing: return .retryIndexing
        case .search: return .retrySearch
        case .filePreview: return .retryFilePreview
        case .gitRefresh: return .retryGitRefresh
        case .chat: return .openHealth
        case .modelLoad: return .retryModelLoad
        case .modelUnload: return .openHealth
        case .toolExecution: return .openHealth
        case .patchApply: return .reviewPatch
        }
    }

    private func corruptArchiveURL() -> URL {
        let stamp = ISO8601DateFormatter.recoveryJournalFormatter.string(from: Date())
        let directory = fileURL.deletingLastPathComponent()
        let base = fileURL.deletingPathExtension().lastPathComponent
        return directory.appendingPathComponent("\(base).corrupt-\(stamp).json")
    }
}

private extension JSONEncoder {
    static var recoveryJournalEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var recoveryJournalDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension ISO8601DateFormatter {
    static var recoveryJournalFormatter: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        return formatter
    }
}
