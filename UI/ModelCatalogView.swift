import SwiftUI
import Shared

public struct ModelCatalogView: View {
    public var entries: [ModelCatalogEntry]
    public var onSelect: @MainActor (String) -> Void

    public init(entries: [ModelCatalogEntry], onSelect: @escaping @MainActor (String) -> Void = { _ in }) {
        self.entries = entries
        self.onSelect = onSelect
    }

    public var body: some View {
        List(entries) { entry in
            Button {
                onSelect(entry.id)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: .space1) {
                        Text(entry.displayName)
                            .font(.body)
                        Text(entry.supportedRoles.map(\.rawValue).joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if entry.isAvailableLocally {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Theme.C.success)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }
}
