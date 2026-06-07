import Foundation

/// A minimal FIFO async counting semaphore.
///
/// The Swift standard library has no async semaphore, and using actor isolation
/// alone to serialize an exclusive section — e.g. the single active inference
/// stream in `MLXEngine`, or a full workspace re-index in `Workspace` — would
/// also serialize unrelated calls on the same actor. This gate is
/// **cancellation-aware**: a task cancelled while waiting throws
/// `CancellationError` and does not consume a permit.
public final class AsyncSemaphore: @unchecked Sendable {

    private struct Waiter {
        let id: UInt64
        let continuation: CheckedContinuation<Void, Error>
    }

    private let lock = NSLock()
    private var permits: Int
    private var waiters: [Waiter] = []
    private var nextWaiterID: UInt64 = 0

    public init(value: Int) {
        precondition(value >= 0, "AsyncSemaphore value must be non-negative")
        self.permits = value
    }

    /// Acquire a permit, suspending until one is available.
    /// Throws `CancellationError` if the awaiting task is cancelled while waiting.
    public func wait() async throws {
        try Task.checkCancellation()

        let id: UInt64 = {
            lock.lock()
            defer { lock.unlock() }
            let next = nextWaiterID
            nextWaiterID &+= 1
            return next
        }()

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.lock()
                if Task.isCancelled {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                if permits > 0 {
                    permits -= 1
                    lock.unlock()
                    continuation.resume()
                    return
                }
                waiters.append(Waiter(id: id, continuation: continuation))
                lock.unlock()
            }
        } onCancel: {
            lock.lock()
            if let index = waiters.firstIndex(where: { $0.id == id }) {
                let waiter = waiters.remove(at: index)
                lock.unlock()
                waiter.continuation.resume(throwing: CancellationError())
            } else {
                lock.unlock()
            }
        }
    }

    /// Release a permit, resuming the next FIFO waiter if any.
    public func signal() {
        lock.lock()
        if waiters.isEmpty {
            permits += 1
            lock.unlock()
        } else {
            let waiter = waiters.removeFirst()
            lock.unlock()
            waiter.continuation.resume()
        }
    }
}
