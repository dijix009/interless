import Foundation
import UI

public enum SafeFilePreviewError: Error, Sendable, Equatable, CustomStringConvertible {
    case emptyPath
    case pathEscapesWorkspace(String)
    case notARegularFile(String)

    public var description: String {
        switch self {
        case .emptyPath:
            return "No file path was provided."
        case .pathEscapesWorkspace(let path):
            return "Path escapes the workspace: \(path)"
        case .notARegularFile(let path):
            return "Path is not a regular file: \(path)"
        }
    }
}

public struct SafeFilePreviewLoader: Sendable {
    public var maxPreviewBytes: Int
    public var binaryProbeBytes: Int

    public init(maxPreviewBytes: Int = 256 * 1024, binaryProbeBytes: Int = 4 * 1024) {
        self.maxPreviewBytes = maxPreviewBytes
        self.binaryProbeBytes = binaryProbeBytes
    }

    public func preview(root: URL, relativePath: String) async throws -> FilePreviewViewState {
        try await Task.detached {
            try Self.load(
                root: root,
                relativePath: relativePath,
                maxPreviewBytes: maxPreviewBytes,
                binaryProbeBytes: binaryProbeBytes)
        }.value
    }

    private static func load(
        root: URL,
        relativePath: String,
        maxPreviewBytes: Int,
        binaryProbeBytes: Int
    ) throws -> FilePreviewViewState {
        let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SafeFilePreviewError.emptyPath }
        guard !trimmed.hasPrefix("/") else { throw SafeFilePreviewError.pathEscapesWorkspace(trimmed) }

        let rootURL = root.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = rootURL.appendingPathComponent(trimmed).standardizedFileURL.resolvingSymlinksInPath()
        let rootPath = rootURL.path
        guard candidate.path == rootPath || candidate.path.hasPrefix(rootPath + "/") else {
            throw SafeFilePreviewError.pathEscapesWorkspace(trimmed)
        }

        let values = try candidate.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else {
            throw SafeFilePreviewError.notARegularFile(trimmed)
        }

        let handle = try FileHandle(forReadingFrom: candidate)
        defer { try? handle.close() }
        let requestedBytes = max(maxPreviewBytes, 1) + 1
        let data = try handle.read(upToCount: requestedBytes) ?? Data()
        let byteCount = values.fileSize ?? data.count
        let previewData = data.prefix(maxPreviewBytes)
        let isTruncated = data.count > maxPreviewBytes || byteCount > maxPreviewBytes
        let probe = previewData.prefix(max(1, min(binaryProbeBytes, previewData.count)))

        if probe.contains(0) || String(data: previewData, encoding: .utf8) == nil {
            return FilePreviewViewState(
                path: trimmed,
                kind: .binary,
                byteCount: byteCount,
                isTruncated: isTruncated,
                message: "Binary file preview is disabled.")
        }

        var text = String(decoding: previewData, as: UTF8.self)
        if isTruncated {
            text += "\n\n[Preview truncated at \(maxPreviewBytes) bytes of \(byteCount) bytes]"
        }
        return FilePreviewViewState(
            path: trimmed,
            kind: .text,
            text: text,
            syntaxTokens: SyntaxHighlighter.tokens(in: text, path: trimmed),
            byteCount: byteCount,
            isTruncated: isTruncated,
            message: text.isEmpty ? "Empty file." : "")
    }
}

enum SyntaxHighlighter {
    private static let swiftKeywords: Set<String> = [
        "actor", "any", "as", "async", "await", "break", "case", "catch", "class",
        "continue", "defer", "do", "else", "enum", "extension", "false", "for",
        "func", "guard", "if", "import", "in", "init", "let", "nil", "private",
        "protocol", "public", "return", "self", "static", "struct", "switch",
        "throws", "true", "try", "var", "while",
    ]

    static func tokens(in text: String, path: String) -> [CodeSyntaxToken] {
        guard path.hasSuffix(".swift") else { return [] }
        let ns = text as NSString
        let length = ns.length
        var tokens: [CodeSyntaxToken] = []
        var index = 0
        while index < length {
            let character = ns.character(at: index)
            if character == 47, index + 1 < length { // /
                let next = ns.character(at: index + 1)
                if next == 47 {
                    let end = lineEnd(in: ns, from: index)
                    tokens.append(.init(range: NSRange(location: index, length: end - index), kind: .comment))
                    index = end
                    continue
                }
                if next == 42 {
                    let end = blockCommentEnd(in: ns, from: index + 2)
                    tokens.append(.init(range: NSRange(location: index, length: end - index), kind: .comment))
                    index = end
                    continue
                }
            }
            if character == 34 { // "
                let end = stringEnd(in: ns, from: index + 1)
                tokens.append(.init(range: NSRange(location: index, length: end - index), kind: .string))
                index = end
                continue
            }
            if isDigit(character) {
                let start = index
                while index < length, isDigit(ns.character(at: index)) { index += 1 }
                tokens.append(.init(range: NSRange(location: start, length: index - start), kind: .number))
                continue
            }
            if isIdentifierStart(character) {
                let start = index
                while index < length, isIdentifierPart(ns.character(at: index)) { index += 1 }
                let word = ns.substring(with: NSRange(location: start, length: index - start))
                if swiftKeywords.contains(word) {
                    tokens.append(.init(range: NSRange(location: start, length: index - start), kind: .keyword))
                }
                continue
            }
            index += 1
        }
        return tokens
    }

    private static func lineEnd(in text: NSString, from start: Int) -> Int {
        var index = start
        while index < text.length, text.character(at: index) != 10 { index += 1 }
        return index
    }

    private static func blockCommentEnd(in text: NSString, from start: Int) -> Int {
        var index = start
        while index + 1 < text.length {
            if text.character(at: index) == 42, text.character(at: index + 1) == 47 {
                return index + 2
            }
            index += 1
        }
        return text.length
    }

    private static func stringEnd(in text: NSString, from start: Int) -> Int {
        var index = start
        var escaped = false
        while index < text.length {
            let character = text.character(at: index)
            if character == 34, !escaped { return index + 1 }
            escaped = character == 92 && !escaped
            if character != 92 { escaped = false }
            index += 1
        }
        return text.length
    }

    private static func isDigit(_ character: unichar) -> Bool {
        character >= 48 && character <= 57
    }

    private static func isIdentifierStart(_ character: unichar) -> Bool {
        (character >= 65 && character <= 90) || (character >= 97 && character <= 122) || character == 95
    }

    private static func isIdentifierPart(_ character: unichar) -> Bool {
        isIdentifierStart(character) || isDigit(character)
    }
}
