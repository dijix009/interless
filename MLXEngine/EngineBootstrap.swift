import Core
import Shared
import CloudInference

/// Phase 1 composition root for the inference stack.
///
/// Wires the real `MLXBackend` and a `MemoryPressureMonitor` into an
/// `InferenceController` and starts memory-pressure monitoring. This is the one
/// place that knows about both `Core` and the concrete backend — `App/` takes
/// over this role in Phase 4. Keeping the wiring here (not in `Core`) is what
/// lets the dependency point only `MLXEngine → Core`.
public enum EngineBootstrap {

    /// Build the live inference controller (real MLX backend) and begin
    /// observing macOS memory pressure.
    public static func liveController(
        gpuCacheLimitBytes: Int? = nil,
        resourceProfile: ResourceProfile = .automatic,
        memoryCoordinator: MemoryBudgetCoordinator? = nil,
        thresholds: MemoryThresholds = .default
    ) async -> InferenceController {
        let budget = ResourceBudget.resolved(for: resourceProfile)
        var engineTuning = budget.engineTuning
        if let gpuCacheLimitBytes { engineTuning.gpuCacheLimitBytes = gpuCacheLimitBytes }
        // Local MLX is the default; the routing backend sends only `provider/model`
        // ids (e.g. `anthropic/…`) to the hosted backend. Local ids are unaffected,
        // and the remote backend is inert until a cloud id is loaded (gated by the
        // consent + key checks in the app layer).
        let backend = RoutingInferenceBackend(
            local: MLXBackend(engineTuning: engineTuning),
            remote: RemoteInferenceBackend(client: AnthropicModelClient()))
        let controller = InferenceController(
            backend: backend,
            memoryMonitor: MemoryPressureMonitor(thresholds: thresholds),
            memoryCoordinator: memoryCoordinator,
            resourceProfile: resourceProfile
        )
        await controller.startMemoryMonitoring()
        return controller
    }
}
