import Foundation
import Shared
import SwiftTreeSitter
import TreeSitterSwift

/// Structured source extraction for the workspace index (ARCHITECTURE.md §9).
///
/// Swift is implemented first. The protocol keeps additional language parsers
/// additive: the indexer only depends on this seam.
public protocol CodeStructureExtractor: Sendable {
    func extract(from text: String, relativePath: String) -> CodeStructure
}

public struct CodeStructure: Sendable, Equatable {
    public var symbols: [CodeSymbol]
    public var comments: [String]
    public var references: [CodeReference]

    public init(symbols: [CodeSymbol] = [], comments: [String] = [], references: [CodeReference] = []) {
        self.symbols = symbols
        self.comments = comments
        self.references = references
    }
}

public struct NoOpCodeStructureExtractor: CodeStructureExtractor {
    public init() {}
    public func extract(from text: String, relativePath: String) -> CodeStructure { CodeStructure() }
}

/// Swift-first tree-sitter extractor. The parser supplies structural nodes;
/// lexical extraction remains a fallback for parser setup failures.
public struct SwiftCodeStructureExtractor: CodeStructureExtractor {
    public init() {}

    public func extract(from text: String, relativePath: String) -> CodeStructure {
        guard relativePath.hasSuffix(".swift") else { return CodeStructure() }
        return Self.treeSitterExtract(from: text) ?? Self.lexicalExtract(from: text)
    }

    private static func treeSitterExtract(from text: String) -> CodeStructure? {
        let parser = Parser()
        do {
            try parser.setLanguage(Language(language: tree_sitter_swift()))
        } catch {
            return nil
        }
        guard let tree = parser.parse(text), let root = tree.rootNode else { return nil }

        var symbols: [CodeSymbol] = []
        var comments: [String] = []
        var references: [CodeReference] = []

        visit(root) { node in
            guard let nodeType = node.nodeType else { return }
            switch nodeType {
            case "class_declaration":
                guard let nameNode = node.child(byFieldName: "name") else { return }
                let declarationKind = node.child(byFieldName: "declaration_kind")
                    .map { nodeText($0, in: text) } ?? "type"
                let kind = declarationKind == "extension" ? "extension" : "type"
                symbols.append(symbol(name: nodeText(nameNode, in: text), kind: kind, node: nameNode))
            case "protocol_declaration":
                guard let nameNode = node.child(byFieldName: "name") else { return }
                symbols.append(symbol(name: nodeText(nameNode, in: text), kind: "type", node: nameNode))
            case "function_declaration":
                guard let nameNode = node.child(byFieldName: "name") else { return }
                symbols.append(symbol(name: nodeText(nameNode, in: text), kind: "function", node: nameNode))
            case "init_declaration":
                symbols.append(symbol(name: "init", kind: "initializer", node: node))
            case "property_declaration":
                guard let nameNode = node.child(byFieldName: "name") else { return }
                for identifier in identifiers(in: nameNode, source: text) {
                    symbols.append(symbol(name: identifier.name, kind: "property", node: identifier.node))
                }
            case "import_declaration":
                let importName = nodeText(node, in: text)
                    .replacingOccurrences(of: #"^\s*@testable\s+"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"^\s*import\s+"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !importName.isEmpty {
                    references.append(reference(name: importName, kind: "import", node: node))
                }
            case "call_expression":
                let callName = callTargetName(from: nodeText(node, in: text))
                if let callName, !callKeywords.contains(callName) {
                    references.append(reference(name: callName, kind: "call", node: node))
                }
            case "user_type":
                let typeName = nodeText(node, in: text)
                if !typeName.isEmpty {
                    references.append(reference(name: typeName, kind: "type", node: node))
                }
            case "simple_identifier":
                let name = nodeText(node, in: text)
                if !identifierKeywords.contains(name) {
                    if name.first?.isUppercase == true {
                        references.append(reference(name: name, kind: "type", node: node))
                    }
                    references.append(reference(name: name, kind: "identifier", node: node))
                }
            case "comment", "multiline_comment":
                let comment = stripCommentDelimiters(nodeText(node, in: text))
                if !comment.isEmpty { comments.append(comment) }
            default:
                break
            }
        }

        if comments.isEmpty {
            comments = extractComments(from: text)
        }

        return CodeStructure(
            symbols: deduplicate(symbols),
            comments: deduplicate(comments),
            references: deduplicate(references))
    }

