import Foundation

public enum MetricKind: String, Sendable, Codable, Equatable, CaseIterable {
    case inferenceLatency
    case indexingDuration
    case searchDuration
    case filePreviewDuration
    case gitDuration
    case toolExecutionLatency
    case patchApplyDuration
    case modelLoadDuration
    case memoryFootprint
    case memoryPressureActionCount
    case indexBytesRead
    case indexSkippedTooLargeCount
    case searchSnippetBytesRead
    case contextCharacters
    case toolOutputBytes
    case toolOutputTruncatedCount
    case cancellationCount
    case failureCount
}

public enum MetricUnit: String, Sendable, Codable, Equatable, CaseIterable {
    case milliseconds
    case count
    case bytes
    case ratio
}

public struct MetricSample: Identifiable, Sendable, Codable, Equatable {
    public var id: UUID
    public var date: Date
    public var kind: MetricKind
    public var unit: MetricUnit
    public var value: Double
    public var metadata: [String: String]

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        kind: MetricKind,
        unit: MetricUnit,
        value: Double,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.date = date
        self.kind = kind
        self.unit = unit
        self.value = value
        self.metadata = metadata
    }
}

public struct MetricSummary: Identifiable, Sendable, Codable, Equatable {
    public var id: MetricKind { kind }
    public var kind: MetricKind
    public var unit: MetricUnit
    public var count: Int
    public var latest: Double
    public var average: Double
    public var minimum: Double
    public var maximum: Double

    public init(kind: MetricKind, unit: MetricUnit, samples: [MetricSample]) {
        self.kind = kind
        self.unit = unit
        self.count = samples.count
        self.latest = samples.last?.value ?? 0
        self.average = samples.isEmpty ? 0 : samples.reduce(0) { $0 + $1.value } / Double(samples.count)
        self.minimum = samples.map(\.value).min() ?? 0
        self.maximum = samples.map(\.value).max() ?? 0
    }
}

public actor MetricsRecorder {
    private let retentionLimit: Int
    private var samples: [MetricSample] = []

    public init(retentionLimit: Int = 500) {
        self.retentionLimit = max(1, retentionLimit)
    }

    public func record(_ sample: MetricSample) {
        samples.append(sample)
        if samples.count > retentionLimit {
            samples.removeFirst(samples.count - retentionLimit)
        }
    }

    @discardableResult
    public func measure<T>(
        kind: MetricKind,
        metadata: [String: String] = [:],
        operation: () async throws -> T
    ) async rethrows -> T {
        let start = ContinuousClock.now
        do {
            let value = try await operation()
            let elapsed = start.duration(to: ContinuousClock.now)
            record(.init(kind: kind, unit: .milliseconds, value: elapsed.milliseconds, metadata: metadata))
            return value
        } catch {
            let elapsed = start.duration(to: ContinuousClock.now)
            record(.init(kind: kind, unit: .milliseconds, value: elapsed.milliseconds, metadata: metadata))
            throw error
        }
    }

    public func recentSamples(limit: Int? = nil) -> [MetricSample] {
        let maxCount = max(0, limit ?? samples.count)
        return Array(samples.suffix(maxCount))
    }

    public func summaries() -> [MetricSummary] {
        Dictionary(grouping: samples, by: \.kind)
            .map { kind, samples in
                MetricSummary(kind: kind, unit: samples.last?.unit ?? .count, samples: samples)
            }
            .sorted { $0.kind.rawValue < $1.kind.rawValue }
    }
}

private extension Duration {
    var milliseconds: Double {
        let components = components
        return Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}
