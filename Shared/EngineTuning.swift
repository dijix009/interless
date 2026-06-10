import Foundation

/// How the per-role KV cache is managed during generation (ARCHITECTURE.md §8).
///
/// `MLXEngine` maps this to MLX cache types. Critical upstream constraint
/// (mlx-swift-lm 3.31.3): `maybeQuantizeKVCache` only converts a `KVCacheSimple`,
/// and `LanguageModel.newCache` returns a `RotatingKVCache` whenever
/// `GenerateParameters.maxKVSize` is set. Therefore `.quantized` must **not** set
/// `maxKVSize` (otherwise quantization silently no-ops), while `.rotatingWindow`
/// relies on it.
public enum KVCacheStrategy: String, Sendable, Equatable, Codable, CaseIterable {
    /// Bound memory with a sliding `RotatingKVCache(maxSize:)`; full precision.
    case rotatingWindow
    /// Grow a `KVCacheSimple`, then quantize it (4/8-bit) once it exceeds
    /// `quantizedKVStart` tokens. Lowest bytes/token; gives up the hard window.
    case quantized
    /// Unbounded full-precision `KVCacheSimple` (largeRAM, short contexts).
    case simpleUnbounded
}

/// KV-cache policy resolved from the active resource profile.
public struct KVCachePolicy: Sendable, Equatable, Codable {
    public var strategy: KVCacheStrategy
    /// Quantization bit-width (4 or 8) for `.quantized`; `nil` disables quantization.
    public var kvBits: Int?
    /// Quantization group size (MLX default 64).
    public var kvGroupSize: Int
    /// Keep the first N tokens full-precision before quantizing (`.quantized`).
    public var quantizedKVStart: Int

    public init(
        strategy: KVCacheStrategy = .rotatingWindow,
        kvBits: Int? = nil,
        kvGroupSize: Int = 64,
        quantizedKVStart: Int = 0
    ) {
        self.strategy = strategy
        self.kvBits = kvBits
        self.kvGroupSize = max(1, kvGroupSize)
        self.quantizedKVStart = max(0, quantizedKVStart)
    }

    public static let `default` = KVCachePolicy()
}

/// Speculative-decoding policy (opt-in; large-RAM only). A small *draft* model
/// proposes tokens that the larger orchestrator verifies, raising decode
/// throughput at the cost of an extra resident model. Both models must share a
/// tokenizer; `MLXEngine` validates this at draft-load time and disables on
/// mismatch.
public struct SpeculativeDecodingPolicy: Sendable, Equatable, Codable {
    public var isEnabled: Bool
    public var draftModelID: String?
    public var draftQuantization: QuantizationLevel
    public var numDraftTokens: Int

    public init(
        isEnabled: Bool = false,
        draftModelID: String? = nil,
        draftQuantization: QuantizationLevel = .q4,
        numDraftTokens: Int = 2
    ) {
        self.isEnabled = isEnabled
        self.draftModelID = draftModelID
        self.draftQuantization = draftQuantization
        self.numDraftTokens = max(1, numDraftTokens)
    }

    public static let disabled = SpeculativeDecodingPolicy()
}

/// MLX-free engine performance/memory tuning, resolved from a `ResourceProfile`
/// and mapped onto MLX `GenerateParameters` + `MLX.Memory` limits inside
/// `MLXEngine`. Lives in `Shared` so the budget/profile layer can own it without
/// importing MLX.
public struct EngineTuning: Sendable, Equatable, Codable {
    public var kvCachePolicy: KVCachePolicy
    /// Prompt prefill chunk size (tokens) — bounds prefill peak memory + tunes speed.
    public var prefillStepSize: Int
    /// Proactive `MLX.Memory.memoryLimit` ceiling in bytes; `nil` = leave MLX default.
    public var gpuMemoryLimitBytes: Int?
    /// `MLX.Memory.cacheLimit` (buffer-recycle pool) in bytes.
    public var gpuCacheLimitBytes: Int
    /// Target token budget per embedding sub-batch (bounds peak activation).
    public var embeddingMaxBatchTokens: Int
    public var speculativeDecoding: SpeculativeDecodingPolicy

    public init(
        kvCachePolicy: KVCachePolicy = .default,
        prefillStepSize: Int = 512,
        gpuMemoryLimitBytes: Int? = nil,
        gpuCacheLimitBytes: Int = 256 * 1024 * 1024,
        embeddingMaxBatchTokens: Int = 8_192,
        speculativeDecoding: SpeculativeDecodingPolicy = .disabled
    ) {
        self.kvCachePolicy = kvCachePolicy
        self.prefillStepSize = max(1, prefillStepSize)
        self.gpuMemoryLimitBytes = gpuMemoryLimitBytes.map { max(0, $0) }
        self.gpuCacheLimitBytes = max(0, gpuCacheLimitBytes)
        self.embeddingMaxBatchTokens = max(256, embeddingMaxBatchTokens)
        self.speculativeDecoding = speculativeDecoding
    }

    public static let `default` = EngineTuning()

    /// A proactive GPU memory limit as a fraction of unified memory, with a floor
    /// so small machines still get a workable ceiling.
    public static func gpuMemoryLimit(fraction: Double, physicalMemoryBytes: Int) -> Int {
        let raw = Double(physicalMemoryBytes) * fraction
        return max(512 * 1024 * 1024, Int(raw.isFinite ? raw : 0))
    }
}
