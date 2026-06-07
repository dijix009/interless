import Foundation
import Testing
import Core

struct ObservabilityTests {
    @Test func eventBusKeepsOrderingRetentionAndSnapshots() async {
        let bus = EventBus(retentionLimit: 2)

        await bus.publish(.init(kind: .workspace, message: "first"))
        await bus.publish(.init(kind: .search, message: "second"))
        await bus.publish(.init(kind: .git, message: "third"))

        let recent = await bus.recentEvents()
        #expect(recent.map(\.message) == ["second", "third"])
        #expect(await bus.recentEvents(limit: 1).map(\.message) == ["third"])
    }

    @Test func eventBusDeliversToMultipleSubscribers() async {
        let bus = EventBus(retentionLimit: 10)
        var first = await bus.stream().makeAsyncIterator()
        var second = await bus.stream().makeAsyncIterator()
        let event = AppEvent(kind: .chat, message: "token")

        await bus.publish(event)

        #expect(await first.next() == event)
        #expect(await second.next() == event)
    }

    @Test func taskSchedulerTracksCompletionCancellationAndRetention() async {
        let scheduler = TaskScheduler(retentionLimit: 2)
        let completedID = await scheduler.start(kind: "fast", title: "Fast") {}
        let cancelledID = await scheduler.start(kind: "slow", title: "Slow") {
            try await Task.sleep(for: .seconds(5))
        }

        try? await Task.sleep(for: .milliseconds(20))
        await scheduler.cancel(id: cancelledID)
        try? await Task.sleep(for: .milliseconds(50))

        let snapshot = await scheduler.snapshot()
        #expect(!snapshot.active.contains { $0.id == completedID })
        #expect(!snapshot.active.contains { $0.id == cancelledID })
        #expect(snapshot.recent.map(\.status).contains(.completed))
        #expect(snapshot.recent.map(\.status).contains(.cancelled))
        #expect(snapshot.recent.count <= 2)
    }

    @Test func taskSchedulerManualLifecycleAppearsInSnapshots() async {
        let scheduler = TaskScheduler()

        let id = await scheduler.begin(kind: "indexing", title: "Index workspace", priority: .userInitiated)
        var snapshot = await scheduler.snapshot()
        #expect(snapshot.active.map(\.id) == [id])
        #expect(snapshot.active.first?.status == .running)

        await scheduler.finish(id: id, status: .completed, message: "done")
        snapshot = await scheduler.snapshot()
        #expect(snapshot.active.isEmpty)
        #expect(snapshot.recent.first?.id == id)
        #expect(snapshot.recent.first?.message == "done")
    }

    @Test func metricsRecorderAggregatesAndMeasuresDurations() async throws {
        let recorder = MetricsRecorder(retentionLimit: 3)

        await recorder.record(.init(kind: .failureCount, unit: .count, value: 1))
        await recorder.record(.init(kind: .failureCount, unit: .count, value: 3))
        let measured = try await recorder.measure(kind: .searchDuration) {
            try await Task.sleep(for: .milliseconds(1))
            return 42
        }

        let summaries = await recorder.summaries()
        let failures = try #require(summaries.first { $0.kind == .failureCount })
        let search = try #require(summaries.first { $0.kind == .searchDuration })

        #expect(measured == 42)
        #expect(failures.count == 2)
        #expect(failures.latest == 3)
        #expect(failures.average == 2)
        #expect(search.unit == .milliseconds)
        #expect(search.latest >= 0)
        #expect(await recorder.recentSamples().count <= 3)
    }

    @Test func metricKitBridgeLifecycleIsIdempotent() async {
        let bridge = MetricKitBridge(recorder: MetricsRecorder())
        bridge.start()
        bridge.start()
        bridge.stop()
        bridge.stop()
    }
}
