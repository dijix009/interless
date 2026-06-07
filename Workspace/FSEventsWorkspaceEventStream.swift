@preconcurrency import CoreServices
import Foundation

/// FSEvents-backed workspace event stream. Events are delivered in filesystem
/// batches and coalesced further by `WorkspaceWatcher`.
public final class FSEventsWorkspaceEventStream: WorkspaceEventStream, @unchecked Sendable {
    private let latency: TimeInterval

    public init(latency: TimeInterval = 0.25) {
        self.latency = latency
    }

    public func events(root: URL) -> AsyncStream<[WorkspaceEvent]> {
        let rootPath = root.standardizedFileURL.path
        let latency = self.latency
        return AsyncStream { continuation in
            let bridge = FSEventsBridge(
                rootPath: rootPath,
                latency: latency,
                continuation: continuation)
            guard bridge.start() else {
                continuation.finish()
                return
            }
            continuation.onTermination = { _ in bridge.stop() }
        }
    }
}

private let fseventsCallback: FSEventStreamCallback = { _, info, count, eventPaths, eventFlags, _ in
    guard let info else { return }
    let bridge = Unmanaged<FSEventsBridge>.fromOpaque(info).takeUnretainedValue()
    bridge.yield(count: count, eventPaths: eventPaths, eventFlags: eventFlags)
}

private final class FSEventsBridge: @unchecked Sendable {
    private let rootPath: String
    private let rootPrefix: String
    private let latency: TimeInterval
    private let continuation: AsyncStream<[WorkspaceEvent]>.Continuation
    private let lock = NSLock()
    private var stream: FSEventStreamRef?

    init(
        rootPath: String,
        latency: TimeInterval,
        continuation: AsyncStream<[WorkspaceEvent]>.Continuation
    ) {
        self.rootPath = rootPath
        self.rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        self.latency = latency
        self.continuation = continuation
    }

    func start() -> Bool {
        let retainedSelf = Unmanaged.passRetained(self).toOpaque()
        var context = FSEventStreamContext(
            version: 0,
            info: retainedSelf,
            retain: nil,
            release: { info in
                if let info {
                    Unmanaged<FSEventsBridge>.fromOpaque(info).release()
                }
            },
            copyDescription: nil)

        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagNoDefer)
        guard let stream = FSEventStreamCreate(
            nil,
            fseventsCallback,
            &context,
            [rootPath] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags)
        else {
            Unmanaged<FSEventsBridge>.fromOpaque(retainedSelf).release()
            return false
        }

        lock.withLock {
            self.stream = stream
        }
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .utility))
        FSEventStreamStart(stream)
        return true
    }

    func stop() {
        let stream = lock.withLock {
            let stream = self.stream
            self.stream = nil
            return stream
        }
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }

    func yield(
        count: Int,
        eventPaths: UnsafeMutableRawPointer,
        eventFlags: UnsafePointer<FSEventStreamEventFlags>
    ) {
        let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []
        var events: [WorkspaceEvent] = []
        for index in 0..<count {
            let path = index < paths.count ? paths[index] : rootPath
            let flags = eventFlags[index]
            events.append(WorkspaceEvent(
                relativePath: relativePath(for: path),
                kind: Self.kind(from: flags),
                isDirectory: (flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir)) != 0))
        }
        if !events.isEmpty { continuation.yield(events) }
    }

    private func relativePath(for path: String) -> String? {
        if path == rootPath { return nil }
        guard path.hasPrefix(rootPrefix) else { return nil }
        return String(path.dropFirst(rootPrefix.count))
    }

    private static func kind(from flags: FSEventStreamEventFlags) -> WorkspaceEventKind {
        if (flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved)) != 0 { return .deleted }
        if (flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRenamed)) != 0 { return .renamed }
        if (flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated)) != 0 { return .created }
        if (flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified)) != 0 { return .modified }
        return .unknown
    }
}
