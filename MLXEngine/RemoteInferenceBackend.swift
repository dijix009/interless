import Foundation
import Shared
import CloudInference

/// `InferenceBackend` over one or more hosted `CloudModelClient`s (Anthropic,
/// OpenAI, …), selected per call by the model id's provider prefix. The lifecycle
/// is intentionally hollow: there are no local weights, KV cache, or GPU/RAM to
/// manage, so `load`/`unload`/`clearKVCache`/draft ops are no-ops and memory
/// readings are zero. `generate` delegates to the resolved provider's client
/// using the bare model name. Embeddings stay local (throws here).
public struct RemoteInferenceBackend: InferenceBackend {
    private let clients: [CloudProvider: any CloudModelClient]

    public init(clients: [CloudProvider: any CloudModelClient]) {
        self.clients = clients
    }

    private func resolve(_ id: String) -> (model: String, client: any CloudModelClient)? {
        guard let resolved = CloudModelResolver.resolve(id),
              let client = clients[resolved.provider] else {
            return nil
        }
        return (resolved.model, client)
    }

    public func load(
        id: String,
        role: ModelRole,
        quantization: QuantizationLevel,
        toolCallFormat: ModelToolCallFormat?,
        progressHandler: (@Sendable (Double) -> Void)?
    ) async throws -> LoadedModelHandle {
        guard let (_, client) = resolve(id) else {
            throw InferenceError.modelLoadFailed(role: role, underlying: "no configured cloud provider for model id \"\(id)\"")
        }
        // Nothing to download; surface a missing-key error here so it appears at
        // "load" time rather than mid-generation.
        try await client.validate()
        progressHandler?(1.0)
        return LoadedModelHandle(role: role, id: id, quantization: quantization)
    }

    public func generate(request: GenerationRequest, handle: LoadedModelHandle) -> AsyncThrowingStream<TokenChunk, Error> {
        guard let (model, client) = resolve(handle.id) else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: InferenceError.generationFailed(
                    "no configured cloud provider for model id \"\(handle.id)\""))
            }
        }
        return client.stream(model: model, request: request)
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
}
