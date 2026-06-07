import CryptoKit
import Foundation
import Shared

public struct DiagnosticsExportRequest: Sendable {
    public var appName: String
    public var appVersion: String
    public var buildIdentifier: String
    public var generatedAt: Date
    public var workspacePath: String?
    public var includeFullPaths: Bool
    public var maxRecords: Int
    public var maxMessageLength: Int
    public var settings: [String: String]
    public var events: [AppEvent]
    public var taskSnapshot: TaskSchedulerSnapshot
    public var metricSummaries: [MetricSummary]
    public var metricSamples: [MetricSample]
    public var memoryPolicyState: MemoryPolicyState?
    public var recoverySnapshot: RecoveryJournalSnapshot?
    public var durableEventCursors: [DurableEventCursor]
    public var sessionEvents: [SessionEvent]

    public init(
        appName: String = "Interless",
        appVersion: String = "development",
        buildIdentifier: String = "local",
        generatedAt: Date = Date(),
        workspacePath: String? = nil,
        includeFullPaths: Bool = false,
        maxRecords: Int = 100,
        maxMessageLength: Int = 240,
        settings: [String: String] = [:],
        events: [AppEvent] = [],
        taskSnapshot: TaskSchedulerSnapshot = TaskSchedulerSnapshot(active: [], recent: []),
        metricSummaries: [MetricSummary] = [],
        metricSamples: [MetricSample] = [],
        memoryPolicyState: MemoryPolicyState? = nil,
        recoverySnapshot: RecoveryJournalSnapshot? = nil,
        durableEventCursors: [DurableEventCursor] = [],
        sessionEvents: [SessionEvent] = []
    ) {
        self.appName = appName
        self.appVersion = appVersion
        self.buildIdentifier = buildIdentifier
        self.generatedAt = generatedAt
        self.workspacePath = workspacePath
        self.includeFullPaths = includeFullPaths
        self.maxRecords = max(0, maxRecords)
        self.maxMessageLength = max(32, maxMessageLength)
        self.settings = settings
        self.events = events
        self.taskSnapshot = taskSnapshot
        self.metricSummaries = metricSummaries
        self.metricSamples = metricSamples
        self.memoryPolicyState = memoryPolicyState
        self.recoverySnapshot = recoverySnapshot
        self.durableEventCursors = durableEventCursors
        self.sessionEvents = sessionEvents
    }
}

public struct DiagnosticsBundle: Sendable, Codable, Equatable {
    public var schemaVersion: Int
    public var generatedAt: Date
    public var app: DiagnosticsAppInfo
    public var system: DiagnosticsSystemInfo
    public var workspace: DiagnosticsWorkspaceInfo?
    public var settings: [String: String]
    public var events: [DiagnosticsEvent]
    public var tasks: DiagnosticsTaskSnapshot
    public var metrics: DiagnosticsMetrics
    public var memoryPolicy: DiagnosticsMemoryPolicy?
    public var recovery: DiagnosticsRecovery?
    public var observability: DiagnosticsObservability
    public var redaction: DiagnosticsRedactionInfo
}

public struct DiagnosticsAppInfo: Sendable, Codable, Equatable {
    public var name: String
    public var version: String
    public var buildIdentifier: String
}

public struct DiagnosticsSystemInfo: Sendable, Codable, Equatable {
    public var osVersion: String
    public var architecture: String
    public var physicalMemoryBytes: Int
    public var processorCount: Int
}

public struct DiagnosticsWorkspaceInfo: Sendable, Codable, Equatable {
    public var basename: String
    public var pathHash: String
    public var fullPath: String?
}

public struct DiagnosticsEvent: Sendable, Codable, Equatable {
    public var id: UUID
    public var date: Date
    public var kind: String
    public var severity: String
    public var message: String
    public var metadata: [String: String]
}

public struct DiagnosticsTaskSnapshot: Sendable, Codable, Equatable {
    public var active: [TrackedTaskRecord]
    public var recent: [TrackedTaskRecord]
}

public struct DiagnosticsMetrics: Sendable, Codable, Equatable {
    public var summaries: [MetricSummary]
    public var samples: [MetricSample]
}

public struct DiagnosticsMemoryPolicy: Sendable, Codable, Equatable {
    public var requestedProfile: String
    public var resolvedProfile: String
    public var usedFraction: Double
    public var activeActions: [String]
    public var evaluatedAt: Date
    public var processFootprintBytes: Int
    public var totalUnifiedBytes: Int
    public var gpuActiveBytes: Int
    public var gpuCacheBytes: Int
}

public struct DiagnosticsRecovery: Sendable, Codable, Equatable {
    public var records: [RecoveryJournalRecord]
    public var recoveryItems: [RecoveryJournalRecord]
    public var corruptionArchive: String?
}

