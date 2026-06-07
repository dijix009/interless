/// Typed failures surfaced by the inference runtime (ARCHITECTURE.md §15).
///
/// These never terminate the host process — they propagate through the token
/// stream (`AsyncThrowingStream`) or are thrown from `loadModel`.
public enum InferenceError: Error, Sendable, Equatable {
    /// `generate` was asked for a role with no loaded model.
    case modelNotLoaded(ModelRole)
    /// The backend failed to load a model (after any retries).
    case modelLoadFailed(role: ModelRole, underlying: String)
    /// The model at `repo` does not match the expected quantization.
    case quantizationMismatch(expected: QuantizationLevel, repo: String)
    /// Inference was refused because memory pressure hit the 95% watermark (§8).
    case memoryPressureRejected(usedFraction: Double)
    /// The consuming task cancelled the stream.
    case cancelled
    /// Generation failed mid-stream for a backend-specific reason.
    case generationFailed(String)
}
