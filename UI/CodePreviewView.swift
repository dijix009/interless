import AppKit
import SwiftUI

public struct CodePreviewView: NSViewRepresentable {
    public var text: String
    public var syntaxTokens: [CodeSyntaxToken]

    public init(text: String, syntaxTokens: [CodeSyntaxToken] = []) {
        self.text = text
        self.syntaxTokens = syntaxTokens
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView(usingTextLayoutManager: true)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.textContainer?.widthTracksTextView = true
        textView.autoresizingMask = [.width]

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.drawsBackground = false
        scrollView.documentView = textView
        return scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        textView.textStorage?.setAttributedString(Self.attributed(text: text, tokens: syntaxTokens))
    }

    private static func attributed(text: String, tokens: [CodeSyntaxToken]) -> NSAttributedString {
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        let result = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
                .foregroundColor: NSColor.labelColor,
            ])
        for token in tokens where NSIntersectionRange(fullRange, token.range).length == token.range.length {
            result.addAttribute(.foregroundColor, value: color(for: token.kind), range: token.range)
        }
        return result
    }

    private static func color(for kind: CodeSyntaxTokenKind) -> NSColor {
        switch kind {
        case .keyword:
            return .systemBlue
        case .string:
            return .systemGreen
        case .comment:
            return .secondaryLabelColor
        case .number:
            return .systemOrange
        }
    }
}
