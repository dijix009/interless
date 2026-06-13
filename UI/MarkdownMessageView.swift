import AppKit
import SwiftUI

public enum MarkdownBlock: Equatable, Sendable {
    case paragraph(String)
    case heading(level: Int, text: String)
    case unorderedList([String])
    case orderedList(start: Int, items: [String])
    case blockquote(String)
    case code(language: String?, text: String, isClosed: Bool)
    case horizontalRule
}

public enum MarkdownMessageParser {
    public static func parse(_ text: String) -> [MarkdownBlock] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var blocks: [MarkdownBlock] = []
        var paragraphLines: [String] = []
        var quoteLines: [String] = []
        var unorderedItems: [String] = []
        var orderedItems: [String] = []
        var orderedStart = 1
        var codeLines: [String] = []
        var codeLanguage: String?
        var activeFence: (char: Character, length: Int)?

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            blocks.append(.paragraph(paragraphLines.joined(separator: "\n")))
            paragraphLines.removeAll()
        }

        func flushQuote() {
            guard !quoteLines.isEmpty else { return }
            blocks.append(.blockquote(quoteLines.joined(separator: "\n")))
            quoteLines.removeAll()
        }

        func flushList() {
            if !unorderedItems.isEmpty {
                blocks.append(.unorderedList(unorderedItems))
                unorderedItems.removeAll()
            }
            if !orderedItems.isEmpty {
                blocks.append(.orderedList(start: orderedStart, items: orderedItems))
                orderedItems.removeAll()
                orderedStart = 1
            }
        }

        func flushFlowBlocks() {
            flushParagraph()
            flushQuote()
            flushList()
        }

        for line in lines {
            if let fence = activeFence {
                // CommonMark: the closing fence must be a BARE run of the same
                // char, at least as long as the opener. An inner ```lang line (or
                // a shorter run) is content, not a close — so nested fences don't
                // truncate the block.
                if let run = Self.fenceRun(for: line),
                   run.char == fence.char, run.length >= fence.length, run.info.isEmpty {
                    blocks.append(.code(language: codeLanguage, text: codeLines.joined(separator: "\n"), isClosed: true))
                    codeLines.removeAll()
                    codeLanguage = nil
                    activeFence = nil
                } else {
                    codeLines.append(line)
                }
                continue
            }

            if let run = Self.fenceRun(for: line) {
                flushFlowBlocks()
                activeFence = (run.char, run.length)
                codeLanguage = run.info.isEmpty ? nil : run.info
                codeLines.removeAll()
                continue
            }

            if Self.isBlank(line) {
                flushFlowBlocks()
                continue
            }

            if Self.isHorizontalRule(line) {
                flushFlowBlocks()
                blocks.append(.horizontalRule)
                continue
            }

            if let heading = Self.heading(for: line) {
                flushFlowBlocks()
                blocks.append(.heading(level: heading.level, text: heading.text))
                continue
            }

            if let item = Self.unorderedListItem(for: line) {
                flushParagraph()
                flushQuote()
                if !orderedItems.isEmpty { flushList() }
                unorderedItems.append(item)
                continue
            }

            if let ordered = Self.orderedListItem(for: line) {
                flushParagraph()
                flushQuote()
                if !unorderedItems.isEmpty { flushList() }
                if orderedItems.isEmpty { orderedStart = ordered.start }
                orderedItems.append(ordered.text)
                continue
            }

            if let quote = Self.blockquoteLine(for: line) {
                flushParagraph()
                flushList()
                quoteLines.append(quote)
                continue
            }

            flushQuote()
            flushList()
            paragraphLines.append(line)
        }

        if activeFence != nil {
            blocks.append(.code(language: codeLanguage, text: codeLines.joined(separator: "\n"), isClosed: false))
        } else {
            flushFlowBlocks()
        }

        return blocks
    }

    private static func isBlank(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Leading fence run (≥3 of ``` or ~~~) plus the trimmed info string. Returns
    /// the run length so the parser can require a closing fence to be at least as
    /// long as the opener (and bare), per CommonMark.
    private static func fenceRun(for line: String) -> (char: Character, length: Int, info: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first, first == "`" || first == "~" else { return nil }
        var length = 0
        var index = trimmed.startIndex
        while index < trimmed.endIndex, trimmed[index] == first {
            length += 1
            index = trimmed.index(after: index)
        }
        guard length >= 3 else { return nil }
        let info = String(trimmed[index...]).trimmingCharacters(in: .whitespaces)
        return (first, length, info)
    }

    private static func heading(for line: String) -> (level: Int, text: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        var level = 0
        for character in trimmed {
            if character == "#" {
                level += 1
            } else {
                break
            }
        }
        guard (1...6).contains(level),
              trimmed.dropFirst(level).first == " " else { return nil }
        let text = trimmed.dropFirst(level + 1).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : (level, text)
    }

    private static func unorderedListItem(for line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        for prefix in ["- ", "* ", "+ "] where trimmed.hasPrefix(prefix) {
            return String(trimmed.dropFirst(prefix.count))
        }
        return nil
    }

    private static func orderedListItem(for line: String) -> (start: Int, text: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        var digitCount = 0
        for character in trimmed {
            if character.isNumber {
                digitCount += 1
            } else {
                break
            }
        }
        guard digitCount > 0 else { return nil }
        let afterDigits = trimmed.dropFirst(digitCount)
        guard afterDigits.hasPrefix(". ") || afterDigits.hasPrefix(") ") else { return nil }
        let number = Int(trimmed.prefix(digitCount)) ?? 1
        return (number, String(afterDigits.dropFirst(2)))
    }

    private static func blockquoteLine(for line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix(">") else { return nil }
        return trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        let marks = line.trimmingCharacters(in: .whitespaces).filter { !$0.isWhitespace }
        guard marks.count >= 3,
              let first = marks.first,
              first == "-" || first == "*" || first == "_" else { return false }
        return marks.allSatisfy { $0 == first }
    }
}

