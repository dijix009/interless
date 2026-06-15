import Foundation
import Shared

/// Debounces workspace filesystem events and drives path-scoped indexing.
public actor WorkspaceWatcher {
    private let root: URL
    private let eventStream: any WorkspaceEventStream
    private let indexer: WorkspaceIndexer
    private let debounce: Duration
    private let ignoredEventPathComponents: Set<String>
    private var pending: [WorkspaceEvent] = []
    private var inFlight = false

    public init(
        root: URL,
        eventStream: any WorkspaceEventStream,
        indexer: WorkspaceIndexer,
        debounce: Duration = .milliseconds(500),
        ignoredEventPathComponents: Set<String> = [".git", ".build"]
    ) {
        self.root = root
        self.eventStream = eventStream
        self.indexer = indexer
        self.debounce = debounce
        self.ignoredEventPathComponents = ignoredEventPathComponents
    }

    public func start() -> AsyncStream<IndexingProgress> {
        let root = self.root
        let eventStream = self.eventStream
        let ignoredComponents = self.ignoredEventPathComponents
        return AsyncStream(IndexingProgress.self, bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task {
                for await batch in eventStream.events(root: root) {
                    let filtered = batch.filter {
                        !Self.isIgnoredGeneratedEvent($0, ignoredComponents: ignoredComponents)
                    }
                    guard !filtered.isEmpty else { continue }
                    self.enqueue(filtered, continuation: continuation)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func enqueue(
        _ events: [WorkspaceEvent],
        continuation: AsyncStream<IndexingProgress>.Continuation
    ) {
        pending.append(contentsOf: events)
        // A single drain loop runs at a time. Events arriving while a reindex is
        // in flight just append to `pending`; the loop picks them up in its next
        // (debounce-coalesced) iteration — no overlapping scheduled tasks, so a
        // burst (git checkout, build output) can't spawn a storm of reindexes.
        guard !inFlight else { return }
        inFlight = true
        Task { await drain(continuation: continuation) }
    }

    private func drain(continuation: AsyncStream<IndexingProgress>.Continuation) async {
        while true {
            try? await Task.sleep(for: debounce)
            let batch = pending
            pending.removeAll(keepingCapacity: true)
            guard !batch.isEmpty else {
                inFlight = false
                return
            }
            let stream = await indexer.reindex(events: batch)
            for await progress in stream {
                continuation.yield(progress)
            }
        }
    }

    private static func isIgnoredGeneratedEvent(
        _ event: WorkspaceEvent,
        ignoredComponents: Set<String>
    ) -> Bool {
        guard let relativePath = event.relativePath else { return false }
        return relativePath.split(separator: "/").contains { ignoredComponents.contains(String($0)) }
    }
}
