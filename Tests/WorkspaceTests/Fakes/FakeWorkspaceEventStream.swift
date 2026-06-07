import Foundation
import Workspace

final class FakeWorkspaceEventStream: WorkspaceEventStream, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<[WorkspaceEvent]>.Continuation?

    func events(root: URL) -> AsyncStream<[WorkspaceEvent]> {
        AsyncStream { continuation in
            lock.withLock {
                self.continuation = continuation
            }
        }
    }

    func emit(_ events: [WorkspaceEvent]) {
        lock.withLock { continuation }?.yield(events)
    }

    func finish() {
        lock.withLock { continuation }?.finish()
    }
}