public struct MarkdownMessageView: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public init(text: String) {
        self.text = text
    }

    public var body: some View {
        let blocks = MarkdownMessageParser.parse(text)
        VStack(alignment: .leading, spacing: .space3) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                MarkdownBlockView(block: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MarkdownBlockView: View {
    let block: MarkdownBlock

    var body: some View {
        switch block {
        case let .paragraph(text):
            InlineMarkdownText(text)
                .font(.bodyS)
                .foregroundStyle(Theme.C.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        case let .heading(level, text):
            InlineMarkdownText(text)
                .font(headingFont(level: level))
                .foregroundStyle(Theme.C.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        case let .unorderedList(items):
            list(items: items, marker: { _ in "•" })
        case let .orderedList(start, items):
            list(items: items, marker: { "\($0 + start)." })
        case let .blockquote(text):
            HStack(alignment: .top, spacing: .space2) {
                Rectangle()
                    .fill(Theme.C.borderHover)
                    .frame(width: 2)
                InlineMarkdownText(text)
                    .font(.bodyS)
                    .foregroundStyle(Theme.C.textSecondary)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case let .code(language, text, isClosed):
            CodeBlockView(language: language, code: text, isClosed: isClosed)
        case .horizontalRule:
            Rectangle()
                .fill(Theme.C.border)
                .frame(height: 1)
                .padding(.vertical, .space1)
        }
    }

    private func headingFont(level: Int) -> Font {
        level <= 2 ? .titleS : .bodyS.weight(.semibold)
    }

    private func list(items: [String], marker: @escaping (Int) -> String) -> some View {
        VStack(alignment: .leading, spacing: .space1) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: .space2) {
                    Text(marker(index))
                        .font(.bodyS)
                        .foregroundStyle(Theme.C.textTertiary)
                        .frame(minWidth: 18, alignment: .trailing)
                    InlineMarkdownText(item)
                        .font(.bodyS)
                        .foregroundStyle(Theme.C.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct InlineMarkdownText: View {
    private let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        if let attributed = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            Text(attributed)
        } else {
            Text(text)
        }
    }
}

public struct CodeBlockView: View {
    private let language: String?
    private let code: String
    private let isClosed: Bool

    public init(language: String?, code: String, isClosed: Bool = true) {
        self.language = language?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.code = code
        self.isClosed = isClosed
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: .space2) {
                Text(displayLanguage)
                    .font(.metaMonoSm)
                    .foregroundStyle(Theme.C.textSecondary)
                if !isClosed {
                    Text("streaming")
                        .font(.metaMonoSm)
                        .foregroundStyle(Theme.C.phosphor)
                }
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.C.textTertiary)
                .help("Copy code")
            }
            .padding(.horizontal, .space3)
            .padding(.vertical, .space2)
            .background(Theme.C.surface3)

            ScrollView(.horizontal, showsIndicators: true) {
                Text(code.isEmpty ? " " : code)
                    .font(.codeMono)
                    .foregroundStyle(Theme.C.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.space3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.C.surface2)
        }
        .clipShape(RoundedRectangle(cornerRadius: .radiusSm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: .radiusSm, style: .continuous)
                .stroke(Theme.C.border, lineWidth: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var displayLanguage: String {
        guard let language, !language.isEmpty else { return "code" }
        return language
    }
}
