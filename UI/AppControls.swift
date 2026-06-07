import SwiftUI
import AppKit

// MARK: - Window drag

/// A background region that lets the user drag the window — for a custom,
/// in-content title bar (replaces the system toolbar's drag behavior).
public struct WindowDragHandle: NSViewRepresentable {
    public init() {}
    public func makeNSView(context: Context) -> NSView { DraggableView() }
    public func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DraggableView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
    }
}

// MARK: - Button styles

/// Compact icon button (toolbar-style) with hover/press feedback.
public struct IconButtonStyle: ButtonStyle {
    var active: Bool
    public init(active: Bool = false) { self.active = active }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(active ? Theme.C.accent : Theme.C.textSecondary)
            .frame(width: 26, height: 26)
            .background(
                configuration.isPressed ? Color.primary.opacity(0.10) : Color.clear,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
    }
}

/// Filled accent button (primary actions / send).
public struct AccentButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.bodyS.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, .space3)
            .padding(.vertical, 6)
            .background(
                Theme.C.accent.opacity(configuration.isPressed ? 0.8 : 1),
                in: RoundedRectangle(cornerRadius: .radiusSm, style: .continuous))
            .contentShape(Rectangle())
    }
}

// MARK: - Segmented toggle (custom, replaces segmented Picker)

public struct SegmentedToggle<Value: Hashable>: View {
    private let options: [(value: Value, label: String)]
    @Binding private var selection: Value

    public init(selection: Binding<Value>, options: [(Value, String)]) {
        self._selection = selection
        self.options = options.map { (value: $0.0, label: $0.1) }
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                Text(option.label)
                    .font(.metaMono)
                    .foregroundStyle(selection == option.value ? Theme.C.textPrimary : Theme.C.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, .space2)
                    .padding(.vertical, 3)
                    .background(
                        selection == option.value ? Theme.C.surface3 : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .contentShape(Rectangle())
                    .onTapGesture { selection = option.value }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(2)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
