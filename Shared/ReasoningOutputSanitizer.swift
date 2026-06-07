import Foundation

public enum ReasoningOutputSanitizer {
    public static func visibleText(_ text: String, reasoningEffort: ReasoningEffort?) -> String {
        guard let reasoningEffort, reasoningEffort == .none else { return text }
        return stripThinkBlocks(from: text)
    }

    public static func stripThinkBlocks(from text: String) -> String {
        guard !text.isEmpty else { return text }
        var output = ""
        var cursor = text.startIndex

        while let openRange = text.range(
            of: "<think",
            options: [.caseInsensitive],
            range: cursor..<text.endIndex
        ) {
            output += String(text[cursor..<openRange.lowerBound])
            guard let openEnd = text[openRange.lowerBound..<text.endIndex].firstIndex(of: ">") else {
                return normalize(output)
            }

            let contentStart = text.index(after: openEnd)
            guard let closeRange = text.range(
                of: "</think>",
                options: [.caseInsensitive],
                range: contentStart..<text.endIndex
            ) else {
                return normalize(output)
            }

            cursor = closeRange.upperBound
        }

        output += String(text[cursor..<text.endIndex])
        return normalize(output)
    }

    private static func normalize(_ text: String) -> String {
        var value = text
        while value.contains("\n\n\n") {
            value = value.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
