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

public struct PromptComposerView: View {
    @Binding private var draft: String
    public var attachments: [PromptComposerAttachmentViewState]
    public var isEnabled: Bool
    public var onSend: @MainActor () -> Void
    public var onAddAttachment: @MainActor () -> Void
    public var onRemoveAttachment: @MainActor (UUID) -> Void

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
                .buttonStyle(.borderless)
                .disabled(!isEnabled)
                .accessibilityLabel("Add attachment")

                TextField("Message", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .disabled(!isEnabled)
                    .onSubmit(onSend)

                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                }
                .buttonStyle(.borderless)
                .disabled(!isEnabled || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Send")
            }
            .padding(.horizontal, .space3)
            .padding(.vertical, .space2)
        }
    }

    private func attachmentChip(_ attachment: PromptComposerAttachmentViewState) -> some View {
        HStack(spacing: .space1) {
            Image(systemName: "doc")
            Text(attachment.name)
                .lineLimit(1)
            if !attachment.detail.isEmpty {
                Text(attachment.detail)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Button {
                onRemoveAttachment(attachment.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Remove attachment")
        }
        .font(.caption)
        .padding(.horizontal, .space2)
        .padding(.vertical, .space1)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
