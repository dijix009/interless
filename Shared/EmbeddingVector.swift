public struct EmbeddingVector: Sendable, Equatable, Codable {
    public var values: [Float]

    public init(_ values: [Float]) {
        self.values = Self.normalized(values)
    }

    public var isEmpty: Bool { values.isEmpty }
    public var dimensions: Int { values.count }

    public static func normalized(_ values: [Float]) -> [Float] {
        let magnitude = values.reduce(Float(0)) { $0 + ($1 * $1) }.squareRoot()
        guard magnitude > 0 else { return values }
        return values.map { $0 / magnitude }
    }

    public func cosineSimilarity(to other: EmbeddingVector) -> Double {
        guard values.count == other.values.count, !values.isEmpty else { return 0 }
        let dot = zip(values, other.values).reduce(Float(0)) { $0 + ($1.0 * $1.1) }
        return Double(dot)
    }
}
