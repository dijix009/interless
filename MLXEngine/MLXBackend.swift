import Foundation
import os
import Shared
import MLX
import MLXEmbedders
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import HuggingFace
import Tokenizers

/// The real MLX-backed `InferenceBackend`.
///
/// This is the **only file in the project that imports MLX** (and the Hugging
/// Face download/tokenizer libraries). It owns the loaded `ModelContainer`s and
/// their per-role KV caches, and bridges MLX's `AsyncStream<Generation>` to the
/// project's `AsyncThrowingStream<TokenChunk, Error>`.
///
/// Implemented as an `actor` to serialize access to its `models` dictionary.
public actor MLXBackend: InferenceBackend {

    private struct Loaded {
        let container: ModelContainer
        let handle: LoadedModelHandle
    }

    private struct LoadedEmbedder {
        let container: EmbedderModelContainer
        let handle: LoadedModelHandle
    }

    /// Locked box holding the speculative draft's (non-`Sendable`) `ModelContext`
    /// so it can be used inside the *target* container's `perform` closure. Safe
    /// because the draft is only ever touched during its target's generation,
    /// which the controller's orchestrator gate serializes.
    private final class DraftContextBox: @unchecked Sendable {
        private let lock = NSLock()
        private var context: ModelContext?
        func set(_ newValue: ModelContext?) { lock.withLock { context = newValue } }
        func get() -> ModelContext? { lock.withLock { context } }
    }

    private struct LoadedDraft {
        let container: ModelContainer
        let box: DraftContextBox
        let handle: LoadedModelHandle
    }

    private var models: [ModelRole: Loaded] = [:]
    private var embedders: [ModelRole: LoadedEmbedder] = [:]
    private var drafts: [ModelRole: LoadedDraft] = [:]
    private let engineTuning: EngineTuning
    private var didConfigureMLXMemory = false
    private let log = Logger(subsystem: "dev.interless", category: "inference")

    /// - Parameter engineTuning: profile-resolved tuning. `gpuCacheLimitBytes`
    ///   bounds MLX's buffer-recycle pool so the §8 watermarks read real footprint;
    ///   `gpuMemoryLimitBytes` (when set) is a proactive allocation ceiling that
    ///   throttles before the OS swaps; `embeddingMaxBatchTokens` caps embedding
    ///   sub-batches.
    public init(engineTuning: EngineTuning = .default) {
        self.engineTuning = engineTuning
    }

    // MARK: - InferenceBackend

    public func load(
        id: String,
        role: ModelRole,
        quantization: QuantizationLevel,
        toolCallFormat: ModelToolCallFormat? = nil,
        progressHandler: (@Sendable (Double) -> Void)? = nil
    ) async throws -> LoadedModelHandle {
        try configureMLXMemoryIfNeeded()
        // Validate the requested quantization against what the repo id advertises
        // (§7): a q6 request must not silently load a "…-4bit" repo.
        if let advertisedBits = QuantizationLevel.advertisedBits(inRepoID: id),
           advertisedBits != quantization.bitWidth {
            throw InferenceError.quantizationMismatch(expected: quantization, repo: id)
        }
        let log = self.log
        if role == .embeddings {
            let configuration: ModelConfiguration = id == "nomic_text_v1_5"
                ? EmbedderRegistry.nomic_text_v1_5
                : ModelConfiguration(id: id)
            let container = try await MLX.withError {
                try await EmbedderModelFactory.shared.loadContainer(
                    from: #hubDownloader(),
                    using: #huggingFaceTokenizerLoader(),
                    configuration: configuration,
                    progressHandler: { progress in
                        let fraction = Self.clampedProgress(progress.fractionCompleted)
                        progressHandler?(fraction)
                        log.debug("embedding download \(id, privacy: .public) \(Int(fraction * 100))%")
                    }
                )
            }
            let handle = LoadedModelHandle(role: role, id: id, quantization: quantization)
            embedders[role] = LoadedEmbedder(container: container, handle: handle)
            return handle
        }

        let container = try await MLX.withError {
            try await LLMModelFactory.shared.loadContainer(
                from: #hubDownloader(),
                using: #huggingFaceTokenizerLoader(),
                configuration: ModelConfiguration(
                    id: id,
                    toolCallFormat: toolCallFormat.map(Self.makeToolCallFormat)),
                progressHandler: { progress in
                    let fraction = Self.clampedProgress(progress.fractionCompleted)
                    progressHandler?(fraction)
                    log.debug("download \(id, privacy: .public) \(Int(fraction * 100))%")
                }
            )
        }
        let handle = LoadedModelHandle(role: role, id: id, quantization: quantization)
        models[role] = Loaded(container: container, handle: handle)
        return handle
    }

    public nonisolated func generate(
        request: GenerationRequest,
        handle: LoadedModelHandle
    ) -> AsyncThrowingStream<TokenChunk, Error> {
        AsyncThrowingStream(TokenChunk.self, bufferingPolicy: .unbounded) { continuation in
            // Prioritize token production so background work (indexing, embeddings
            // at .utility) cannot starve the GPU-feeding loop.
            let task = Task(priority: .userInitiated) {
                do {
                    try await self.runGeneration(request, handle: handle, into: continuation)
                } catch is CancellationError {
                    continuation.finish(throwing: InferenceError.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func embed(
        texts: [String],
        handle: LoadedModelHandle
    ) async throws -> [EmbeddingVector] {
        guard let loaded = embedders[handle.role] else {
            throw InferenceError.modelNotLoaded(handle.role)
        }
        let maxBatchTokens = max(256, engineTuning.embeddingMaxBatchTokens)
        return try await MLX.withError {
            await loaded.container.perform { context in
                let tokenizer = context.tokenizer
                let paddingID = tokenizer.eosTokenId ?? 0
                // Encode once, keeping the original index so results scatter back in
                // input order. Sort by length so each sub-batch buckets similar
                // lengths (minimal padding waste).
                let encoded = texts.enumerated()
                    .map { (index: $0.offset, tokens: tokenizer.encode(text: $0.element, addSpecialTokens: true)) }
                    .sorted { $0.tokens.count < $1.tokens.count }
                var results = [EmbeddingVector](repeating: EmbeddingVector([]), count: texts.count)

                var start = 0
                while start < encoded.count {
                    // Greedily grow a sub-batch while padded size (count × maxLen)
                    // stays within the token budget; always allow at least one item.
                    var end = start
                    var maxLength = 0
                    while end < encoded.count {
                        let candidateMax = max(maxLength, encoded[end].tokens.count)
                        let candidateCount = end - start + 1
                        if candidateCount > 1, candidateMax * candidateCount > maxBatchTokens { break }
                        maxLength = candidateMax
                        end += 1
                    }
                    let slice = Array(encoded[start..<end])
                    let padded = stacked(slice.map { item in
                        MLXArray(item.tokens + Array(repeating: paddingID, count: maxLength - item.tokens.count))
                    })
                    let mask = (padded .!= paddingID)
                    let tokenTypes = MLXArray.zeros(like: padded)
                    let output = context.model(
                        padded,
                        positionIds: nil,
                        tokenTypeIds: tokenTypes,
                        attentionMask: mask)
                    let pooled = context.pooling(output, mask: mask, normalize: true, applyLayerNorm: true)
                    pooled.eval() // free this sub-batch's activations before the next
                    let vectors = pooled.map { EmbeddingVector($0.asArray(Float.self)) }
                    for (offset, item) in slice.enumerated() where offset < vectors.count {
                        results[item.index] = vectors[offset]
                    }
                    start = end
                }
                return results
            }
        }
    }

    public func loadDraftModel(
        id: String,
        forRole role: ModelRole,
        quantization: QuantizationLevel,
        progressHandler: (@Sendable (Double) -> Void)? = nil
    ) async throws -> LoadedModelHandle {
        try configureMLXMemoryIfNeeded()
        // The target must be loaded first — the draft is validated against its tokenizer.
        guard let target = models[role] else {
            throw InferenceError.modelNotLoaded(role)
        }
        if let advertisedBits = QuantizationLevel.advertisedBits(inRepoID: id),
           advertisedBits != quantization.bitWidth {
            throw InferenceError.quantizationMismatch(expected: quantization, repo: id)
        }
        let log = self.log
        let container = try await MLX.withError {
            try await LLMModelFactory.shared.loadContainer(
                from: #hubDownloader(),
                using: #huggingFaceTokenizerLoader(),
                configuration: ModelConfiguration(id: id),
                progressHandler: { progress in
                    let fraction = Self.clampedProgress(progress.fractionCompleted)
                    progressHandler?(fraction)
                    log.debug("draft download \(id, privacy: .public) \(Int(fraction * 100))%")
                }
            )
        }
        // Speculative decoding requires identical tokenization: probe both
        // tokenizers with the same string and require identical ids + EOS.
        let probe = "interless speculative probe: func main(_ x: Int) -> [String] { return [\"42\"] }"
        let targetProbe: ([Int], Int?) = await target.container.perform { context in
            (context.tokenizer.encode(text: probe, addSpecialTokens: true), context.tokenizer.eosTokenId)
        }
        let box = DraftContextBox()
        let draftProbe: ([Int], Int?) = await container.perform { context in
            box.set(context)
            return (context.tokenizer.encode(text: probe, addSpecialTokens: true), context.tokenizer.eosTokenId)
        }
        guard targetProbe == draftProbe else {
            throw InferenceError.modelLoadFailed(
                role: role,
                underlying: "draft model \(id) tokenizer does not match the target model "
                    + "(speculative decoding requires identical tokenizers)")
        }
        let handle = LoadedModelHandle(role: role, id: id, quantization: quantization)
        drafts[role] = LoadedDraft(container: container, box: box, handle: handle)
        log.info("loaded draft model \(id, privacy: .public) for role=\(role.rawValue, privacy: .public)")
        return handle
    }

    public func countTokens(_ text: String, role: ModelRole) async -> Int {
        guard let loaded = models[role] else { return InferenceTokenEstimate.estimate(text) }
        return await loaded.container.perform { context in
            context.tokenizer.encode(text: text, addSpecialTokens: false).count
        }
    }

    public func unloadDraftModel(forRole role: ModelRole) async {
        guard drafts[role] != nil else { return }
        drafts[role] = nil
        if didConfigureMLXMemory {
            try? MLX.withError {
                MLX.Memory.clearCache()
            }
        }
        log.info("unloaded draft model for role=\(role.rawValue, privacy: .public)")
    }

    public func unload(role: ModelRole) async {
        models[role] = nil
        embedders[role] = nil
        drafts[role] = nil
        if didConfigureMLXMemory {
            try? MLX.withError {
                MLX.Memory.clearCache()
                // Reset peak so diagnostics/metrics reflect the post-eviction
                // resident set rather than an all-time high across loads.
                MLX.Memory.peakMemory = 0
            }
        }
    }

    public func clearKVCache(role: ModelRole) async {
        // Every generation already starts from a fresh KV cache (see
        // runGeneration), so this action's remaining job is releasing the MLX
        // buffer-recycle pool that grew during generation.
        if didConfigureMLXMemory {
            try? MLX.withError {
                MLX.Memory.clearCache()
            }
        }
    }

    public func gpuMemory() async -> GPUMemory {
        guard didConfigureMLXMemory else { return GPUMemory() }
        return GPUMemory(
            activeBytes: MLX.Memory.activeMemory,
            cacheBytes: MLX.Memory.cacheMemory,
            peakBytes: MLX.Memory.peakMemory
        )
    }

    public func footprint() async -> MemoryFootprint {
        MemoryProbe.footprint()
    }

    // MARK: - Private

    private func configureMLXMemoryIfNeeded() throws {
        guard !didConfigureMLXMemory else { return }
        try MLX.withError {
            // Buffer-recycle pool cap so §8 watermarks read real footprint.
            MLX.Memory.cacheLimit = engineTuning.gpuCacheLimitBytes
            // Proactive allocation ceiling: throttle allocations before the OS
            // swaps (which collapses GPU throughput on unified memory).
            if let limit = engineTuning.gpuMemoryLimitBytes, limit > 0 {
                MLX.Memory.memoryLimit = limit
            }
        }
        didConfigureMLXMemory = true
    }

    private func runGeneration(
        _ request: GenerationRequest,
        handle: LoadedModelHandle,
        into continuation: AsyncThrowingStream<TokenChunk, Error>.Continuation
    ) async throws {
        guard let loaded = models[request.role] else {
            throw InferenceError.modelNotLoaded(request.role)
        }
        let container = loaded.container
        // "Draft loaded" is the speculative-decoding signal — loading is gated by
        // the controller (largeRAM + opt-in + memory watermark), so generation
        // simply uses the draft whenever one is resident.
        let draftBox = drafts[request.role]?.box
        let numDraftTokens = (request.engineTuning ?? .default).speculativeDecoding.numDraftTokens

        // `perform` provides serialized access to the (non-Sendable) ModelContext.
        try await MLX.withError {
            try await container.perform { context in
                let params = Self.makeParameters(from: request)
                let userInput = Self.makeUserInput(from: request)
                let lmInput = try await context.processor.prepare(input: userInput)
                // A fresh KV cache per generation. Cross-request KV reuse is
                // intentionally NOT enabled: the streaming API yields text (not token
                // ids), so the generated tokens left in the cache can't be fingerprinted;
                // correct prompt-prefix reuse would also need cache-trimming back to the
                // prompt length and chat-template-aware prefix validation. Feeding a new
                // full prompt against a stale non-empty cache corrupts attention, so we
                // always start fresh. (`request.reuseKVCache` is reserved for that future
                // prefix-cache feature.)
                let cache = context.model.newCache(parameters: params)

                let stream: AsyncStream<Generation>
                if let draftContext = draftBox?.get() {
                    // Speculative decoding: the draft proposes tokens, the target
                    // verifies. Draft cache is ephemeral (nil → fresh per generation).
                    stream = try MLXLMCommon.generate(
                        input: lmInput, cache: cache, parameters: params, context: context,
                        draftModel: draftContext.model,
                        draftCache: nil,
                        numDraftTokens: numDraftTokens)
                } else {
                    stream = try MLXLMCommon.generate(
                        input: lmInput, cache: cache, parameters: params, context: context)
                }

                var index = 0
                for await item in stream {
                    try Task.checkCancellation()
                    switch item {
                    case .chunk(let text):
                        continuation.yield(TokenChunk(text: text, index: index, isFinal: false))
                        index += 1
                    case .info(let info):
                        continuation.yield(
                            TokenChunk(text: "", index: index, isFinal: true, info: Self.mapInfo(info)))
                        index += 1
                    case .toolCall(let toolCall):
                        continuation.yield(TokenChunk(
                            text: "",
                            index: index,
                            isFinal: false,
                            toolCall: Self.mapToolCall(toolCall)))
                        index += 1
                    }
                }
            }
        }
        continuation.finish()
    }

    // MARK: - Mapping helpers (pure)

    private static func makeParameters(from request: GenerationRequest) -> GenerateParameters {
        let tuning = request.engineTuning ?? .default
        let kv = tuning.kvCachePolicy
        // CRITICAL: `maybeQuantizeKVCache` only converts a `KVCacheSimple`, and
        // `newCache` returns a `RotatingKVCache` whenever `maxKVSize` is set. So
        // `maxKVSize` is set ONLY for `.rotatingWindow`; `.quantized` leaves it nil
        // (→ KVCacheSimple) so `kvBits` actually takes effect after `quantizedKVStart`.
        let maxKVSize: Int? = (kv.strategy == .rotatingWindow) ? request.contextTokenBudget : nil
        let kvBits: Int? = (kv.strategy == .quantized) ? kv.kvBits : nil
        return GenerateParameters(
            maxTokens: request.maxTokens,
            maxKVSize: maxKVSize,
            kvBits: kvBits,
            kvGroupSize: kv.kvGroupSize,
            quantizedKVStart: kv.quantizedKVStart,
            temperature: request.temperature,
            topP: request.topP,
            topK: request.topK ?? 0,
            repetitionPenalty: request.repetitionPenalty,
            prefillStepSize: tuning.prefillStepSize
        )
    }

    private static func makeUserInput(from request: GenerationRequest) -> UserInput {
        let tools = request.tools.isEmpty ? nil : request.tools.map(makeToolSpec)
        switch request.input {
        case .prompt(let text):
            return UserInput(chat: [.user(text)], tools: tools)
        case .messages(let messages):
            let chat: [Chat.Message] = messages.map { message in
                switch message.role {
                case .system: return .system(message.content)
                case .user: return .user(message.content)
                case .assistant: return .assistant(message.content)
                case .tool: return .tool(message.content)
                }
            }
            return UserInput(chat: chat, tools: tools)
        }
    }

    private static func makeToolSpec(_ definition: ToolDefinition) -> [String: any Sendable] {
        guard case let .object(values) = definition.schema else { return [:] }
        return values.mapValues(\.anySendable)
    }

    private nonisolated static func clampedProgress(_ fraction: Double) -> Double {
        guard fraction.isFinite else { return 0 }
        return min(1, max(0, fraction))
    }

    private static func makeToolCallFormat(_ format: ModelToolCallFormat) -> ToolCallFormat {
        switch format {
        case .json: return .json
        case .lfm2: return .lfm2
        case .xmlFunction: return .xmlFunction
        case .glm4: return .glm4
        case .gemma: return .gemma
        case .kimiK2: return .kimiK2
        case .minimaxM2: return .minimaxM2
        case .mistral: return .mistral
        case .llama3: return .llama3
        }
    }

    private static func mapToolCall(_ toolCall: ToolCall) -> ModelToolCall {
        ModelToolCall(
            name: toolCall.function.name,
            arguments: toolCall.function.arguments.mapValues(mapJSONValue))
    }

    private static func mapJSONValue(_ value: MLXLMCommon.JSONValue) -> Shared.JSONValue {
        switch value {
        case .null:
            return .null
        case .bool(let bool):
            return .bool(bool)
        case .int(let int):
            return .int(int)
        case .double(let double):
            return .double(double)
        case .string(let string):
            return .string(string)
        case .array(let values):
            return .array(values.map(mapJSONValue))
        case .object(let values):
            return .object(values.mapValues(mapJSONValue))
        }
    }

    private static func mapInfo(_ info: GenerateCompletionInfo) -> TokenChunk.CompletionInfo {
        TokenChunk.CompletionInfo(
            promptTokenCount: info.promptTokenCount,
            generationTokenCount: info.generationTokenCount,
            promptTime: info.promptTime,
            generateTime: info.generateTime,
            tokensPerSecond: info.tokensPerSecond,
            promptTokensPerSecond: info.promptTokensPerSecond,
            stopReason: String(describing: info.stopReason)
        )
    }
}
