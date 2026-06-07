import SwiftUI

public enum TodoItemStatus: String, Sendable, Equatable, Codable, CaseIterable {
    case pending
    case inProgress
    case completed
}

public struct TodoItemViewState: Sendable, Equatable, Codable, Identifiable {
    public var id: UUID
    public var title: String
    public var status: TodoItemStatus

    public init(id: UUID = UUID(), title: String, status: TodoItemStatus = .pending) {
        self.id = id
        self.title = title
        self.status = status
    }
}

public struct TodoPanelViewState: Sendable, Equatable, Codable {
    public var items: [TodoItemViewState]

    public init(items: [TodoItemViewState] = []) {
        self.items = items
    }

    public var openCount: Int {
        items.filter { $0.status != .completed }.count
    }
}

public struct TodoPanelView: View {
    public var state: TodoPanelViewState

    public init(state: TodoPanelViewState) {
        self.state = state
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: .space2) {
            ForEach(state.items) { item in
                HStack(spacing: .space2) {
                    Image(systemName: symbol(for: item.status))
                    Text(item.title)
                        .lineLimit(1)
                    Spacer()
                    Text(item.status.rawValue)
                        .font(.metaMono)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func symbol(for status: TodoItemStatus) -> String {
        switch status {
        case .pending: return "circle"
        case .inProgress: return "circle.lefthalf.filled"
        case .completed: return "checkmark.circle.fill"
        }
    }
}
