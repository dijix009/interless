import Foundation
import os
import Shared
import Core

/// The sole authority for model lifecycle, KV-cache ownership, inference
/// streaming, and memory coordination (ARCHITECTURE.md §7).
///
/// Implemented as an isolated `actor`. It owns **no MLX types** — all model work
/// is delegated to an injected `InferenceBackend` (the real one is `MLXBackend`;
/// tests inject a fake), satisfying "no singleton global mutable state" (§17) via
/// constructor injection. It conforms to `MemorySnapshotProvider` and
/// `MemoryActionHandler` so a `MemoryPressureMonitor` can drive eviction without
/// `Core` ever depending on this type.
public actor InferenceController {

    private let backend: any InferenceBackend
    private let memoryMonitor: MemoryPressureMonitor
    private let memoryCoordinator: MemoryBudgetCoordinator
    private let log = Logger(subsystem: "dev.interless", category: "inference")

    /// Handles for currently-loaded models, keyed by role.
    private var handles: [ModelRole: LoadedModelHandle] = [:]

    /// Serializes the single active orchestrator generation stream (§8). Utility
    /// and embedding generations are not gated, so they may run concurrently.
    private let orchestratorGate = AsyncSemaphore(value: 1)

    /// Serializes model loads to prevent concurrent VRAM spikes, and dedupes
    /// reentrant same-role loads — actors are reentrant, so without this a second
    /// `loadModel` can start during the first's `await backend.load` (§7).
    private let loadGate = AsyncSemaphore(value: 1)

    /// Number of attempts for `loadModel` before giving up (§15 model-load retry).
    private let maxLoadAttempts: Int

    public init(
        backend: any InferenceBackend,
        memoryMonitor: MemoryPressureMonitor = MemoryPressureMonitor(),
        memoryCoordinator: MemoryBudgetCoordinator? = nil,
        resourceProfile: ResourceProfile = .automatic,
        maxLoadAttempts: Int = 2
    ) {
        self.backend = backend
        self.memoryMonitor = memoryMonitor
        self.memoryCoordinator = memoryCoordinator ?? MemoryBudgetCoordinator(requestedProfile: resourceProfile)
        self.maxLoadAttempts = max(1, maxLoadAttempts)
    }

    // MARK: - Spec API (§7)

    /// Lazily load a model for `role`. Idempotent: a second call for an
    /// already-loaded role is a no-op.
    public func loadModel(
        id: String,
        role: ModelRole,
        quantization: QuantizationLevel,
        toolCallFormat: ModelToolCallFormat? = nil,
        progressHandler: (@Sendable (_ modelID: String, _ role: ModelRole, _ fractionCompleted: Double) -> Void)? = nil
    ) async throws {
        if handles[role] != nil { return }

        // Serialize loads (§7) and dedupe reentrant same-role loads.
        try await loadGate.wait()
        defer { loadGate.signal() }

        // Another load may have completed this role while we waited on the gate.
        if handles[role] != nil { return }

        log.info("loading model \(id, privacy: .public) role=\(role.rawValue, privacy: .public) q=\(quantization.bitWidth)bit")

        var lastError: Error?
        for attempt in 1...maxLoadAttempts {
            do {
                let handle = try await backend.load(
                    id: id,
                    role: role,
                    quantization: quantization,
                    toolCallFormat: toolCallFormat,
                    progressHandler: { fraction in
                        progressHandler?(id, role, min(1, max(0, fraction)))
                    })
                handles[role] = handle
                log.info("loaded role=\(role.rawValue, privacy: .public) id=\(id, privacy: .public) attempt=\(attempt)")
                return
            } catch let error as InferenceError {
                // Deterministic failures (e.g. quantization mismatch) won't change on retry.
                if case .quantizationMismatch = error {
                    log.error("load failed (quantization mismatch) role=\(role.rawValue, privacy: .public): \(String(describing: error), privacy: .public)")
                    throw error
                }
                lastError = error
                log.error("load attempt \(attempt) failed role=\(role.rawValue, privacy: .public): \(String(describing: error), privacy: .public)")
            } catch {
                lastError = error
                log.error("load attempt \(attempt) failed role=\(role.rawValue, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }
        if let inferenceError = lastError as? InferenceError { throw inferenceError }
        throw InferenceError.modelLoadFailed(role: role, underlying: String(describing: lastError))
    }

    /// Build and return the token stream **immediately**. Generation runs in a
    /// producer task that re-enters the actor only for a brief pre-flight; the
    /// actor is not held during streaming.
    public func generate(request: GenerationRequest) -> AsyncThrowingStream<TokenChunk, Error> {
        let backend = self.backend
        let gate = self.orchestratorGate
        let log = self.log

        return AsyncThrowingStream(TokenChunk.self, bufferingPolicy: .unbounded) { continuation in
            let task = Task {
                do {
                    // Actor-isolated pre-flight: reject watermark + handle lookup.
                    let (handle, effectiveRequest) = try await self.preflight(request)

                    let isOrchestrator = (request.role == .orchestrator)
                    if isOrchestrator {
                        try await gate.wait() // throws CancellationError if cancelled while waiting
                    }
                    // Permit held (if orchestrator) from here — must be released.
                    do {
                        defer { if isOrchestrator { gate.signal() } }
                        try Task.checkCancellation()
                        log.debug("generate start id=\(request.id.uuidString, privacy: .public) role=\(request.role.rawValue, privacy: .public)")

                        for try await chunk in backend.generate(request: effectiveRequest, handle: handle) {
                            try Task.checkCancellation()
                            continuation.yield(chunk)
                        }
                        continuation.finish()
                    }
                } catch is CancellationError {
                    continuation.finish(throwing: InferenceError.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            // Forward consumer cancellation / early break into the producer task.
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func embed(texts: [String]) async throws -> [EmbeddingVector] {
        try Task.checkCancellation()
        guard !texts.isEmpty else { return [] }
        let snapshot = await currentMemoryUsage()
        let dueActions = await memoryCoordinator.evaluate(snapshot: snapshot)
        for action in dueActions where action != .rejectInference {
            await perform(action)
        }
        let state = await memoryCoordinator.currentState()
        if state.activeActions.contains(MemoryBudgetCoordinator.actionName(.rejectInference)) {
            throw InferenceError.memoryPressureRejected(usedFraction: snapshot.usedFraction)
        }
        guard let handle = handles[.embeddings] else {
            throw InferenceError.modelNotLoaded(.embeddings)
        }
        return try await backend.embed(texts: texts, handle: handle)
    }

    /// Load a speculative-decoding draft model for the orchestrator, gated on the
    /// resolved profile and current memory headroom. Returns `false` (without
    /// throwing) when the gate declines — speculative decoding is purely opt-in
    /// and must never block normal chat.
    @discardableResult
    public func loadDraftModel(
        id: String,
        quantization: QuantizationLevel = .q4,
        progressHandler: (@Sendable (_ modelID: String, _ fractionCompleted: Double) -> Void)? = nil
    ) async throws -> Bool {
        let state = await memoryCoordinator.currentState()
        guard state.resolvedProfile == .largeRAM else {
            log.notice("draft model skipped: profile \(state.resolvedProfile.rawValue, privacy: .public) is not largeRAM")
            return false
        }
        // An extra resident model: require headroom below the unload watermark.
        let snapshot = await currentMemoryUsage()
        guard snapshot.usedFraction < MemoryThresholds.default.unloadUtilityModel else {
            log.notice("draft model skipped: memory at \(snapshot.usedFraction, format: .fixed(precision: 2))")
            return false
        }
        try await loadGate.wait()
        defer { loadGate.signal() }
        _ = try await backend.loadDraftModel(
            id: id,
            forRole: .orchestrator,
            quantization: quantization,
            progressHandler: { fraction in progressHandler?(id, min(1, max(0, fraction))) })
        log.info("draft model loaded id=\(id, privacy: .public)")
        return true
    }

    /// Tokenizer-true count via the backend (estimate when the role isn't loaded).
    public func countTokens(_ text: String, role: ModelRole) async -> Int {
        await backend.countTokens(text, role: role)
    }

    public func unload(role: ModelRole) async {
        guard handles[role] != nil else { return }
        handles[role] = nil
        await backend.unloadDraftModel(forRole: role)
        await backend.unload(role: role)
        log.info("unloaded role=\(role.rawValue, privacy: .public)")
    }

    public func clearKVCache(role: ModelRole) async {
        await backend.clearKVCache(role: role)
        log.info("cleared KV cache role=\(role.rawValue, privacy: .public)")
    }

    public func currentMemoryUsage() async -> MemorySnapshot {
        let gpu = await backend.gpuMemory()
        let footprint = await backend.footprint()
        return MemorySnapshot(
            footprint: footprint,
            gpu: gpu,
            loadedRoles: Set(handles.keys),
            kvCacheBytes: [:]
        )
    }

    // MARK: - Memory-monitor wiring

    /// Wire the injected `MemoryPressureMonitor` to this controller and begin
    /// observing real memory pressure. Called by the composition root
    /// (`EngineBootstrap`, and later `App/`).
    public func startMemoryMonitoring() {
        memoryMonitor.start(provider: self, handler: self, coordinator: memoryCoordinator)
    }

    public func memoryPolicyState() async -> MemoryPolicyState {
        await memoryCoordinator.currentState()
    }

    /// Test/diagnostic hook: which roles are currently loaded.
    public var loadedRoles: Set<ModelRole> { Set(handles.keys) }

    // MARK: - Private

    private func preflight(_ request: GenerationRequest) async throws -> (LoadedModelHandle, GenerationRequest) {
        // 95% reject watermark (§8) — refuse before any heavy work.
        let snapshot = await currentMemoryUsage()
        let dueActions = await memoryCoordinator.evaluate(snapshot: snapshot)
        for action in dueActions where action != .rejectInference {
            await perform(action)
        }
        let state = await memoryCoordinator.currentState()
        if state.activeActions.contains(MemoryBudgetCoordinator.actionName(.rejectInference)) {
            log.error("rejecting inference: memory at \(snapshot.usedFraction, format: .fixed(precision: 2))")
            throw InferenceError.memoryPressureRejected(usedFraction: snapshot.usedFraction)
        }
        guard let handle = handles[request.role] else {
            throw InferenceError.modelNotLoaded(request.role)
        }
        return (handle, Self.capped(request, budget: state.budget))
    }

    private static func capped(_ request: GenerationRequest, budget: ResourceBudget) -> GenerationRequest {
        var copy = request
        if let cap = budget.contextTokenBudget(for: request.role) {
            copy.contextTokenBudget = min(request.contextTokenBudget ?? cap, cap)
        }
        if let cap = budget.maxTokens(for: request.role, reasoningEffort: request.reasoningEffort) {
            copy.maxTokens = min(request.maxTokens ?? cap, cap)
        }
        if request.role != .orchestrator {
            copy.reuseKVCache = false
        }
        // Resolve engine tuning (KV-cache policy, prefill, memory caps) from the
        // active budget unless the request already carries an override.
        copy.engineTuning = request.engineTuning ?? budget.engineTuning
        return copy
    }
}

// MARK: - Core protocol conformances (let MemoryPressureMonitor drive eviction)

extension InferenceController: MemorySnapshotProvider {}

extension InferenceController: MemoryActionHandler {
    /// Execute a memory-pressure action (§8). Crucially, a *utility* watermark
    /// never clears the orchestrator's persistent KV cache.
    public func perform(_ action: MemoryAction) async {
        switch action {
        case .clearUtilityKVCache:
            await clearKVCache(role: .utility)
        case .suspendEmbeddings:
            await unload(role: .embeddings)
        case .reduceContext:
            log.notice("memory pressure: reduce context (advisory; enforced per-request)")
        case .unloadUtilityModel:
            // Shed the (optional) speculative draft with the utility model: both
            // are accelerators, never required for correctness.
            await backend.unloadDraftModel(forRole: .orchestrator)
            await unload(role: .utility)
        case .rejectInference:
            log.notice("memory pressure: new inference will be rejected at the 95% watermark")
        }
    }
}
