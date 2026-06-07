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

    /// Current MLX GPU allocator counters (active / cache / peak bytes).
    func gpuMemory() async -> GPUMemory

    /// Current process/system unified-memory footprint. Routed through the seam
    /// (not read directly by the controller) so the §8 watermark policy can be
    /// exercised against a fake reading in unit tests.
    func footprint() async -> MemoryFootprint
}
