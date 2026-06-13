import Foundation
import Tooling

public enum CodeModeFinalAnswerSanitizer {
    public static func sanitize(
        _ text: String,
        fileChanges: [ToolFileChange],
        minimumFenceCharacters: Int = 600
    ) -> String {
        guard !fileChanges.isEmpty, text.contains("```") || text.contains("~~~") else {
            return trimTrailingWhitespace(text)
        }
        let paths = fileChanges.map(\.path).filter { !$0.isEmpty }
        guard !paths.isEmpty else { return trimTrailingWhitespace(text) }
        let reference = writtenReference(paths: paths)
        let replaced = replaceLargeFencedBlocks(
            in: text,
            minimumFenceCharacters: minimumFenceCharacters,
            replacement: reference)
        return trimTrailingWhitespace(replaced)
    }

    private static func replaceLargeFencedBlocks(
        in text: String,
        minimumFenceCharacters: Int,
        replacement: String
    ) -> String {
        var output = ""
        var cursor = text.startIndex
        while let fence = nextFence(in: text, from: cursor) {
            output += text[cursor..<fence.range.lowerBound]
            guard let endRange = closingFence(in: text, from: fence.contentStart, marker: fence.marker) else {
                output += text[fence.range.lowerBound...]
                return output
            }
            let body = text[fence.contentStart..<endRange.lowerBound]
            if body.utf8.count >= minimumFenceCharacters {
                output += replacement
            } else {
                output += text[fence.range.lowerBound..<endRange.upperBound]
            }
            cursor = endRange.upperBound
        }
        output += text[cursor...]
        return output
    }

    private static func nextFence(
        in text: String,
        from start: String.Index
    ) -> (range: Range<String.Index>, marker: String, contentStart: String.Index)? {
        let candidates = ["```", "~~~"].compactMap { marker -> (Range<String.Index>, String)? in
            guard let range = text.range(of: marker, range: start..<text.endIndex) else { return nil }
            return (range, marker)
        }
        guard let first = candidates.min(by: { $0.0.lowerBound < $1.0.lowerBound }) else { return nil }
        let lineEnd = text[first.0.upperBound...].firstIndex(of: "\n") ?? text.endIndex
        let contentStart = lineEnd == text.endIndex ? lineEnd : text.index(after: lineEnd)
        return (first.0, first.1, contentStart)
    }

    private static func closingFence(
        in text: String,
        from start: String.Index,
        marker: String
    ) -> Range<String.Index>? {
        var cursor = start
        while cursor < text.endIndex {
            guard let range = text.range(of: marker, range: cursor..<text.endIndex) else { return nil }
            let lineStart = text[..<range.lowerBound].lastIndex(of: "\n").map { text.index(after: $0) } ?? text.startIndex
            let linePrefix = text[lineStart..<range.lowerBound]
            let newlineIndex = text[range.upperBound...].firstIndex(of: "\n")
            let lineSuffix = text[range.upperBound..<(newlineIndex ?? text.endIndex)]
            // Closing fence must be bare on its own line; a marker with an info
            // string (an inner ```lang) is content, so nested fences don't truncate.
            if linePrefix.trimmingCharacters(in: .whitespaces).isEmpty,
               lineSuffix.trimmingCharacters(in: .whitespaces).isEmpty {
                let lineEnd = newlineIndex.map { text.index(after: $0) } ?? range.upperBound
                return range.lowerBound..<lineEnd
            }
            cursor = range.upperBound
        }
        return nil
    }

    private static func writtenReference(paths: [String]) -> String {
        if paths.count == 1, let path = paths.first {
            return "Full generated content was written to `\(path)`."
        }
        let list = paths
            .prefix(8)
            .map { "- `\($0)`" }
            .joined(separator: "\n")
        return "Full generated content was written to:\n\(list)"
    }

    private static func trimTrailingWhitespace(_ text: String) -> String {
        var end = text.endIndex
        while end > text.startIndex {
            let previous = text.index(before: end)
            guard text[previous].isWhitespace else { break }
            end = previous
        }
        return String(text[..<end])
    }
}
