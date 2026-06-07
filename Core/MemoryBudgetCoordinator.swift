import Foundation
import Shared

public actor MemoryBudgetCoordinator {
    private let thresholds: MemoryThresholds
    private let metrics: MetricsRecorder?
    private let events: EventBus?
    private let cooldownSeconds: TimeInterval
    private let physicalMemoryBytes: Int
    private var requestedProfile: ResourceProfile
    private var lastActionDates: [MemoryAction: Date] = [:]
    private var state: MemoryPolicyState

    public init(
        requestedProfile: ResourceProfile = .automatic,
        physicalMemoryBytes: Int = Int(ProcessInfo.processInfo.physicalMemory),
        thresholds: MemoryThresholds = .default,
        metrics: MetricsRecorder? = nil,
        events: EventBus? = nil,
        actionCooldownSeconds: TimeInterval = 15
    ) {
        self.requestedProfile = requestedProfile
        self.physicalMemoryBytes = physicalMemoryBytes
        self.thresholds = thresholds
        self.metrics = metrics
        self.events = events
        self.cooldownSeconds = max(0, actionCooldownSeconds)
        self.state = MemoryPolicyState(
            requestedProfile: requestedProfile,
            physicalMemoryBytes: physicalMemoryBytes)
    }

    public func setRequestedProfile(_ profile: ResourceProfile) {
        requestedProfile = profile
        state = MemoryPolicyState(
            requestedProfile: profile,
            physicalMemoryBytes: physicalMemoryBytes,
            snapshot: state.snapshot,
            activeActions: state.activeActions,
            evaluatedAt: Date())
    }

    public func currentState() -> MemoryPolicyState {
        state
    }

    public func currentBudget() -> ResourceBudget {
        state.budget
    }

    public func evaluate(snapshot: MemorySnapshot, now: Date = Date()) async -> [MemoryAction] {
        let actions = MemoryPressureMonitor(thresholds: thresholds).actions(for: snapshot)
        let names = actions.map(Self.actionName)
        state = MemoryPolicyState(
            requestedProfile: requestedProfile,
            physicalMemoryBytes: physicalMemoryBytes,
            snapshot: snapshot,
            activeActions: names,
            evaluatedAt: now)

        await metrics?.record(.init(
            kind: .memoryFootprint,
            unit: .bytes,
            value: Double(snapshot.footprint.processFootprintBytes),
            metadata: [
                "profile": state.resolvedProfile.rawValue,
                "usedFraction": String(format: "%.3f", snapshot.usedFraction),
            ]))

        var due: [MemoryAction] = []
        for action in actions {
            if shouldRun(action, now: now) {
                lastActionDates[action] = now
                due.append(action)
                await metrics?.record(.init(
                    kind: .memoryPressureActionCount,
                    unit: .count,
                    value: 1,
                    metadata: ["action": Self.actionName(action)]))
            }
        }

        if !actions.isEmpty {
            await events?.publish(.init(
                kind: .memory,
                severity: actions.contains(.rejectInference) ? .error : .warning,
                message: "Memory policy active: \(names.joined(separator: ", "))",
                metadata: [
                    "profile": state.resolvedProfile.rawValue,
                    "usedFraction": String(format: "%.3f", snapshot.usedFraction),
                ]))
        }
        return due
    }

    private func shouldRun(_ action: MemoryAction, now: Date) -> Bool {
        guard let last = lastActionDates[action] else { return true }
        return now.timeIntervalSince(last) >= cooldownSeconds
    }

    public static func actionName(_ action: MemoryAction) -> String {
        switch action {
        case .clearUtilityKVCache: return "clearUtilityKVCache"
        case .suspendEmbeddings: return "suspendEmbeddings"
        case .reduceContext: return "reduceContext"
        case .unloadUtilityModel: return "unloadUtilityModel"
        case .rejectInference: return "rejectInference"
        }
    }
}