public struct DiagnosticsObservability: Sendable, Codable, Equatable {
    public var durableCursors: [DiagnosticsDurableCursor]
    public var sessionEvents: [DiagnosticsSessionEvent]
    public var backgroundJobs: DiagnosticsBackgroundJobLifecycle
}

public struct DiagnosticsDurableCursor: Sendable, Codable, Equatable {
    public var streamID: String
    public var sequence: Int64
    public var updatedAt: Date
}

public struct DiagnosticsSessionEvent: Sendable, Codable, Equatable {
    public var sessionID: UUID
    public var sequence: Int64
    public var kind: String
    public var messageID: UUID?
    public var payload: [String: String]
    public var createdAt: Date
}

public struct DiagnosticsBackgroundJobLifecycle: Sendable, Codable, Equatable {
    public var activeCount: Int
    public var recentCount: Int
    public var runningCount: Int
    public var completedCount: Int
    public var failedCount: Int
    public var cancelledCount: Int
}

public struct DiagnosticsRedactionInfo: Sendable, Codable, Equatable {
    public var fullPathsIncluded: Bool
    public var maxMessageLength: Int
    public var rules: [String]
}

public struct DiagnosticsExporter: Sendable {
    public init() {}

    public func export(request: DiagnosticsExportRequest) async throws -> DiagnosticsBundle {
        let redactor = DiagnosticsRedactor(
            includeFullPaths: request.includeFullPaths,
            maxMessageLength: request.maxMessageLength)
        return DiagnosticsBundle(
            schemaVersion: 2,
            generatedAt: request.generatedAt,
            app: DiagnosticsAppInfo(
                name: redactor.sanitize(request.appName),
                version: redactor.sanitize(request.appVersion),
                buildIdentifier: redactor.sanitize(request.buildIdentifier)),
            system: DiagnosticsSystemInfo(
                osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                architecture: Self.architecture,
                physicalMemoryBytes: Int(ProcessInfo.processInfo.physicalMemory),
                processorCount: ProcessInfo.processInfo.processorCount),
            workspace: request.workspacePath.map { redactor.workspaceInfo(for: $0) },
            settings: redactor.sanitize(metadata: request.settings),
            events: request.events.suffix(request.maxRecords).map { redactor.event($0) },
            tasks: DiagnosticsTaskSnapshot(
                active: request.taskSnapshot.active.suffix(request.maxRecords).map { redactor.task($0) },
                recent: request.taskSnapshot.recent.suffix(request.maxRecords).map { redactor.task($0) }),
            metrics: DiagnosticsMetrics(
                summaries: request.metricSummaries,
                samples: Array(request.metricSamples.suffix(request.maxRecords))),
            memoryPolicy: request.memoryPolicyState.map(redactor.memoryPolicy),
            recovery: request.recoverySnapshot.map { redactor.recovery($0, limit: request.maxRecords) },
            observability: DiagnosticsObservability(
                durableCursors: request.durableEventCursors
                    .suffix(request.maxRecords)
                    .map(redactor.durableCursor),
                sessionEvents: request.sessionEvents
                    .suffix(request.maxRecords)
                    .map(redactor.sessionEvent),
                backgroundJobs: redactor.backgroundJobs(request.taskSnapshot)),
            redaction: DiagnosticsRedactionInfo(
                fullPathsIncluded: request.includeFullPaths,
                maxMessageLength: request.maxMessageLength,
                rules: [
                    "absolute paths are hashed unless full paths are explicitly requested",
                    "prompt/source/body/content/preview/stdout/stderr metadata is redacted",
                    "secret/token/password/credential/authorization values are redacted",
                    "messages are truncated to the configured length",
                ]))
    }

    public func write(bundle: DiagnosticsBundle, to url: URL) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(bundle)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic])
    }

    private static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }
}

public struct DiagnosticsRedactor: Sendable {
    public var includeFullPaths: Bool
    public var maxMessageLength: Int

    public init(includeFullPaths: Bool = false, maxMessageLength: Int = 240) {
        self.includeFullPaths = includeFullPaths
        self.maxMessageLength = max(32, maxMessageLength)
    }

    public func event(_ event: AppEvent) -> DiagnosticsEvent {
        DiagnosticsEvent(
            id: event.id,
            date: event.date,
            kind: event.kind.rawValue,
            severity: event.severity.rawValue,
            message: sanitize(event.message),
            metadata: sanitize(metadata: event.metadata))
    }

    public func task(_ task: TrackedTaskRecord) -> TrackedTaskRecord {
        var copy = task
        copy.title = sanitize(task.title)
        copy.message = task.message.map(sanitize)
        return copy
    }

