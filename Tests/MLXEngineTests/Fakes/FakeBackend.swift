import Shared
import MLXEngine

/// In-memory `InferenceBackend` test double.
///
/// Configurable scripted output, per-token delay, load failures, mid-stream
/// failure, and a simulated memory footprint; records calls for assertions.
/// Conforms to the exact same protocol as the real `MLXBackend`, so the same
/// invariant checks run against both.
actor FakeBackend: InferenceBackend {

    // MARK: Configuration
    private var scriptedTokens: [String] = ["Hello", ", ", "world"]
    private var scriptedChunks: [TokenChunk]?
    private var scriptedEmbeddings: [EmbeddingVector]?
    private var perTokenDelay: Duration = .zero
    private var loadFailuresRemaining: Int = 0
    private var loadDelay: Duration = .zero
    private var failAfterTokens: Int?
    private var footprintFraction: Double = 0.10

    func setScriptedTokens(_ tokens: [String]) { scriptedTokens = tokens }
    func setScriptedChunks(_ chunks: [TokenChunk]) { scriptedChunks = chunks }
    func setScriptedEmbeddings(_ embeddings: [EmbeddingVector]) { scriptedEmbeddings = embeddings }
    func setPerTokenDelay(_ delay: Duration) { perTokenDelay = delay }
    func setLoadFailures(_ count: Int) { loadFailuresRemaining = count }
    func setLoadDelay(_ delay: Duration) { loadDelay = delay }
    func setFailAfterTokens(_ count: Int?) { failAfterTokens = count }
    func setFootprintFraction(_ fraction: Double) { footprintFraction = fraction }

    // MARK: Recorded state
    private(set) var loadCallCount = 0
    private(set) var loadedDraftIDs: [String] = []
    private(set) var unloadedDraftRoles: [ModelRole] = []
    private(set) var unloadedRoles: [ModelRole] = []
    private(set) var clearedKVRoles: [ModelRole] = []
    private(set) var generationCancelled = false
    private(set) var maxConcurrentGenerations = 0
    private(set) var loadToolCallFormats: [ModelRole: ModelToolCallFormat?] = [:]
    private(set) var generationRequests: [GenerationRequest] = []
    private(set) var embeddingInputs: [[String]] = []
    private var activeGenerations = 0

    // MARK: InferenceBackend

    func load(
        id: String,
        role: ModelRole,
        quantization: QuantizationLevel,
        toolCallFormat: ModelToolCallFormat? = nil,
        progressHandler: (@Sendable (Double) -> Void)? = nil
    ) async throws -> LoadedModelHandle {
        loadCallCount += 1
        loadToolCallFormats[role] = toolCallFormat
        if loadFailuresRemaining > 0 {
            loadFailuresRemaining -= 1
            throw InferenceError.modelLoadFailed(role: role, underlying: "fake load failure")
        }
        progressHandler?(0)
        if loadDelay > .zero { try? await Task.sleep(for: loadDelay) }
        progressHandler?(1)
        return LoadedModelHandle(role: role, id: id, quantization: quantization)
    }

    func loadDraftModel(
        id: String,
        forRole role: ModelRole,
        quantization: QuantizationLevel,
        progressHandler: (@Sendable (Double) -> Void)? = nil
    ) async throws -> LoadedModelHandle {
        loadedDraftIDs.append(id)
        return LoadedModelHandle(role: role, id: id, quantization: quantization)
    }

    func unloadDraftModel(forRole role: ModelRole) async {
        unloadedDraftRoles.append(role)
    }

    nonisolated func generate(
        request: GenerationRequest,
        handle: LoadedModelHandle
    ) -> AsyncThrowingStream<TokenChunk, Error> {
        AsyncThrowingStream(TokenChunk.self, bufferingPolicy: .unbounded) { continuation in
            let task = Task { await self.produce(request: request, into: continuation) }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func unload(role: ModelRole) async { unloadedRoles.append(role) }
    func clearKVCache(role: ModelRole) async { clearedKVRoles.append(role) }
    func gpuMemory() async -> GPUMemory { GPUMemory() }

    func embed(texts: [String], handle: LoadedModelHandle) async throws -> [EmbeddingVector] {
        embeddingInputs.append(texts)
        if let scriptedEmbeddings {
            return Array(scriptedEmbeddings.prefix(texts.count))
        }
        return texts.enumerated().map { index, text in
            let seed = Float(text.utf8.reduce(index + 1) { ($0 &* 31) &+ Int($1) } % 997)
            return EmbeddingVector([seed, seed + 1, seed + 2])
        }
    }

    func footprint() async -> MemoryFootprint {
        let total = 1_000_000
        return MemoryFootprint(
            processFootprintBytes: Int(footprintFraction * Double(total)),
            totalUnifiedBytes: total
        )
    }

    // MARK: Producer

    private func produce(
        request: GenerationRequest,
        into continuation: AsyncThrowingStream<TokenChunk, Error>.Continuation
    ) async {
        generationRequests.append(request)
        activeGenerations += 1
        maxConcurrentGenerations = max(maxConcurrentGenerations, activeGenerations)
        defer { activeGenerations -= 1 }

        if let chunks = scriptedChunks {
            for chunk in chunks {
                if Task.isCancelled {
                    generationCancelled = true
                    continuation.finish(throwing: InferenceError.cancelled)
                    return
                }
                continuation.yield(chunk)
            }
            continuation.finish()
            return
        }

        let tokens = scriptedTokens
        let delay = perTokenDelay
        let failAfter = failAfterTokens

        var index = 0
        for text in tokens {
            if Task.isCancelled {
                generationCancelled = true
                continuation.finish(throwing: InferenceError.cancelled)
                return
            }
            if let failAfter, index >= failAfter {
                continuation.finish(throwing: InferenceError.generationFailed("fake mid-stream failure after \(failAfter) tokens"))
                return
            }
            if delay > .zero {
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    generationCancelled = true
                    continuation.finish(throwing: InferenceError.cancelled)
                    return
                }
            }
            continuation.yield(TokenChunk(text: text, index: index, isFinal: false))
            index += 1
        }
        continuation.yield(TokenChunk(
            text: "", index: index, isFinal: true,
            info: TokenChunk.CompletionInfo(generationTokenCount: tokens.count, tokensPerSecond: 99)))
        continuation.finish()
    }
}
