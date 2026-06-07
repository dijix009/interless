import SwiftUI

public struct SessionTimelineItemViewState: Sendable, Equatable, Codable, Identifiable {
    public var id: UUID
    public var title: String
    public var detail: String
    public var createdAt: Date
    public var severity: AppNoticeSeverity

    public init(
        id: UUID = UUID(),
        title: String,
        detail: String = "",
        createdAt: Date = Date(),
        severity: AppNoticeSeverity = .info
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.createdAt = createdAt
        self.severity = severity
    }
}

public struct SessionTimelineView: View {
    public var items: [SessionTimelineItemViewState]

    public init(items: [SessionTimelineItemViewState]) {
        self.items = items
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: .space2) {
            ForEach(items) { item in
                HStack(alignment: .top, spacing: .space2) {
                    Image(systemName: symbol(for: item.severity))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .lineLimit(1)
                        if !item.detail.isEmpty {
                            Text(item.detail)
                                .font(.metaMono)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    Spacer()
                }
            }
        }
    }

    private func symbol(for severity: AppNoticeSeverity) -> String {
        switch severity {
        case .info: return "circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.octagon"
        }
    }
}
