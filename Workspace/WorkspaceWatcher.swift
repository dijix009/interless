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
    private var scheduled = false

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
        guard !scheduled else { return }
        scheduled = true
        Task {
            try? await Task.sleep(for: debounce)
            let batch = takePending()
            let stream = await indexer.reindex(events: batch)
            for await progress in stream {
                continuation.yield(progress)
            }
        }
    }

    private func takePending() -> [WorkspaceEvent] {
        let batch = pending
        pending.removeAll(keepingCapacity: true)
        scheduled = false
        return batch
    }

    private static func isIgnoredGeneratedEvent(
        _ event: WorkspaceEvent,
        ignoredComponents: Set<String>
    ) -> Bool {
        guard let relativePath = event.relativePath else { return false }
        return relativePath.split(separator: "/").contains { ignoredComponents.contains(String($0)) }
    }
}
