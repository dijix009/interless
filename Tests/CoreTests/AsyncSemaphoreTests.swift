import Testing
import Foundation
import Core

struct AsyncSemaphoreTests {

    @Test func acquireReleaseRoundTrips() async throws {
        let sem = AsyncSemaphore(value: 1)
        try await sem.wait()
        sem.signal()
        try await sem.wait() // available again
        sem.signal()
    }

    @Test func immediateCancellationThrows() async throws {
        let sem = AsyncSemaphore(value: 0)
        let task = Task { try await sem.wait() }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    /// A waiter cancelled while queued must NOT consume a permit signaled later —
    /// otherwise the gate deadlocks for callers that don't release on cancel.
    @Test func cancelledQueuedWaiterDoesNotConsumeLaterSignaledPermit() async throws {
        let sem = AsyncSemaphore(value: 1)
        try await sem.wait()                          // hold the only permit
        let waiter = Task { try await sem.wait() }    // queues (no permit free)
        try await Task.sleep(for: .milliseconds(20))  // ensure it's queued
        waiter.cancel()
        _ = try? await waiter.value
        sem.signal()                                  // release the held permit

        // The permit must be available now — a fresh acquire succeeds promptly.
        // A lost permit would hang, so race against a timeout and assert we won.
        let acquired = await withTaskGroup(of: Bool.self) { group in
            group.addTask { (try? await sem.wait()) != nil }
            group.addTask { try? await Task.sleep(for: .seconds(2)); return false }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
        #expect(acquired)
    }
}
