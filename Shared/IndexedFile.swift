/// Payload upserted into the workspace index (ARCHITECTURE.md §9, §12).
public struct IndexedFile: Sendable, Equatable, Codable {
    public var relativePath: String
    public var sizeBytes: Int
    public var modifiedAtEpoch: Int
    public var contentHash: String
    /// UTF-8 (lossy) text to index; `nil` for binary/oversized files (still indexed
    /// by filename). The text is tokenized into the FTS5 index and **not** stored
    /// verbatim (§12 — the index is contentless).
    public var content: String?
    /// Structured names extracted from source. Only names/kinds/locations are
    /// persisted outside FTS; source text is not stored.
    public var symbols: [CodeSymbol]
    /// Comment text tokens for FTS indexing. These are tokenized into contentless
    /// FTS only and are not persisted as reconstructable text.
    public var comments: [String]
    /// Lightweight references extracted from source. Names/kinds/locations only.
    public var references: [CodeReference]

    public init(
        relativePath: String,
        sizeBytes: Int,
        modifiedAtEpoch: Int,
        contentHash: String,
        content: String?,
        symbols: [CodeSymbol] = [],
        comments: [String] = [],
        references: [CodeReference] = []
    ) {
        self.relativePath = relativePath
        self.sizeBytes = sizeBytes
        self.modifiedAtEpoch = modifiedAtEpoch
        self.contentHash = contentHash
        self.content = content
        self.symbols = symbols
        self.comments = comments
        self.references = references
    }

    /// The basename (last `/`-separated component), weighted higher in ranking.
    public var fileName: String {
        relativePath.split(separator: "/").last.map(String.init) ?? relativePath
    }
}

/// A structured code symbol discovered during workspace indexing.
public struct CodeSymbol: Sendable, Equatable, Codable, Hashable {
    public var name: String
    public var kind: String
    public var line: Int
    public var column: Int

    public init(name: String, kind: String, line: Int, column: Int) {
        self.name = name
        self.kind = kind
        self.line = line
        self.column = column
    }
}

/// A lightweight semantic reference discovered during workspace indexing.
public struct CodeReference: Sendable, Equatable, Codable, Hashable {
    public var name: String
    public var kind: String
    public var line: Int
    public var column: Int

    public init(name: String, kind: String, line: Int, column: Int) {
        self.name = name
        self.kind = kind
        self.line = line
        self.column = column
    }
}
