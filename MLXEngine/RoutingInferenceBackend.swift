import Foundation
import Shared
import CloudInference

/// Dispatches each backend call to the local MLX backend or a hosted (cloud)
/// backend, decided by the model id: a `provider/model` id (e.g.
/// `anthropic/claude-opus-4-8`) routes to `remote`; everything else (bare ids,
/// Hugging Face repo ids) routes to `local`. This is how a role becomes local or
/// cloud — `InferenceController` and the agents are unchanged.
///
/// No mutable routing table is needed: `load`/`generate`/`embed` route by id (the
/// handle carries it), and role-keyed calls forward to both sub-backends (the one
/// that never loaded the role is a harmless no-op).
public struct RoutingInferenceBackend: InferenceBackend {
    private let local: any InferenceBackend
    private let remote: any InferenceBackend

    public init(local: any InferenceBackend, remote: any InferenceBackend) {
        self.local = local
        self.remote = remote
    }

    private func backend(for id: String) -> any InferenceBackend {
        CloudModelResolver.isCloud(id) ? remote : local
    }

    public func load(
        id: String,
        role: ModelRole,
        quantization: QuantizationLevel,
        toolCallFormat: ModelToolCallFormat?,
        progressHandler: (@Sendable (Double) -> Void)?
    ) async throws -> LoadedModelHandle {
        try await backend(for: id).load(
            id: id, role: role, quantization: quantization,
            toolCallFormat: toolCallFormat, progressHandler: progressHandler)
    }

    public func generate(request: GenerationRequest, handle: LoadedModelHandle) -> AsyncThrowingStream<TokenChunk, Error> {
        backend(for: handle.id).generate(request: request, handle: handle)
    }

    public func embed(texts: [String], handle: LoadedModelHandle) async throws -> [EmbeddingVector] {
        try await backend(for: handle.id).embed(texts: texts, handle: handle)
    }

    public func unload(role: ModelRole) async {
        await local.unload(role: role)
        await remote.unload(role: role)
    }

    public func clearKVCache(role: ModelRole) async {
        await local.clearKVCache(role: role)
        await remote.clearKVCache(role: role)
    }

    public func loadDraftModel(
        id: String,
        forRole role: ModelRole,
        quantization: QuantizationLevel,
        progressHandler: (@Sendable (Double) -> Void)?
    ) async throws -> LoadedModelHandle {
        // Speculative drafting is an MLX-only feature; always local.
        try await local.loadDraftModel(
            id: id, forRole: role, quantization: quantization, progressHandler: progressHandler)
    }

    public func unloadDraftModel(forRole role: ModelRole) async {
        await local.unloadDraftModel(forRole: role)
    }

    public func countTokens(_ text: String, role: ModelRole) async -> Int {
        // Local gives a tokenizer-true count for local roles and a deterministic
        // estimate when the role has no local model (i.e. a cloud role) — exactly
        // what context fitting needs in both cases.
        await local.countTokens(text, role: role)
    }

    public func gpuMemory() async -> GPUMemory { await local.gpuMemory() }
    public func footprint() async -> MemoryFootprint { await local.footprint() }
}
