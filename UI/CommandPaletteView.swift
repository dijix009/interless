import SwiftUI

/// One entry in the command palette. `run` is invoked when the user activates it.
public struct CommandPaletteItem: Identifiable {
    public enum Group: String, CaseIterable, Sendable {
        case action = "Actions"
        case session = "Sessions"
        case file = "Files"
        case model = "Models"
    }

    public var id: String
    public var group: Group
    public var title: String
    public var subtitle: String?
    public var symbol: String
    public var isActive: Bool
    public var run: @MainActor () -> Void

    public init(
        id: String,
        group: Group,
        title: String,
        subtitle: String? = nil,
        symbol: String,
        isActive: Bool = false,
        run: @escaping @MainActor () -> Void
    ) {
        self.id = id
        self.group = group
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.isActive = isActive
        self.run = run
    }
}

/// ⌘K command palette — fuzzy-search across actions, sessions, files, and models.
/// Keyboard: type to filter, ↑/↓ to move, ⏎ to run, esc to close.
public struct CommandPaletteView: View {
    @Binding private var isPresented: Bool
    private let items: [CommandPaletteItem]
    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var queryFocused: Bool

    public init(isPresented: Binding<Bool>, items: [CommandPaletteItem]) {
        self._isPresented = isPresented
        self.items = items
    }

    public var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.42)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { close() }

            VStack(spacing: 0) {
                searchField
                Divider()
                results
                Divider()
                footer
            }
            .frame(width: 600)
            .frame(maxHeight: 460)
            .background(Theme.C.surface, in: RoundedRectangle(cornerRadius: .radiusLg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: .radiusLg, style: .continuous)
                    .stroke(Theme.C.borderHover, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.30), radius: 32, y: 12)
            .padding(.top, 96)
        }
        .onExitCommand { close() }
        .onAppear { queryFocused = true }
    }

    private var searchField: some View {
        HStack(spacing: .space2) {
            Text("›")
                .font(.system(.title3, design: .monospaced).weight(.bold))
                .foregroundStyle(Theme.C.phosphor)
            TextField("Search commands, sessions, files, models…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(.title3, design: .default))
                .foregroundStyle(Theme.C.textPrimary)
                .tint(Theme.C.phosphor)
                .focused($queryFocused)
                .onChange(of: query) { _, _ in selectedIndex = 0 }
                .onKeyPress(.upArrow) { move(-1); return .handled }
                .onKeyPress(.downArrow) { move(1); return .handled }
                .onKeyPress(.return) { runSelected(); return .handled }
        }
        .padding(.horizontal, .space4)
        .padding(.vertical, .space3)
    }

    private var footer: some View {
        HStack(spacing: .space3) {
            hint("↑↓", "navigate")
            hint("↩", "run")
            hint("esc", "close")
            Spacer(minLength: 0)
            Text("\(filteredItems.count)")
                .font(.metaMonoSm)
                .foregroundStyle(Theme.C.textTertiary)
        }
        .padding(.horizontal, .space4)
        .padding(.vertical, .space2)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.metaMonoSm)
                .foregroundStyle(Theme.C.textSecondary)
            Text(label)
                .font(.metaMono)
                .foregroundStyle(Theme.C.textTertiary)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var results: some View {
        let filtered = filteredItems
        if filtered.isEmpty {
            VStack(spacing: .space2) {
                Text("No matches")
                    .font(.bodyS)
                    .foregroundStyle(Theme.C.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, .space5)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(filtered.enumerated()), id: \.element.id) { index, item in
                            row(item, index: index, isSelected: index == clampedSelection(filtered.count))
                                .id(index)
                                .onTapGesture { run(item) }
                        }
                    }
                    .padding(.space2)
                }
                .onChange(of: selectedIndex) { _, newValue in
                    withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(newValue, anchor: .center) }
                }
            }
        }
    }

    private func row(_ item: CommandPaletteItem, index: Int, isSelected: Bool) -> some View {
        HStack(spacing: .space3) {
            Image(systemName: item.symbol)
                .font(.bodyS)
                .foregroundStyle(isSelected ? Theme.C.phosphor : Theme.C.textTertiary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.bodyS.weight(.medium))
                    .foregroundStyle(Theme.C.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let subtitle = item.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.metaMono)
                        .foregroundStyle(Theme.C.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: .space2)
            if item.isActive {
                Image(systemName: "checkmark")
                    .font(.metaMonoSm)
                    .foregroundStyle(Theme.C.phosphor)
            }
            Text(item.group.rawValue)
                .font(.metaMonoSm)
                .foregroundStyle(Theme.C.textTertiary)
        }
        .padding(.horizontal, .space3)
        .padding(.vertical, .space2)
        .background(
            isSelected ? Theme.C.accentGlow : Color.clear,
            in: RoundedRectangle(cornerRadius: .radiusSm, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title), \(item.group.rawValue)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: Filtering

    private var filteredItems: [CommandPaletteItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        // Empty query: show commands and sessions only. Files and models (which
        // can number in the thousands) appear once the user starts typing.
        guard !trimmed.isEmpty else {
            return items.filter { $0.group == .action || $0.group == .session }
        }
        let needle = trimmed.lowercased()
        return items
            .compactMap { item -> (CommandPaletteItem, Int)? in
                guard let score = Self.fuzzyScore(needle, in: item.title.lowercased())
                    ?? item.subtitle.flatMap({ Self.fuzzyScore(needle, in: $0.lowercased()) })
                else { return nil }
                return (item, score)
            }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    /// Subsequence fuzzy match. Returns a score (lower = better: rewards
    /// contiguous, early matches) or nil if `needle` isn't a subsequence.
    static func fuzzyScore(_ needle: String, in haystack: String) -> Int? {
        if let range = haystack.range(of: needle) {
            // Contiguous substring: best, scored by how early it starts.
            return haystack.distance(from: haystack.startIndex, to: range.lowerBound)
        }
        var score = 0
        var lastMatch = -1
        var hChars = Array(haystack)
        var hIndex = 0
        for nChar in needle {
            var found = false
            while hIndex < hChars.count {
                if hChars[hIndex] == nChar {
                    if lastMatch >= 0 { score += (hIndex - lastMatch) }
                    score += hIndex
                    lastMatch = hIndex
                    hIndex += 1
                    found = true
                    break
                }
                hIndex += 1
            }
            if !found { return nil }
        }
        return score + 1000 // subsequence matches rank below contiguous ones
    }

    // MARK: Selection

    private func clampedSelection(_ count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(selectedIndex, 0), count - 1)
    }

    private func move(_ delta: Int) {
        let count = filteredItems.count
        guard count > 0 else { return }
        selectedIndex = (clampedSelection(count) + delta + count) % count
    }

    private func runSelected() {
        let filtered = filteredItems
        guard !filtered.isEmpty else { return }
        run(filtered[clampedSelection(filtered.count)])
    }

    private func run(_ item: CommandPaletteItem) {
        close()
        item.run()
    }

    private func close() {
        isPresented = false
        query = ""
        selectedIndex = 0
    }
}
