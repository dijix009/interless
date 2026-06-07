import Foundation

public enum AppEventKind: String, Sendable, Codable, Equatable, CaseIterable {
    case workspace
    case indexing
    case search
    case filePreview
    case git
    case chat
    case model
    case tool
    case patch
    case memory
    case diagnostics
    case task
    case failure
    case cancellation
}

public enum AppEventSeverity: String, Sendable, Codable, Equatable, CaseIterable {
    case debug
    case info
    case warning
    case error
}

public struct AppEvent: Identifiable, Sendable, Codable, Equatable {
    public var id: UUID
    public var date: Date
    public var kind: AppEventKind
    public var severity: AppEventSeverity
    public var message: String
    public var metadata: [String: String]

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        kind: AppEventKind,
        severity: AppEventSeverity = .info,
        message: String,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.date = date
        self.kind = kind
        self.severity = severity
        self.message = message
        self.metadata = metadata
    }
}

public actor EventBus {
    private let retentionLimit: Int
    private var events: [AppEvent] = []
    private var subscribers: [UUID: AsyncStream<AppEvent>.Continuation] = [:]

    public init(retentionLimit: Int = 200) {
        self.retentionLimit = max(1, retentionLimit)
    }

    public func publish(_ event: AppEvent) {
        events.append(event)
        if events.count > retentionLimit {
            events.removeFirst(events.count - retentionLimit)
        }
        for continuation in subscribers.values {
            continuation.yield(event)
        }
    }

    public func stream() -> AsyncStream<AppEvent> {
        let id = UUID()
        return AsyncStream(AppEvent.self, bufferingPolicy: .bufferingNewest(retentionLimit)) { continuation in
            for event in events {
                continuation.yield(event)
            }
            subscribers[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeSubscriber(id) }
            }
        }
    }

    public func recentEvents(limit: Int? = nil) -> [AppEvent] {
        let maxCount = max(0, limit ?? events.count)
        return Array(events.suffix(maxCount))
    }

    private func removeSubscriber(_ id: UUID) {
        subscribers[id] = nil
    }
}
