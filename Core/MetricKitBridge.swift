import Foundation

#if canImport(MetricKit)
@preconcurrency import MetricKit

public final class MetricKitBridge: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    private let recorder: MetricsRecorder
    private let source: String
    private var isStarted = false
    private let lock = NSLock()

    public init(recorder: MetricsRecorder, source: String = "MetricKit") {
        self.recorder = recorder
        self.source = source
        super.init()
    }

    public static var isAvailable: Bool { true }

    public func start() {
        lock.withLock {
            guard !isStarted else { return }
            isStarted = true
            MXMetricManager.shared.add(self)
        }
    }

    public func stop() {
        lock.withLock {
            guard isStarted else { return }
            isStarted = false
            MXMetricManager.shared.remove(self)
        }
    }

    public func didReceive(_ payloads: [MXMetricPayload]) {
        let count = payloads.count
        let source = self.source
        Task {
            await recorder.record(.init(
                kind: .memoryFootprint,
                unit: .count,
                value: Double(count),
                metadata: ["source": source, "payload": "metric"]))
        }
    }

    public func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let count = payloads.count
        let source = self.source
        Task {
            await recorder.record(.init(
                kind: .failureCount,
                unit: .count,
                value: Double(count),
                metadata: ["source": source, "payload": "diagnostic"]))
        }
    }
}
#else
public final class MetricKitBridge: @unchecked Sendable {
    public init(recorder: MetricsRecorder, source: String = "MetricKit") {}
    public static var isAvailable: Bool { false }
    public func start() {}
    public func stop() {}
}
#endif
