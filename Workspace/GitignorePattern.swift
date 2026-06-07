/// A single compiled `.gitignore` pattern (ARCHITECTURE.md §9). Pure — no I/O.
///
/// Matching is segment-wise (not regex): `*`/`?` never cross `/`, and `**`
/// matches zero or more whole path segments. See `Workspace`'s docs for the
/// explicitly-supported subset.
public struct GitignorePattern: Sendable, Equatable {

    public enum Token: Sendable, Equatable {
        case literal(Character)
        case anyRun   // *  — zero or more non-'/' characters
        case anyChar  // ?  — exactly one non-'/' character
    }

    public enum Segment: Sendable, Equatable {
        case doubleStar          // **
        case glob([Token])       // a single path segment (never contains '/')
    }

    public let negated: Bool
    public let directoryOnly: Bool
    public let anchored: Bool
    public let segments: [Segment]

    /// Parse one line of an ignore file. Returns `nil` for blank lines and comments.
    public init?(line rawLine: String) {
        var s = rawLine
        // Strip CR and trailing whitespace (escaped trailing space is out of scope).
        while s.hasSuffix("\r") || s.hasSuffix(" ") || s.hasSuffix("\t") { s.removeLast() }
        if s.isEmpty || s.hasPrefix("#") { return nil }
        if s.hasPrefix("\\#") { s.removeFirst() } // \# → literal '#'

        var negated = false
        if s.hasPrefix("!") { negated = true; s.removeFirst() }
        if s.isEmpty { return nil }

        var directoryOnly = false
        if s.hasSuffix("/") { directoryOnly = true; s.removeLast() }
        if s.isEmpty { return nil }

        // A '/' anywhere but the (already-removed) trailing slash anchors the
        // pattern to the ignore file's directory; otherwise it matches by basename.
        var anchored = false
        if s.hasPrefix("/") { anchored = true; s.removeFirst() }
        else if s.contains("/") { anchored = true }
        if s.isEmpty { return nil }

        let parts = s.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        self.segments = parts.map { $0 == "**" ? .doubleStar : .glob(Self.tokenize($0)) }
        self.negated = negated
        self.directoryOnly = directoryOnly
        self.anchored = anchored
    }

    private static func tokenize(_ part: String) -> [Token] {
        part.map { ch in
            switch ch {
            case "*": .anyRun
            case "?": .anyChar
            default: .literal(ch)
            }
        }
    }

    /// Does this pattern match `pathSegments` (relative to the ignore file's dir)?
    public func matches(pathSegments: [String], isDirectory: Bool) -> Bool {
        if directoryOnly && !isDirectory { return false }
        // Unanchored patterns match at any depth — equivalent to a leading `**/`.
        let pat = anchored ? segments : [.doubleStar] + segments
        return Self.segmentMatch(pat, pathSegments, pi: 0, si: 0)
    }

    /// Convenience for tests: split a `/`-path string and match.
    public func matches(relativePath: String, isDirectory: Bool) -> Bool {
        matches(pathSegments: relativePath.split(separator: "/").map(String.init),
                isDirectory: isDirectory)
    }

    private static func segmentMatch(_ pat: [Segment], _ path: [String], pi: Int, si: Int) -> Bool {
        var pi = pi
        var si = si
        while pi < pat.count {
            switch pat[pi] {
            case .doubleStar:
                if pi + 1 == pat.count { return true }  // trailing ** matches the rest (incl. none)
                for k in si...path.count where segmentMatch(pat, path, pi: pi + 1, si: k) {
                    return true
                }
                return false
            case .glob(let tokens):
                if si >= path.count { return false }
                if !globMatch(tokens, Array(path[si]), ti: 0, ci: 0) { return false }
                pi += 1
                si += 1
            }
        }
        return si == path.count
    }

    private static func globMatch(_ tokens: [Token], _ chars: [Character], ti: Int, ci: Int) -> Bool {
        var ti = ti
        var ci = ci
        while ti < tokens.count {
            switch tokens[ti] {
            case .literal(let c):
                if ci >= chars.count || chars[ci] != c { return false }
                ti += 1; ci += 1
            case .anyChar:
                if ci >= chars.count { return false }
                ti += 1; ci += 1
            case .anyRun:
                if ti + 1 == tokens.count { return true } // trailing * matches the rest
                for k in ci...chars.count where globMatch(tokens, chars, ti: ti + 1, ci: k) {
                    return true
                }
                return false
            }
        }
        return ci == chars.count
    }
}
