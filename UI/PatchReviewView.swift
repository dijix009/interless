import SwiftUI

public struct PatchReviewView: View {
    public var proposal: PatchProposal?
    public var writesAllowed: Bool
    public var onSetHunkAccepted: @MainActor (_ fileID: String, _ hunkID: Int, _ isAccepted: Bool) -> Void
    public var onApply: @MainActor () -> Void
    public var onDiscard: @MainActor () -> Void

    public init(
        proposal: PatchProposal?,
        writesAllowed: Bool,
        onSetHunkAccepted: @escaping @MainActor (_ fileID: String, _ hunkID: Int, _ isAccepted: Bool) -> Void,
        onApply: @escaping @MainActor () -> Void,
        onDiscard: @escaping @MainActor () -> Void
    ) {
        self.proposal = proposal
        self.writesAllowed = writesAllowed
        self.onSetHunkAccepted = onSetHunkAccepted
        self.onApply = onApply
        self.onDiscard = onDiscard
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let proposal {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: .space3) {
                        diagnostics(proposal)
                        ForEach(proposal.files) { file in
                            fileSection(file)
                        }
                    }
                    .padding()
                }
            } else {
                ContentUnavailableView("No Patch Loaded", systemImage: "doc.text.magnifyingglass")
            }
        }
        .frame(minWidth: 760, minHeight: 560)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(proposal?.title ?? "Patch Review")
                    .font(.displayMd)
                Text(proposal?.summary ?? "No patch proposal loaded")
                    .font(.metaMono)
                    .foregroundStyle(Theme.C.textSecondary)
            }
            Spacer()
            if let reason = PatchReviewModel.disabledApplyReason(proposal: proposal, writesAllowed: writesAllowed) {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Button("Discard", action: onDiscard)
            Button("Apply Accepted", action: onApply)
                .buttonStyle(.borderedProminent)
                .disabled(PatchReviewModel.disabledApplyReason(proposal: proposal, writesAllowed: writesAllowed) != nil)
        }
        .padding()
    }

    @ViewBuilder
    private func diagnostics(_ proposal: PatchProposal) -> some View {
        ForEach(proposal.diagnostics, id: \.self) { diagnostic in
            Label(diagnostic, systemImage: "exclamationmark.triangle")
                .foregroundStyle(Theme.C.caution)
        }
    }

    private func fileSection(_ file: PatchFile) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(file.newPath == "/dev/null" ? file.oldPath : file.newPath, systemImage: "doc.text")
                    .font(.metaMono)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text("+\(file.additions) -\(file.deletions)")
                    .font(.metaMono)
                    .foregroundStyle(Theme.C.textSecondary)
            }
            .padding(.horizontal, .space3)
            .padding(.vertical, .space2)
            .background(Theme.C.surface3.opacity(0.6))

            ForEach(file.diagnostics, id: \.self) { diagnostic in
                Label(diagnostic, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Theme.C.caution)
                    .padding(.space2)
            }

            ForEach(file.hunks) { hunk in
                hunkSection(hunk, fileID: file.id)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: .radiusSm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: .radiusSm, style: .continuous)
                .stroke(Theme.C.border)
        }
    }

    private func hunkSection(_ hunk: PatchHunk, fileID: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Toggle(isOn: Binding(
                    get: { hunk.isAccepted },
                    set: { onSetHunkAccepted(fileID, hunk.id, $0) }
                )) {
                    Text(hunk.header)
                        .font(.caption.monospaced())
                }
                .toggleStyle(.checkbox)
                .accessibilityLabel(AccessibilityCopy.patchHunkLabel(hunk))
                Spacer()
                Text("+\(hunk.additions) -\(hunk.deletions)")
                    .font(.metaMono)
                    .foregroundStyle(Theme.C.textSecondary)
            }
            .padding(.horizontal, .space3)
            .padding(.vertical, 6)
            .background(Theme.C.surface3.opacity(0.6))

            ForEach(hunk.lines) { line in
                Text(prefix(for: line.kind) + line.text)
                    .font(.codeMono)
                    .foregroundStyle(DiffPalette.foreground(line.kind))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, .space3)
                    .padding(.vertical, 2)
                    .background(DiffPalette.background(line.kind))
            }
        }
    }

    private func prefix(for kind: PatchLineKind) -> String {
        switch kind {
        case .context: return " "
        case .addition: return "+"
        case .deletion: return "-"
        }
    }
}
