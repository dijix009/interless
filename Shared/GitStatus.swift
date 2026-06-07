/// A point-in-time git snapshot of a workspace (ARCHITECTURE.md §9, "repository
/// metadata extraction"). For a non-repository, `isRepository` is false and the
/// rest is empty/nil.
public struct GitStatus: Sendable, Equatable, Codable {
    public struct Entry: Sendable, Equatable, Codable {
        public var path: String
        /// Two-character porcelain status code, e.g. `" M"`, `"??"`, `"A "`.
        public var xy: String
        public init(path: String, xy: String) {
            self.path = path
            self.xy = xy
        }
    }

    public var isRepository: Bool
    public var branch: String?     // nil ⇒ detached HEAD or no commits
    public var headSHA: String?
    public var entries: [Entry]

    public init(isRepository: Bool, branch: String? = nil, headSHA: String? = nil, entries: [Entry] = []) {
        self.isRepository = isRepository
        self.branch = branch
        self.headSHA = headSHA
        self.entries = entries
    }

    public static let notARepository = GitStatus(isRepository: false)
}