    private static func lexicalExtract(from text: String) -> CodeStructure {
        let comments = extractComments(from: text)
        let sanitized = sanitizedSource(text)
        var symbols: [CodeSymbol] = []
        var references: [CodeReference] = []

        let lines = sanitized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        for (offset, line) in lines.enumerated() {
            let lineNumber = offset + 1
            symbols.append(contentsOf: Self.symbols(in: line, lineNumber: lineNumber))
            references.append(contentsOf: Self.references(in: line, lineNumber: lineNumber))
        }

        return CodeStructure(
            symbols: deduplicate(symbols),
            comments: comments,
            references: deduplicate(references))
    }

    private static func visit(_ node: Node, _ body: (Node) -> Void) {
        body(node)
        for index in 0..<node.childCount {
            if let child = node.child(at: index) {
                visit(child, body)
            }
        }
    }

    private static func identifiers(in node: Node, source: String) -> [(name: String, node: Node)] {
        var identifiers: [(String, Node)] = []
        visit(node) { child in
            guard child.nodeType == "simple_identifier" else { return }
            let name = nodeText(child, in: source)
            if !identifierKeywords.contains(name) {
                identifiers.append((name, child))
            }
        }
        return identifiers
    }

    private static func nodeText(_ node: Node, in source: String) -> String {
        guard let range = Range(node.range, in: source) else { return "" }
        return String(source[range])
    }

    private static func symbol(name: String, kind: String, node: Node) -> CodeSymbol {
        let point = node.pointRange.lowerBound
        return CodeSymbol(name: cleanName(name), kind: kind, line: Int(point.row) + 1, column: Int(point.column) + 1)
    }

    private static func reference(name: String, kind: String, node: Node) -> CodeReference {
        let point = node.pointRange.lowerBound
        return CodeReference(name: cleanName(name), kind: kind, line: Int(point.row) + 1, column: Int(point.column) + 1)
    }

