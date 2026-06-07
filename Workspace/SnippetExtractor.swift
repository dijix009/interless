import Foundation

/// Extracts a short excerpt around the first query-term match in file text
/// (ARCHITECTURE.md §9). Pure. Needed because the contentless FTS5 index cannot
/// produce snippets itself — the index stores no content (§12).
public enum SnippetExtractor {

    /// Returns the first line containing any query term, trimmed and truncated to
    /// `maxChars`, or `nil` if no term is found.
    public static func snippet(from text: String, query: String, maxChars: Int = 160) -> String? {
        let terms = Self.terms(in: query)
        guard !terms.isEmpty else { return nil }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let lowered = line.lowercased()
            guard terms.contains(where: { lowered.contains($0) }) else { continue }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.count <= maxChars { return trimmed }
            return String(trimmed.prefix(maxChars)) + "…"
        }
        return nil
    }

    public static func snippet(
        fileAt url: URL,
        query: String,
        maxReadBytes: Int,
        maxChars: Int = 160
    ) throws -> (snippet: String?, bytesRead: Int) {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let cap = max(0, maxReadBytes)
        let data = try handle.read(upToCount: cap) ?? Data()
        guard !data.prefix(min(data.count, 8192)).contains(0) else {
            return (nil, data.count)
        }
        let text = String(decoding: data, as: UTF8.self)
        return (snippet(from: text, query: query, maxChars: maxChars), data.count)
    }

    private static func terms(in query: String) -> [String] {
        query.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !$0.isEmpty }
    }
}
