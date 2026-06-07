import Foundation
import Dispatch
import Shared

/// An eviction/throttle action the memory policy can request (ARCHITECTURE.md §8).
/// Ordered least → most severe.
public enum MemoryAction: Sendable, Equatable, CaseIterable {
    case clearUtilityKVCache   // ≥ 70%
    case suspendEmbeddings     // ≥ 80%
    case reduceContext         // ≥ 85%
    case unloadUtilityModel    // ≥ 90%
    case rejectInference       // ≥ 95%
}

/// The §8 memory-pressure watermarks, as fractions of unified memory in use.
public struct MemoryThresholds: Sendable, Equatable {
    public var clearUtilityKVCache: Double
    public var suspendEmbeddings: Double
    public var reduceContext: Double
    public var unloadUtilityModel: Double
    public var rejectInference: Double

    public init(
        clearUtilityKVCache: Double = 0.70,
        suspendEmbeddings: Double = 0.80,
        reduceContext: Double = 0.85,
        unloadUtilityModel: Double = 0.90,
        rejectInference: Double = 0.95
    ) {
        self.clearUtilityKVCache = clearUtilityKVCache
        self.suspendEmbeddings = suspendEmbeddings
        self.reduceContext = reduceContext
        self.unloadUtilityModel = unloadUtilityModel
        self.rejectInference = rejectInference
    }

    /// The spec's §8 defaults: 70 / 80 / 85 / 90 / 95 %.
    public static let `default` = MemoryThresholds()
}

/// Supplies the current memory state to the live monitor. `InferenceController`
/// conforms to this; Core never names the controller, so the dependency only
/// points `MLXEngine → Core`.
public protocol MemorySnapshotProvider: Sendable {
    func currentMemoryUsage() async -> MemorySnapshot
}

/// Executes a memory action (e.g. clear the utility KV cache, unload a model).
/// `InferenceController` conforms to this.
public protocol MemoryActionHandler: Sendable {
    func perform(_ action: MemoryAction) async
}

/// Memory-pressure policy + live macOS pressure source (ARCHITECTURE.md §8).
///
/// The policy (`actions(for:)`) is a **pure function** of the thresholds and a
/// `MemorySnapshot`, so it is exhaustively unit-testable with zero GPU. The live
/// source pulls a snapshot on each pressure signal and dispatches the resulting
/// actions to an injected handler. The monitor depends only on `Shared`.
public final class MemoryPressureMonitor: @unchecked Sendable {
    public let thresholds: MemoryThresholds

    private let lock = NSLock()
    private var source: DispatchSourceMemoryPressure?

    public init(thresholds: MemoryThresholds = .default) {
        self.thresholds = thresholds
    }

    // MARK: - Pure policy (unit-tested in isolation)

    /// Every action whose watermark the snapshot has crossed, ordered
    /// least → most severe. Pure: depends only on `thresholds` and the snapshot.
    public func actions(for snapshot: MemorySnapshot) -> [MemoryAction] {
        Self.actions(forUsedFraction: snapshot.usedFraction, thresholds: thresholds)
    }

    /// Convenience overload keyed directly on a usage fraction.
    public func actions(forUsedFraction fraction: Double) -> [MemoryAction] {
        Self.actions(forUsedFraction: fraction, thresholds: thresholds)
    }

    /// Single implementation, `static` so the live event handler need not
    /// capture `self`.
    private static func actions(forUsedFraction fraction: Double, thresholds: MemoryThresholds) -> [MemoryAction] {
        var actions: [MemoryAction] = []
        if fraction >= thresholds.clearUtilityKVCache { actions.append(.clearUtilityKVCache) }
        if fraction >= thresholds.suspendEmbeddings { actions.append(.suspendEmbeddings) }
        if fraction >= thresholds.reduceContext { actions.append(.reduceContext) }
        if fraction >= thresholds.unloadUtilityModel { actions.append(.unloadUtilityModel) }
        if fraction >= thresholds.rejectInference { actions.append(.rejectInference) }
        return actions
    }

    // MARK: - Live macOS memory-pressure source

    /// Begin observing real macOS memory pressure. On each warning/critical
    /// signal, pulls a snapshot from `provider`, computes `actions(for:)`, and
    /// dispatches each to `handler`. Concrete wiring (the `InferenceController`)
    /// happens in MLXEngine/App, never in Core.
    public func start(
        provider: any MemorySnapshotProvider,
        handler: any MemoryActionHandler,
        coordinator: MemoryBudgetCoordinator? = nil
    ) {
        let newSource = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .global(qos: .utility)
        )
        let thresholds = self.thresholds
        newSource.setEventHandler {
            // Hop off the signal handler; snapshot → policy → dispatch.
            Task {
                let snapshot = await provider.currentMemoryUsage()
                let actions: [MemoryAction]
                if let coordinator {
                    actions = await coordinator.evaluate(snapshot: snapshot)
                } else {
                    actions = Self.actions(forUsedFraction: snapshot.usedFraction, thresholds: thresholds)
                }
                for action in actions {
                    await handler.perform(action)
                }
            }
        }

        lock.lock()
        source?.cancel()
        source = newSource
        lock.unlock()

        newSource.activate()
    }

    /// Stop observing memory pressure.
    public func stop() {
        lock.lock()
        source?.cancel()
        source = nil
        lock.unlock()
    }
}
