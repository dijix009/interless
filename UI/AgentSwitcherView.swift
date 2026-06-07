import SwiftUI

public struct AgentSwitcherItemViewState: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var isEnabled: Bool

    public init(id: String, title: String, subtitle: String = "", isEnabled: Bool = true) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.isEnabled = isEnabled
    }
}

public struct AgentSwitcherView: View {
    public var agents: [AgentSwitcherItemViewState]
    public var selectedAgentID: String?
    public var onSelect: @MainActor (String) -> Void

    public init(
        agents: [AgentSwitcherItemViewState],
        selectedAgentID: String?,
        onSelect: @escaping @MainActor (String) -> Void
    ) {
        self.agents = agents
        self.selectedAgentID = selectedAgentID
        self.onSelect = onSelect
    }

    public var body: some View {
        Menu {
            ForEach(agents) { agent in
                Button {
                    onSelect(agent.id)
                } label: {
                    Label(agent.title, systemImage: selectedAgentID == agent.id ? "checkmark" : "person")
                }
                .disabled(!agent.isEnabled)
            }
        } label: {
            Label(selectedTitle, systemImage: "person.2")
        }
        .accessibilityLabel("Agent")
    }

    private var selectedTitle: String {
        agents.first { $0.id == selectedAgentID }?.title ?? "Agent"
    }
}
