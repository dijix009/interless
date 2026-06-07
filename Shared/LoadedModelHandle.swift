/// An opaque, MLX-free reference to a model that has been loaded into the
/// backend. Held by `InferenceController` so the controller never touches MLX
/// types directly (the concrete model objects live behind the backend seam).
public struct LoadedModelHandle: Sendable, Hashable, Codable {
    /// The role this loaded model serves.
    public let role: ModelRole
    /// The model identifier (e.g. a Hugging Face repo id).
    public let id: String
    /// The quantization the model was loaded at.
    public let quantization: QuantizationLevel

    public init(role: ModelRole, id: String, quantization: QuantizationLevel) {
        self.role = role
        self.id = id
        self.quantization = quantization
    }
}
