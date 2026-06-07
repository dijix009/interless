import SwiftUI

public struct QuestionPromptViewState: Sendable, Equatable, Codable, Identifiable {
    public var id: UUID
    public var prompt: String
    public var options: [String]

    public init(id: UUID = UUID(), prompt: String, options: [String] = []) {
        self.id = id
        self.prompt = prompt
        self.options = options
    }
}

public struct QuestionPromptView: View {
    public var state: QuestionPromptViewState
    public var onAnswer: @MainActor (String) -> Void
    public var onCancel: @MainActor () -> Void
    @State private var freeformAnswer = ""

    public init(
        state: QuestionPromptViewState,
        onAnswer: @escaping @MainActor (String) -> Void,
        onCancel: @escaping @MainActor () -> Void
    ) {
        self.state = state
        self.onAnswer = onAnswer
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: .space3) {
            HStack(spacing: .space2) {
                Image(systemName: "questionmark.bubble")
                Text("Question")
                    .font(.titleS)
                Spacer()
            }
            Text(state.prompt)
                .font(.body)
                .foregroundStyle(Theme.C.textSecondary)
            if !state.options.isEmpty {
                VStack(alignment: .leading, spacing: .space2) {
                    ForEach(state.options, id: \.self) { option in
                        Button {
                            onAnswer(option)
                        } label: {
                            HStack {
                                Text(option)
                                Spacer()
                            }
                        }
                    }
                }
            }
            TextField("Answer", text: $freeformAnswer)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                Button("Answer") {
                    onAnswer(freeformAnswer)
                }
                .disabled(freeformAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.space4)
        .overlaySurface()
    }
}
