import Foundation

public enum TrackedTaskPriority: String, Sendable, Codable, Equatable, CaseIterable {
    case background
    case utility
    case userInitiated
    case critical

    public var swiftPriority: TaskPriority {
        switch self {
        case .background: return .background
        case .utility: return .utility
        case .userInitiated: return .userInitiated
        case .critical: return .high
        }
    }
}

public enum TrackedTaskStatus: String, Sendable, Codable, Equatable, CaseIterable {
    case running
    case completed
    case failed
    case cancelled
}

public struct TrackedTaskRecord: Identifiable, Sendable, Codable, Equatable {
    public var id: UUID
    public var kind: String
    public var title: String
    public var priority: TrackedTaskPriority
    public var status: TrackedTaskStatus
    public var startedAt: Date
    public var endedAt: Date?
    public var message: String?

    public init(
        id: UUID = UUID(),
        kind: String,
        title: String,
        priority: TrackedTaskPriority,
        status: TrackedTaskStatus = .running,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        message: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.priority = priority
        self.status = status
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.message = message
    }
}

public struct TaskSchedulerSnapshot: Sendable, Codable, Equatable {
    public var active: [TrackedTaskRecord]
    public var recent: [TrackedTaskRecord]

    public init(active: [TrackedTaskRecord], recent: [TrackedTaskRecord]) {
        self.active = active
        self.recent = recent
    }
}

public actor TaskScheduler {
    private let retentionLimit: Int
    private var activeRecords: [UUID: TrackedTaskRecord] = [:]
    private var recentRecords: [TrackedTaskRecord] = []
    private var tasks: [UUID: Task<Void, Never>] = [:]

    public init(retentionLimit: Int = 100) {
        self.retentionLimit = max(1, retentionLimit)
    }

    @discardableResult
    public func begin(
        kind: String,
        title: String,
        priority: TrackedTaskPriority = .utility
    ) -> UUID {
        let id = UUID()
        activeRecords[id] = TrackedTaskRecord(id: id, kind: kind, title: title, priority: priority)
        return id
    }

    @discardableResult
    public func start(
        kind: String,
        title: String,
        priority: TrackedTaskPriority = .utility,
        operation: @escaping @Sendable () async throws -> Void
    ) -> UUID {
        let id = UUID()
        activeRecords[id] = TrackedTaskRecord(id: id, kind: kind, title: title, priority: priority)
        tasks[id] = Task(priority: priority.swiftPriority) { [weak self] in
            do {
                try Task.checkCancellation()
                try await operation()
                await self?.finish(id: id, status: .completed)
            } catch is CancellationError {
                await self?.finish(id: id, status: .cancelled, message: "Cancelled")
            } catch {
                await self?.finish(id: id, status: .failed, message: String(describing: error))
            }
        }
        return id
    }

    public func cancel(id: UUID) {
        tasks[id]?.cancel()
        finish(id: id, status: .cancelled, message: "Cancelled")
    }

    public func cancel(kind: String) {
        for id in activeRecords.values.filter({ $0.kind == kind }).map(\.id) {
            cancel(id: id)
        }
    }

    public func snapshot() -> TaskSchedulerSnapshot {
        TaskSchedulerSnapshot(
            active: activeRecords.values.sorted { $0.startedAt < $1.startedAt },
            recent: recentRecords)
    }

    public func recordManual(
        kind: String,
        title: String,
        priority: TrackedTaskPriority = .utility,
        status: TrackedTaskStatus,
        message: String? = nil
    ) {
        var record = TrackedTaskRecord(kind: kind, title: title, priority: priority, status: status)
        record.endedAt = Date()
        record.message = message
        appendRecent(record)
    }

    public func finish(id: UUID, status: TrackedTaskStatus, message: String? = nil) {
        guard var record = activeRecords.removeValue(forKey: id) else {
            tasks[id] = nil
            return
        }
        tasks[id] = nil
        record.status = status
        record.endedAt = Date()
        record.message = message
        appendRecent(record)
    }

    private func appendRecent(_ record: TrackedTaskRecord) {
        recentRecords.append(record)
        if recentRecords.count > retentionLimit {
            recentRecords.removeFirst(recentRecords.count - retentionLimit)
        }
    }
}
