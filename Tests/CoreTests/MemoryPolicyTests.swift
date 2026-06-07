import Testing
import Foundation
import Shared
import Core

/// Exhaustive table test of the §8 memory-pressure watermark policy — the
/// spec-critical logic, verified as a pure function with zero GPU.
struct MemoryPolicyTests {

    /// Build a snapshot whose `usedFraction == bytes / 1000` (exact in Double).
    private static func snapshot(_ bytes: Int) -> MemorySnapshot {
        MemorySnapshot(footprint: MemoryFootprint(processFootprintBytes: bytes, totalUnifiedBytes: 1000))
    }

    @Test(arguments: [
        (bytes: 500, expected: [MemoryAction]()),                       // below all
        (bytes: 699, expected: [MemoryAction]()),                       // just below 70%
        (bytes: 700, expected: [.clearUtilityKVCache]),                 // 70%
        (bytes: 820, expected: [.clearUtilityKVCache, .suspendEmbeddings]),
        (bytes: 860, expected: [.clearUtilityKVCache, .suspendEmbeddings, .reduceContext]),
        (bytes: 910, expected: [.clearUtilityKVCache, .suspendEmbeddings, .reduceContext, .unloadUtilityModel]),
        (bytes: 960, expected: [.clearUtilityKVCache, .suspendEmbeddings, .reduceContext, .unloadUtilityModel, .rejectInference]),
        (bytes: 1000, expected: [.clearUtilityKVCache, .suspendEmbeddings, .reduceContext, .unloadUtilityModel, .rejectInference]),
    ])
    func watermarkProducesCorrectActions(_ testCase: (bytes: Int, expected: [MemoryAction])) {
        let monitor = MemoryPressureMonitor()
        #expect(monitor.actions(for: Self.snapshot(testCase.bytes)) == testCase.expected)
    }

    @Test func actionsOrderedLeastToMostSevere() {
        let actions = MemoryPressureMonitor().actions(for: Self.snapshot(1000))
        #expect(actions == MemoryAction.allCases) // allCases declared least → most severe
    }

    @Test func customThresholdsAreHonored() {
        let monitor = MemoryPressureMonitor(
            thresholds: MemoryThresholds(clearUtilityKVCache: 0.50, suspendEmbeddings: 0.99,
                                         reduceContext: 0.99, unloadUtilityModel: 0.99, rejectInference: 0.99))
        #expect(monitor.actions(for: Self.snapshot(600)) == [.clearUtilityKVCache])
    }

    @Test func memoryBudgetCoordinatorResolvesProfileAndAppliesCooldown() async {
        let coordinator = MemoryBudgetCoordinator(
            requestedProfile: .automatic,
            physicalMemoryBytes: 8 * 1024 * 1024 * 1024,
            actionCooldownSeconds: 60)
        let now = Date(timeIntervalSince1970: 100)

        let first = await coordinator.evaluate(snapshot: Self.snapshot(960), now: now)
        let second = await coordinator.evaluate(snapshot: Self.snapshot(960), now: now.addingTimeInterval(1))
        let third = await coordinator.evaluate(snapshot: Self.snapshot(960), now: now.addingTimeInterval(61))
        let state = await coordinator.currentState()

        #expect(state.resolvedProfile == .smallRAM)
        #expect(state.activeActions.contains("rejectInference"))
        #expect(first == MemoryAction.allCases)
        #expect(second.isEmpty)
        #expect(third == MemoryAction.allCases)
    }
}
