/// A set of directory-scoped ignore rules discovered while traversing a tree
/// (ARCHITECTURE.md §9, nested `.gitignore` support). Pure — no I/O.
///
/// Each scope is anchored at the directory whose ignore file produced it. For a
/// given entry, only scopes whose base is an ancestor (or the entry's own dir)
/// apply, evaluated **shallow → deep** so deeper ignore files override shallower
/// ones (and later patterns within a scope override earlier — see `IgnoreRules`).
/// The filesystem scanner prunes inactive sibling scopes as traversal advances,
/// keeping memory bounded by current traversal depth rather than total ignore
/// files seen.
public struct IgnoreStack: Sendable {

    public struct Scope: Sendable {
        /// The scope's directory, as `/`-path segments relative to the workspace root.
        public let baseSegments: [String]
        public let rules: IgnoreRules
        public init(baseSegments: [String], rules: IgnoreRules) {
            self.baseSegments = baseSegments
            self.rules = rules
        }
    }

    private var scopes: [Scope] = []

    public init() {}

    /// Register a directory's ignore rules. No-op if the rules are empty.
    public mutating func add(_ scope: Scope) {
        guard !scope.rules.isEmpty else { return }
        scopes.append(scope)
    }

    /// Drop scopes that cannot apply to the current path.
    public mutating func prune(for pathSegments: [String]) {
        scopes.removeAll { !Self.isAncestorOrEqual($0.baseSegments, of: pathSegments) }
    }

    /// Whether `pathSegments` (relative to the workspace root) is ignored.
    public func isIgnored(pathSegments: [String], isDirectory: Bool) -> Bool {
        var ignored = false
        for scope in scopes
            .filter({ Self.isAncestorOrEqual($0.baseSegments, of: pathSegments) })
            .sorted(by: { $0.baseSegments.count < $1.baseSegments.count }) {
            let relative = Array(pathSegments.dropFirst(scope.baseSegments.count))
            guard !relative.isEmpty else { continue } // a scope never ignores its own dir
            if let decision = scope.rules.lastDecision(pathSegments: relative, isDirectory: isDirectory) {
                ignored = decision
            }
        }
        return ignored
    }

    private static func isAncestorOrEqual(_ base: [String], of path: [String]) -> Bool {
        guard base.count <= path.count else { return false }
        return Array(path.prefix(base.count)) == base
    }
}
