import SwiftUI

public struct DiffViewer: View {
    public var files: [DiffFile]
    public var fallbackLines: [DiffLine]
    public var layout: ChatDiffLayoutMode

    public init(files: [DiffFile], fallbackLines: [DiffLine] = [], layout: ChatDiffLayoutMode = .inline) {
        self.files = files
        self.fallbackLines = fallbackLines
        self.layout = layout
    }

    public init(lines: [DiffLine], layout: ChatDiffLayoutMode = .inline) {
        self.files = []
        self.fallbackLines = lines
        self.layout = layout
    }

    public var body: some View {
        GeometryReader { geo in
            let effective = resolvedLayout(width: geo.size.width)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if !files.isEmpty {
                        ForEach(files) { file in
                            fileSection(file, layout: effective)
                        }
                    } else {
                        ForEach(fallbackLines) { line in
                            row(line, layout: effective)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, files.isEmpty ? 0 : 8)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .overlay {
                if files.isEmpty && fallbackLines.isEmpty {
                    ContentUnavailableView("No Diff", systemImage: "checkmark.circle", description: Text("Working tree diff is empty or unavailable."))
                }
            }
        }
        .background(Theme.C.surface)
    }

    /// `.dynamic` picks side-by-side only when there's room; otherwise honors the
    /// explicit choice. Side-by-side in a narrow pane would be cramped.
    private func resolvedLayout(width: CGFloat) -> ChatDiffLayoutMode {
        switch layout {
        case .dynamic: return width >= 720 ? .sideBySide : .inline
        case .inline: return .inline
        case .sideBySide: return .sideBySide
        }
    }

    private func fileSection(_ file: DiffFile, layout: ChatDiffLayoutMode) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "doc.text")
                    .foregroundStyle(Theme.C.textTertiary)
                Text(file.newPath.isEmpty ? file.oldPath : file.newPath)
                    .font(.metaMono)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text("+\(file.additions) -\(file.deletions)")
                    .font(.metaMono)
                    .foregroundStyle(Theme.C.textSecondary)
            }
            .padding(.horizontal, .space3)
            .padding(.vertical, 6)
            .background(Theme.C.surface3.opacity(0.6))

            ForEach(file.leadingLines) { line in
                row(line, layout: layout)
            }
            ForEach(file.hunks) { hunk in
                Text(hunk.header)
                    .font(.codeMono)
                    .foregroundStyle(Theme.C.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, .space3)
                    .padding(.vertical, .space1)
                    .background(Theme.C.surface3.opacity(0.6))
                ForEach(hunk.lines.filter { $0.text != hunk.header }) { line in
                    row(line, layout: layout)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: .radiusSm, style: .continuous))
        .padding(.horizontal, .space2)
    }

    @ViewBuilder
    private func row(_ line: DiffLine, layout: ChatDiffLayoutMode) -> some View {
        if layout == .sideBySide {
            sideBySideLine(line)
        } else {
            lineView(line)
        }
    }

    // MARK: Inline (unified)

    private func lineView(_ line: DiffLine) -> some View {
        // Leading gutter glyph so add/delete is not conveyed by color alone (a11y).
        Text(DiffPalette.glyph(line.kind) + " " + (line.text.isEmpty ? " " : line.text))
            .font(.codeMono)
            .foregroundStyle(DiffPalette.foreground(line.kind))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, .space3)
            .padding(.vertical, 2)
            .background(DiffPalette.background(line.kind))
    }

    // MARK: Side-by-side (split)

    private func sideBySideLine(_ line: DiffLine) -> some View {
        HStack(spacing: 0) {
            diffCell(line, isLeft: true)
            Divider()
            diffCell(line, isLeft: false)
        }
    }

    /// One side of a split row. Deletions show only on the left, additions only
    /// on the right; context shows on both. The empty side stays blank.
    private func diffCell(_ line: DiffLine, isLeft: Bool) -> some View {
        let visible: Bool
        switch line.kind {
        case .deletion: visible = isLeft
        case .addition: visible = !isLeft
        default: visible = true
        }
        let glyph: String
        switch line.kind {
        case .addition: glyph = "+"
        case .deletion: glyph = "-"
        default: glyph = " "
        }
        return Text(visible ? (glyph + " " + (line.text.isEmpty ? " " : line.text)) : " ")
            .font(.codeMono)
            .foregroundStyle(DiffPalette.foreground(visible ? line.kind : .context))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, .space2)
            .padding(.vertical, 2)
            .background(visible ? DiffPalette.background(line.kind) : Color.clear)
    }
}
