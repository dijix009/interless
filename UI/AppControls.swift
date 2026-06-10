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

// MARK: - Resizable divider

/// A thin divider with a wider invisible hit area that drag-resizes an adjacent
/// pane. Shows the horizontal-resize cursor on hover. Width is bound to a
/// persisted value so the layout survives relaunch.
public struct ResizableDivider: View {
    @Binding private var width: Double
    private let minWidth: Double
    private let maxWidth: Double
    @State private var dragBaseWidth: Double?

    public init(width: Binding<Double>, minWidth: Double, maxWidth: Double) {
        self._width = width
        self.minWidth = minWidth
        self.maxWidth = maxWidth
    }

    public var body: some View {
        Divider()
            .overlay(
                Color.clear
                    .frame(width: 10)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        // .set() (not push/pop) avoids cursor-stack imbalance.
                        if inside { NSCursor.resizeLeftRight.set() } else { NSCursor.arrow.set() }
                    }
                    .gesture(
                        // .global coordinate space is essential: the divider itself
                        // moves as the pane resizes, so a local-space translation
                        // would drift and oscillate. Global space is anchored to the
                        // window, so the delta stays stable.
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { value in
                                let base = dragBaseWidth ?? width
                                if dragBaseWidth == nil { dragBaseWidth = base }
                                NSCursor.resizeLeftRight.set()
                                width = min(maxWidth, max(minWidth, base + value.translation.width))
                            }
                            .onEnded { _ in dragBaseWidth = nil })
            )
            .accessibilityHidden(true)
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
                let isSelected = selection == option.value
                Button {
                    selection = option.value
                } label: {
                    Text(option.label)
                        .font(.metaMono)
                        .foregroundStyle(isSelected ? Theme.C.textPrimary : Theme.C.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, .space2)
                        .padding(.vertical, 3)
                        .background(
                            isSelected ? Theme.C.surface3 : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.label)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(2)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: .radiusSm, style: .continuous))
    }
}
