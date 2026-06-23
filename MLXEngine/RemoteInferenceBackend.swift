import Foundation
import Shared
import CloudInference

/// `InferenceBackend` over a hosted `CloudModelClient` (e.g. Anthropic). The
/// lifecycle is intentionally hollow: there are no local weights, KV cache, or
/// GPU/RAM to manage, so `load`/`unload`/`clearKVCache`/draft ops are no-ops and
/// memory readings are zero. `generate` delegates to the client using the model
/// id carried on the handle (provider prefix stripped). Embeddings stay local.
public struct RemoteInferenceBackend: InferenceBackend {
    private let client: any CloudModelClient

    public init(client: any CloudModelClient) {
        self.client = client
    }

    public func load(
        id: String,
        role: ModelRole,
        quantization: QuantizationLevel,
        toolCallFormat: ModelToolCallFormat?,
        progressHandler: (@Sendable (Double) -> Void)?
    ) async throws -> LoadedModelHandle {
        // Nothing to download; surface a missing-key error here so it appears at
        // "load" time rather than mid-generation.
        try await client.validate()
        progressHandler?(1.0)
        return LoadedModelHandle(role: role, id: id, quantization: quantization)
    }

    public func generate(request: GenerationRequest, handle: LoadedModelHandle) -> AsyncThrowingStream<TokenChunk, Error> {
        client.stream(model: Self.modelName(from: handle.id), request: request)
    }

    public func embed(texts: [String], handle: LoadedModelHandle) async throws -> [EmbeddingVector] {
        throw InferenceError.generationFailed("Cloud embeddings are not supported; embeddings run locally.")
    }

    public func unload(role: ModelRole) async {}
    public func clearKVCache(role: ModelRole) async {}
    public func unloadDraftModel(forRole role: ModelRole) async {}

    public func gpuMemory() async -> GPUMemory { GPUMemory() }
    public func footprint() async -> MemoryFootprint {
        MemoryFootprint(processFootprintBytes: 0, totalUnifiedBytes: 0)
    }

    /// `anthropic/claude-opus-4-8` → `claude-opus-4-8`; leaves bare ids unchanged.
    static func modelName(from id: String) -> String {
        CloudModelResolver.resolve(id)?.model ?? id
    }
}
