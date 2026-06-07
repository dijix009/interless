import Foundation
import Shared

public struct NativeExtensionRecord: Sendable, Equatable, Codable, Identifiable {
    public enum Kind: String, Sendable, Equatable, Codable, CaseIterable {
        case skill
        case reference
        case tool
        case mcp
        case provider
    }

    public var id: String
    public var kind: Kind
    public var name: String
    public var source: String
    public var enabled: Bool
    public var options: [String: JSONValue]

    public init(
        id: String,
        kind: Kind,
        name: String,
        source: String,
        enabled: Bool = true,
        options: [String: JSONValue] = [:]
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.source = source
        self.enabled = enabled
        self.options = options
    }
}

public enum ExtensionRegistryEvent: Sendable, Equatable {
    case registered(NativeExtensionRecord)
    case removed(String)
}

public actor ExtensionRegistry {
    private var records: [String: NativeExtensionRecord] = [:]
    private var subscribers: [UUID: AsyncStream<ExtensionRegistryEvent>.Continuation] = [:]

    public init(records: [NativeExtensionRecord] = []) {
        self.records = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
    }

    public func register(_ record: NativeExtensionRecord) {
        records[record.id] = record
        publish(.registered(record))
    }

    public func remove(id: String) {
        records.removeValue(forKey: id)
        publish(.removed(id))
    }

    public func all(kind: NativeExtensionRecord.Kind? = nil, enabledOnly: Bool = false) -> [NativeExtensionRecord] {
        records.values
            .filter { record in
                (kind == nil || record.kind == kind) && (!enabledOnly || record.enabled)
            }
            .sorted { $0.id < $1.id }
    }

    public func stream() -> AsyncStream<ExtensionRegistryEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            subscribers[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeSubscriber(id) }
            }
        }
    }

    private func publish(_ event: ExtensionRegistryEvent) {
        for continuation in subscribers.values {
            continuation.yield(event)
        }
    }

    private func removeSubscriber(_ id: UUID) {
        subscribers.removeValue(forKey: id)
    }
}
