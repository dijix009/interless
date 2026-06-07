import SwiftUI

public struct DiffViewer: View {
    public var files: [DiffFile]
    public var fallbackLines: [DiffLine]

    public init(files: [DiffFile], fallbackLines: [DiffLine] = []) {
        self.files = files
        self.fallbackLines = fallbackLines
    }

    public init(lines: [DiffLine]) {
        self.files = []
        self.fallbackLines = lines
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if !files.isEmpty {
                        ForEach(files) { file in
                            fileSection(file)
                        }
                    } else {
                        ForEach(fallbackLines) { line in
                            lineView(line)
                        }
                    }
                }
                .padding(.vertical, files.isEmpty ? 0 : 8)
            }
            .overlay {
                if files.isEmpty && fallbackLines.isEmpty {
                    ContentUnavailableView("No Diff", systemImage: "checkmark.circle", description: Text("Working tree diff is empty or unavailable."))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.C.surface)
    }

    private func fileSection(_ file: DiffFile) -> some View {
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
                lineView(line)
            }
            ForEach(file.hunks) { hunk in
                Text(hunk.header)
                    .font(.codeMono)
                    .foregroundStyle(Theme.C.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, .space3)
                    .padding(.vertical, 4)
                    .background(Theme.C.surface3.opacity(0.6))
                ForEach(hunk.lines.filter { $0.text != hunk.header }) { line in
                    lineView(line)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: .radiusSm, style: .continuous))
        .padding(.horizontal, .space2)
    }

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
}
