/// The compiled ignore patterns from one directory's ignore files (ARCHITECTURE.md
/// §9). Pure — no I/O. Patterns are evaluated in order with **last-match-wins**
/// (a later `!negation` re-includes).
public struct IgnoreRules: Sendable, Equatable {
    public let patterns: [GitignorePattern]

    public init(patterns: [GitignorePattern]) { self.patterns = patterns }

    public var isEmpty: Bool { patterns.isEmpty }

    /// Parse one or more ignore-file texts (e.g. `.gitignore` then `.opencodeignore`),
    /// concatenated in order. Lines are split on `\n`.
    public static func parse(_ fileContents: [String]) -> IgnoreRules {
        let lines = fileContents.flatMap {
            $0.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        }
        return IgnoreRules(patterns: lines.compactMap(GitignorePattern.init(line:)))
    }

    /// The ignore decision (true = ignored) from the **last** matching pattern, or
    /// `nil` if no pattern in this scope matches `pathSegments`.
    public func lastDecision(pathSegments: [String], isDirectory: Bool) -> Bool? {
        var decision: Bool?
        for pattern in patterns
        where pattern.matches(pathSegments: pathSegments, isDirectory: isDirectory) {
            decision = !pattern.negated
        }
        return decision
    }
}
