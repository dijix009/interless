import Foundation

public struct CodeModeGeneratedFileCandidate: Sendable, Equatable {
    public var path: String
    public var contents: String

    public init(path: String, contents: String) {
        self.path = path
        self.contents = contents
    }
}

public enum CodeModeGeneratedFileFallback {
    public static func candidate(
        prompt: String,
        assistantText: String,
        selectedPath: String?,
        fileTreePaths: [String] = []
    ) -> CodeModeGeneratedFileCandidate? {
        guard looksLikeFileMutationRequest(prompt) else { return nil }
        guard let block = fencedCodeBlocks(in: assistantText)
            .filter({ !$0.contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            .max(by: { $0.contents.utf8.count < $1.contents.utf8.count }) else {
            return nil
        }
        let stripped = stripLeadingFilenameComment(from: block.contents)
        let contents = stripped.contents.trimmingCharacters(in: .whitespacesAndNewlines)
        guard contents.utf8.count >= 80 else { return nil }

        let path = stripped.path
            ?? explicitPath(in: prompt)
            ?? explicitPath(in: block.info)
            ?? selectedEditTarget(prompt: prompt, selectedPath: selectedPath, fileTreePaths: fileTreePaths)
            ?? inferredStandalonePath(prompt: prompt, language: block.language)
        guard let path = normalizedRelativePath(path) else { return nil }
        return CodeModeGeneratedFileCandidate(path: path, contents: contents + "\n")
    }

    private struct FencedBlock {
        var info: String
        var language: String?
        var contents: String
    }

    private static let supportedExtensions: Set<String> = [
        "bash", "c", "cc", "cpp", "css", "go", "h", "hpp", "html", "htm",
        "java", "js", "json", "jsx", "kt", "m", "md", "mm", "php", "py",
        "rb", "rs", "sh", "sql", "swift", "toml", "ts", "tsx", "vue", "xml",
        "yaml", "yml", "zsh"
    ]

    private static func looksLikeFileMutationRequest(_ prompt: String) -> Bool {
        let lower = prompt.lowercased()
        let mutationWords = ["create", "make", "write", "generate", "add", "save", "implement", "edit", "update"]
        let fileWords = [" file", " script", " page", " component", ".html", ".js", ".ts", ".swift", ".py", ".css", ".json", ".md"]
        return mutationWords.contains { lower.contains($0) } && fileWords.contains { lower.contains($0) }
    }

    private static func fencedCodeBlocks(in text: String) -> [FencedBlock] {
        var blocks: [FencedBlock] = []
        var cursor = text.startIndex
        while let fence = nextFence(in: text, from: cursor) {
            guard let closing = closingFence(in: text, from: fence.contentStart, marker: fence.marker) else { break }
            let contents = String(text[fence.contentStart..<closing.lowerBound])
            let language = fence.info
                .split(whereSeparator: \.isWhitespace)
                .first
                .map(String.init)?
                .lowercased()
            blocks.append(FencedBlock(info: fence.info, language: language, contents: contents))
            cursor = closing.upperBound
        }
        return blocks
    }

    private static func nextFence(
        in text: String,
        from start: String.Index
    ) -> (marker: String, info: String, contentStart: String.Index)? {
        let candidates = ["```", "~~~"].compactMap { marker -> (Range<String.Index>, String)? in
            guard let range = text.range(of: marker, range: start..<text.endIndex) else { return nil }
            return (range, marker)
        }
        guard let first = candidates.min(by: { $0.0.lowerBound < $1.0.lowerBound }) else { return nil }
        let lineEnd = text[first.0.upperBound...].firstIndex(of: "\n") ?? text.endIndex
        let info = String(text[first.0.upperBound..<lineEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
        let contentStart = lineEnd == text.endIndex ? lineEnd : text.index(after: lineEnd)
        return (first.1, info, contentStart)
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
            let prefix = text[lineStart..<range.lowerBound]
            if prefix.trimmingCharacters(in: .whitespaces).isEmpty {
                let lineEnd = text[range.upperBound...].firstIndex(of: "\n").map { text.index(after: $0) } ?? range.upperBound
                return range.lowerBound..<lineEnd
            }
            cursor = range.upperBound
        }
        return nil
    }

    private static func stripLeadingFilenameComment(from contents: String) -> (path: String?, contents: String) {
        guard let lineEnd = contents.firstIndex(of: "\n") else { return (nil, contents) }
        let firstLine = String(contents[..<lineEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
        let isFilenameComment = firstLine.hasPrefix("<!--")
            || firstLine.hasPrefix("//")
            || firstLine.hasPrefix("#")
            || firstLine.hasPrefix("/*")
        guard isFilenameComment, let path = explicitPath(in: firstLine) else {
            return (nil, contents)
        }
        return (path, String(contents[contents.index(after: lineEnd)...]))
    }

    private static func explicitPath(in text: String) -> String? {
        let extensions = supportedExtensions
            .sorted { lhs, rhs in
                if lhs.count == rhs.count { return lhs < rhs }
                return lhs.count > rhs.count
            }
            .joined(separator: "|")
        let pattern = #"(?i)(?:[A-Za-z0-9_-]+/)*[A-Za-z0-9_-][A-Za-z0-9_.-]*\.(?:\#(extensions))"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: nsRange),
              let range = Range(match.range, in: text) else {
            return nil
        }
        return String(text[range])
    }

    private static func selectedEditTarget(
        prompt: String,
        selectedPath: String?,
        fileTreePaths: [String]
    ) -> String? {
        guard let selectedPath = selectedPath,
              looksLikeEditRequest(prompt),
              fileTreePaths.contains(selectedPath) || selectedPath.contains(".") else {
            return nil
        }
        return selectedPath
    }

    private static func looksLikeEditRequest(_ prompt: String) -> Bool {
        let lower = prompt.lowercased()
        return ["edit", "update", "change", "modify", "fix"].contains { lower.contains($0) }
    }

    private static func inferredStandalonePath(prompt: String, language: String?) -> String? {
        guard let ext = extensionFor(language: language, prompt: prompt) else { return nil }
        let base = inferredBaseName(prompt: prompt)
        return "\(base).\(ext)"
    }

    private static func extensionFor(language: String?, prompt: String) -> String? {
        if let language {
            switch language {
            case "html", "htm": return "html"
            case "javascript": return "js"
            case "typescript": return "ts"
            case "shell", "bash", "zsh": return "sh"
            case "python": return "py"
            case "markdown": return "md"
            default:
                if supportedExtensions.contains(language) { return language }
            }
        }
        if let path = explicitPath(in: prompt),
           let ext = path.split(separator: ".").last {
            return String(ext).lowercased()
        }
        let lower = prompt.lowercased()
        for ext in supportedExtensions.sorted(by: { $0.count > $1.count }) where lower.contains(".\(ext)") {
            return ext == "htm" ? "html" : ext
        }
        return nil
    }

    private static func inferredBaseName(prompt: String) -> String {
        let lower = prompt.lowercased()
        if lower.contains("temp") || lower.contains("celsius") || lower.contains("fahrenheit") || lower.contains("kelvin") {
            if lower.contains("convert") || lower.contains("converter") {
                return "temperature-converter"
            }
            return "temperature"
        }
        let stopWords: Set<String> = [
            "a", "an", "and", "app", "can", "code", "create", "file", "for", "generate",
            "i", "in", "it", "make", "me", "new", "of", "page", "please", "save",
            "script", "simple", "that", "the", "this", "to", "with", "write", "you"
        ]
        let words = lower
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count > 1 && !stopWords.contains($0) && !supportedExtensions.contains($0) }
        let selected = words.prefix(4)
        return selected.isEmpty ? "generated-file" : selected.joined(separator: "-")
    }

    private static func normalizedRelativePath(_ path: String?) -> String? {
        guard var path = path?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else {
            return nil
        }
        path = path.trimmingCharacters(in: CharacterSet(charactersIn: "`'\""))
        while path.hasPrefix("./") { path.removeFirst(2) }
        guard !path.hasPrefix("/"),
              !path.hasPrefix("~"),
              !path.contains(".."),
              !path.contains("\n"),
              !path.contains("\r"),
              !path.hasSuffix("/") else {
            return nil
        }
        return path
    }
}
