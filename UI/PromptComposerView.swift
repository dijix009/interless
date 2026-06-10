import SwiftUI

public struct PromptComposerAttachmentViewState: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var detail: String

    public init(id: UUID = UUID(), name: String, detail: String = "") {
        self.id = id
        self.name = name
        self.detail = detail
    }
}

/// Compact, reusable prompt composer. Visually aligned with the primary chat
/// composer (Theme tokens, amber focus ring, phosphor live caret) so the app
/// presents a single, coherent input language everywhere it appears.
public struct PromptComposerView: View {
    @Binding private var draft: String
    public var attachments: [PromptComposerAttachmentViewState]
    public var isEnabled: Bool
    public var onSend: @MainActor () -> Void
    public var onAddAttachment: @MainActor () -> Void
    public var onRemoveAttachment: @MainActor (UUID) -> Void
    @FocusState private var isFocused: Bool

    public init(
        draft: Binding<String>,
        attachments: [PromptComposerAttachmentViewState] = [],
        isEnabled: Bool = true,
        onSend: @escaping @MainActor () -> Void,
        onAddAttachment: @escaping @MainActor () -> Void = {},
        onRemoveAttachment: @escaping @MainActor (UUID) -> Void = { _ in }
    ) {
        self._draft = draft
        self.attachments = attachments
        self.isEnabled = isEnabled
        self.onSend = onSend
        self.onAddAttachment = onAddAttachment
        self.onRemoveAttachment = onRemoveAttachment
    }

    private var isSendEnabled: Bool {
        isEnabled && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: .space2) {
            if !attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: .space2) {
                        ForEach(attachments) { attachment in
                            attachmentChip(attachment)
                        }
                    }
                    .padding(.horizontal, .space3)
                }
            }
            HStack(alignment: .bottom, spacing: .space2) {
                Button(action: onAddAttachment) {
                    Image(systemName: "paperclip")
                }
                .buttonStyle(IconButtonStyle())
                .disabled(!isEnabled)
                .accessibilityLabel("Add attachment")

                TextField("Message", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.bodyS.weight(.medium))
                    .foregroundStyle(isEnabled ? Theme.C.textPrimary : Theme.C.textTertiary)
                    .tint(Theme.C.phosphor)   // live caret
                    .lineLimit(1...6)
                    .focused($isFocused)
                    .disabled(!isEnabled)
                    .onSubmit(onSend)

                Button(action: onSend) {
                    Image(systemName: "paperplane")
                        .foregroundStyle(isSendEnabled ? Theme.C.accent : Theme.C.textTertiary)
                }
                .buttonStyle(IconButtonStyle())
                .disabled(!isSendEnabled)
                .accessibilityLabel("Send")
            }
            .padding(.horizontal, .space3)
            .padding(.vertical, .space2)
        }
        .background(Theme.C.surface, in: RoundedRectangle(cornerRadius: .radiusLg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: .radiusLg, style: .continuous)
                .stroke(isFocused ? Theme.C.accent.opacity(0.58) : Theme.C.borderHover, lineWidth: 1)
        }
    }

    private func attachmentChip(_ attachment: PromptComposerAttachmentViewState) -> some View {
        HStack(spacing: .space1) {
            Image(systemName: "doc")
            Text(attachment.name)
                .lineLimit(1)
            if !attachment.detail.isEmpty {
                Text(attachment.detail)
                    .foregroundStyle(Theme.C.textTertiary)
                    .lineLimit(1)
            }
            Button {
                onRemoveAttachment(attachment.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Theme.C.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove attachment")
        }
        .font(.metaMono)
        .foregroundStyle(Theme.C.textSecondary)
        .padding(.horizontal, .space2)
        .padding(.vertical, .space1)
        .background(Theme.C.surface2, in: RoundedRectangle(cornerRadius: .radiusSm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: .radiusSm, style: .continuous)
                .stroke(Theme.C.border, lineWidth: 1))
    }
}