    public func memoryPolicy(_ state: MemoryPolicyState) -> DiagnosticsMemoryPolicy {
        DiagnosticsMemoryPolicy(
            requestedProfile: state.requestedProfile.rawValue,
            resolvedProfile: state.resolvedProfile.rawValue,
            usedFraction: state.usedFraction,
            activeActions: state.activeActions,
            evaluatedAt: state.evaluatedAt,
            processFootprintBytes: state.snapshot?.footprint.processFootprintBytes ?? 0,
            totalUnifiedBytes: state.snapshot?.footprint.totalUnifiedBytes ?? 0,
            gpuActiveBytes: state.snapshot?.gpu.activeBytes ?? 0,
            gpuCacheBytes: state.snapshot?.gpu.cacheBytes ?? 0)
    }

    public func recovery(_ snapshot: RecoveryJournalSnapshot, limit: Int) -> DiagnosticsRecovery {
        DiagnosticsRecovery(
            records: snapshot.records.suffix(max(0, limit)).map(recoveryRecord),
            recoveryItems: snapshot.recoveryItems.suffix(max(0, limit)).map(recoveryRecord),
            corruptionArchive: snapshot.corruptionArchiveURL.map { sanitize($0.path) })
    }

    public func durableCursor(_ cursor: DurableEventCursor) -> DiagnosticsDurableCursor {
        DiagnosticsDurableCursor(
            streamID: sanitize(cursor.streamID),
            sequence: cursor.sequence,
            updatedAt: cursor.updatedAt)
    }

    public func sessionEvent(_ event: SessionEvent) -> DiagnosticsSessionEvent {
        DiagnosticsSessionEvent(
            sessionID: event.sessionID,
            sequence: event.sequence,
            kind: event.kind.rawValue,
            messageID: event.messageID,
            payload: sanitize(metadata: event.payload),
            createdAt: event.createdAt)
    }

    public func backgroundJobs(_ snapshot: TaskSchedulerSnapshot) -> DiagnosticsBackgroundJobLifecycle {
        let all = snapshot.active + snapshot.recent
        return DiagnosticsBackgroundJobLifecycle(
            activeCount: snapshot.active.count,
            recentCount: snapshot.recent.count,
            runningCount: all.filter { $0.status == .running }.count,
            completedCount: all.filter { $0.status == .completed }.count,
            failedCount: all.filter { $0.status == .failed }.count,
            cancelledCount: all.filter { $0.status == .cancelled }.count)
    }

    public func workspaceInfo(for path: String) -> DiagnosticsWorkspaceInfo {
        let url = URL(fileURLWithPath: path)
        return DiagnosticsWorkspaceInfo(
            basename: sanitize(url.lastPathComponent),
            pathHash: Self.stableHash(path),
            fullPath: includeFullPaths ? sanitize(path) : nil)
    }

    public func sanitize(metadata: [String: String]) -> [String: String] {
        metadata.reduce(into: [:]) { result, pair in
            result[pair.key] = shouldRedactValue(forKey: pair.key) ? "[redacted]" : sanitize(pair.value)
        }
    }

    public func sanitize(_ value: String) -> String {
        let secretWords = ["secret", "token", "password", "credential", "authorization", "api_key", "apikey"]
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if secretWords.contains(where: { text.lowercased().contains($0) }) {
            text = "[redacted]"
        }
        if !includeFullPaths {
            text = redactAbsolutePaths(in: text)
        }
        if text.count > maxMessageLength {
            return "\(text.prefix(maxMessageLength))..."
        }
        return text
    }

    private func recoveryRecord(_ record: RecoveryJournalRecord) -> RecoveryJournalRecord {
        var copy = record
        copy.title = sanitize(record.title)
        copy.message = record.message.map(sanitize)
        copy.metadata = sanitize(metadata: record.metadata)
        return copy
    }

    private func shouldRedactValue(forKey key: String) -> Bool {
        let lower = key.lowercased()
        return [
            "prompt", "source", "body", "content", "preview", "stdout", "stderr",
            "secret", "token", "password", "credential", "authorization",
        ].contains { lower.contains($0) }
    }

    private func redactAbsolutePaths(in value: String) -> String {
        let pattern = #"/[^\s,\"')\]]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return value }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        var result = value
        for match in regex.matches(in: value, range: range).reversed() {
            guard let swiftRange = Range(match.range, in: result) else { continue }
            let path = String(result[swiftRange])
            let replacement = "[path:\(Self.stableHash(path))]"
            result.replaceSubrange(swiftRange, with: replacement)
        }
        return result
    }

    public static func stableHash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .prefix(6)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
