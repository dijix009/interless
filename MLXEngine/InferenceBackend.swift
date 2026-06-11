import Shared

/// In-process seam between `InferenceController` and the concrete MLX runtime.
///
/// IMPORTANT — this is **not** a service boundary. There is no HTTP, no
/// localhost, no cross-process transport, and no token serialization: the real
/// implementation (`MLXBackend`) runs in the same target and address space
/// (ARCHITECTURE.md §3, "No Inference Microservices"). The protocol exists
/// solely so the controller's memory policy, stream serialization, and lifecycle
/// logic can be unit-tested against a `FakeBackend` without a multi-GB model or a
/// Metal GPU.
///
/// Conformers own all MLX state (model containers, KV caches). The controller
/// holds only MLX-free `LoadedModelHandle`s.
public protocol InferenceBackend: Sendable {

    /// Load a model for `role` at `quantization`, returning an MLX-free handle.
    /// Idempotency is handled by the caller (`InferenceController`).
    func load(
        id: String,
        role: ModelRole,
        quantization: QuantizationLevel,
        toolCallFormat: ModelToolCallFormat?,
        progressHandler: (@Sendable (Double) -> Void)?
    ) async throws -> LoadedModelHandle

    /// Stream generation for an already-loaded model.
    ///
    /// Contract (verified by the shared backend-conformance tests):
    /// - chunks arrive in ascending `index` order;
    /// - exactly one terminal chunk has `isFinal == true` and ends the stream;
    /// - cancelling the consuming task stops work and releases resources.
    func generate(
        request: GenerationRequest,
        handle: LoadedModelHandle
    ) -> AsyncThrowingStream<TokenChunk, Error>

    /// Produce normalized embedding vectors for already-loaded embedding models.
    /// Implementations must return repo-owned values and keep MLX types private.
    func embed(
        texts: [String],
        handle: LoadedModelHandle
    ) async throws -> [EmbeddingVector]

    /// Unload the model for `role`, freeing its weights and KV cache.
    func unload(role: ModelRole) async

    /// Discard the role's KV cache so the next generation starts fresh.
    func clearKVCache(role: ModelRole) async

    /// Load a speculative-decoding *draft* model attached to the model serving
    /// `role` (orchestrator in practice). Conformers must validate the draft
    /// shares the target's tokenizer and throw on mismatch. Subsequent
    /// generations for `role` use the draft automatically; unloading is via
    /// `unloadDraftModel(forRole:)` or `unload(role:)`.
    func loadDraftModel(
        id: String,
        forRole role: ModelRole,
        quantization: QuantizationLevel,
        progressHandler: (@Sendable (Double) -> Void)?
    ) async throws -> LoadedModelHandle

    /// Unload `role`'s draft model (no-op when none is loaded).
    func unloadDraftModel(forRole role: ModelRole) async

    /// Tokenizer-true token count for `text` using `role`'s loaded model;
    /// falls back to a deterministic estimate when the model isn't loaded.
    func countTokens(_ text: String, role: ModelRole) async -> Int

    /// Current MLX GPU allocator counters (active / cache / peak bytes).
    func gpuMemory() async -> GPUMemory

    /// Current process/system unified-memory footprint. Routed through the seam
    /// (not read directly by the controller) so the §8 watermark policy can be
    /// exercised against a fake reading in unit tests.
    func footprint() async -> MemoryFootprint
}

public extension InferenceBackend {
    /// Default: speculative decoding unsupported — backends opt in explicitly.
    func loadDraftModel(
        id: String,
        forRole role: ModelRole,
        quantization: QuantizationLevel,
        progressHandler: (@Sendable (Double) -> Void)?
    ) async throws -> LoadedModelHandle {
        throw InferenceError.modelLoadFailed(
            role: role, underlying: "speculative decoding is not supported by this backend")
    }

    func unloadDraftModel(forRole role: ModelRole) async {}

    /// Deterministic estimate (~4 bytes/token) for backends without a tokenizer.
    func countTokens(_ text: String, role: ModelRole) async -> Int {
        InferenceTokenEstimate.estimate(text)
    }
}

/// Shared fallback estimate so the backend default, MLX fallback, and agent-layer
/// default all agree.
public enum InferenceTokenEstimate {
    public static func estimate(_ text: String) -> Int {
        max(1, Int((Double(text.utf8.count) / 4.0).rounded(.up)))
    }
}