    private static func cleanName(_ name: String) -> String {
        name.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "`")))
    }

    private static func callTargetName(from expression: String) -> String? {
        guard let paren = expression.firstIndex(of: "(") else { return nil }
        let target = expression[..<paren]
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "_" && $0 != "." })
            .last?
            .split(separator: ".")
            .last
            .map(String.init)
        return target?.isEmpty == false ? target : nil
    }

    private static func stripCommentDelimiters(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("//") {
            return trimmed.drop(while: { $0 == "/" })
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if trimmed.hasPrefix("/*") {
            return trimmed
                .replacingOccurrences(of: #"^/\*+"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\*/$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    private static func symbols(in line: String, lineNumber: Int) -> [CodeSymbol] {
        var symbols: [CodeSymbol] = []
        for (regex, kind) in Self.symbolRegexes {
            for match in regex.matches(in: line, range: NSRange(line.startIndex..., in: line)) {
                let name: String
                let column: Int
                if kind == "initializer" {
                    name = "init"
                    column = Self.column(for: match.range, in: line)
                } else {
                    let range = match.range(at: match.numberOfRanges - 1)
                    name = Self.substring(line, range).trimmingCharacters(in: CharacterSet(charactersIn: "`"))
                    column = Self.column(for: range, in: line)
                }
                symbols.append(CodeSymbol(name: name, kind: kind, line: lineNumber, column: column))
            }
        }
        return symbols
    }

    private static func references(in line: String, lineNumber: Int) -> [CodeReference] {
        var references: [CodeReference] = []
        for match in Self.importRegex.matches(in: line, range: NSRange(line.startIndex..., in: line)) {
            let range = match.range(at: 1)
            references.append(CodeReference(name: substring(line, range), kind: "import", line: lineNumber, column: column(for: range, in: line)))
        }
        for match in Self.callRegex.matches(in: line, range: NSRange(line.startIndex..., in: line)) {
            let range = match.range(at: 1)
            let name = substring(line, range)
            if !Self.callKeywords.contains(name) {
                references.append(CodeReference(name: name, kind: "call", line: lineNumber, column: column(for: range, in: line)))
            }
        }
        for match in Self.typeReferenceRegex.matches(in: line, range: NSRange(line.startIndex..., in: line)) {
            let name = substring(line, match.range)
            references.append(CodeReference(name: name, kind: "type", line: lineNumber, column: column(for: match.range, in: line)))
        }
        for match in Self.identifierRegex.matches(in: line, range: NSRange(line.startIndex..., in: line)) {
            let name = substring(line, match.range)
            if !Self.identifierKeywords.contains(name) {
                references.append(CodeReference(name: name, kind: "identifier", line: lineNumber, column: column(for: match.range, in: line)))
            }
        }
        return references
    }

    private static func extractComments(from text: String) -> [String] {
        var comments: [String] = []
        var block = ""
        var inBlock = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            var remaining = line[...]
            while !remaining.isEmpty {
                if inBlock {
                    if let end = remaining.range(of: "*/") {
                        block += " " + remaining[..<end.lowerBound]
                        comments.append(String(block).trimmingCharacters(in: .whitespacesAndNewlines))
                        block = ""
                        inBlock = false
                        remaining = remaining[end.upperBound...]
                    } else {
                        block += " " + remaining
                        break
                    }
                } else if let lineComment = remaining.range(of: "//"),
                          (remaining.range(of: "/*") == nil || lineComment.lowerBound < remaining.range(of: "/*")!.lowerBound) {
                    comments.append(String(remaining[lineComment.upperBound...]).trimmingCharacters(in: .whitespaces))
                    break
                } else if let start = remaining.range(of: "/*") {
                    inBlock = true
                    remaining = remaining[start.upperBound...]
                } else {
                    break
                }
            }
        }
        if inBlock, !block.isEmpty {
            comments.append(block.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return comments.filter { !$0.isEmpty }
    }

    private static func sanitizedSource(_ text: String) -> String {
        var output = ""
        var iterator = text.makeIterator()
        var inString = false
        var previous: Character?
        while let ch = iterator.next() {
            if inString {
                if ch == "\"" && previous != "\\" { inString = false }
                output.append(ch == "\n" ? "\n" : " ")
            } else if ch == "\"" {
                inString = true
                output.append(" ")
            } else {
                output.append(ch)
            }
            previous = ch
        }
        return output
    }

    private static let identifierKeywords: Set<String> = [
        "actor", "as", "associatedtype", "break", "case", "catch", "class", "continue", "default",
        "defer", "deinit", "do", "else", "enum", "extension", "fallthrough", "false", "fileprivate",
        "for", "func", "guard", "if", "import", "in", "init", "inout", "internal", "is", "let",
        "nil", "open", "operator", "private", "protocol", "public", "repeat", "return", "self",
        "static", "struct", "subscript", "super", "switch", "throw", "throws", "true", "try",
        "typealias", "var", "where", "while"
    ]
    private static let callKeywords: Set<String> = identifierKeywords.union(["if", "for", "while", "switch", "guard"])

    private static func makeRegex(_ pattern: String) -> NSRegularExpression {
        // Patterns are compile-time constants and back the static caches below
        // (compiled once, not per line). Fall back to a valid never-match pattern
        // rather than `try!`, so a typo can never crash indexing.
        if let regex = try? NSRegularExpression(pattern: pattern) { return regex }
        return (try? NSRegularExpression(pattern: "(?!)")) ?? NSRegularExpression()
    }

    // Compiled once and reused across every line (was: recompiled per line).
    private static let symbolRegexes: [(NSRegularExpression, String)] = [
        (makeRegex(#"\b(struct|class|enum|protocol|actor)\s+(`?[A-Za-z_][A-Za-z0-9_]*`?)"#), "type"),
        (makeRegex(#"\bextension\s+(`?[A-Za-z_][A-Za-z0-9_\.]*`?)"#), "extension"),
        (makeRegex(#"\bfunc\s+(`?[A-Za-z_][A-Za-z0-9_]*`?)\s*\("#), "function"),
        (makeRegex(#"\binit\s*\("#), "initializer"),
        (makeRegex(#"\b(?:let|var)\s+(`?[A-Za-z_][A-Za-z0-9_]*`?)"#), "property"),
    ]
    private static let importRegex = makeRegex(#"\bimport\s+([A-Za-z_][A-Za-z0-9_\.]*)"#)
    private static let callRegex = makeRegex(#"\b([A-Za-z_][A-Za-z0-9_]*)\s*\("#)
    private static let typeReferenceRegex = makeRegex(#"\b[A-Z][A-Za-z0-9_]*\b"#)
    private static let identifierRegex = makeRegex(#"\b[A-Za-z_][A-Za-z0-9_]*\b"#)

    private static func substring(_ string: String, _ range: NSRange) -> String {
        guard let range = Range(range, in: string) else { return "" }
        return String(string[range])
    }

    private static func column(for range: NSRange, in line: String) -> Int {
        guard let swiftRange = Range(range, in: line) else { return 1 }
        return line.distance(from: line.startIndex, to: swiftRange.lowerBound) + 1
    }

    private static func deduplicate(_ symbols: [CodeSymbol]) -> [CodeSymbol] {
        var seen = Set<CodeSymbol>()
        return symbols.filter { seen.insert($0).inserted }
    }

    private static func deduplicate(_ references: [CodeReference]) -> [CodeReference] {
        var seen = Set<CodeReference>()
        return references.filter { seen.insert($0).inserted }
    }

    private static func deduplicate(_ strings: [String]) -> [String] {
        var seen = Set<String>()
        return strings.filter { seen.insert($0).inserted }
    }
}
