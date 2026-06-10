import SwiftUI

// MARK: - Motion primitives
//
// Restrained, terminal-flavoured motion that expresses the "machine is alive"
// idea (see DesignTokens colour semantics). Everything here honours the system
// Reduce Motion setting: when it is on, animations resolve to a calm static
// state instead of looping.

/// A blinking phosphor block caret — the signature terminal cursor. Use it in
/// the empty state and the streaming indicator.
public struct BlinkingCaret: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var on = true
    private let width: CGFloat
    private let height: CGFloat

    public init(width: CGFloat = 8, height: CGFloat = 16) {
        self.width = width
        self.height = height
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(Theme.C.phosphor)
            .frame(width: width, height: height)
            .opacity(on ? 1 : (reduceMotion ? 1 : 0.08))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                    on.toggle()
                }
            }
            .accessibilityHidden(true)
    }
}

private struct PulsingModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsed = false
    var minOpacity: Double
    var duration: Double

    func body(content: Content) -> some View {
        content
            .opacity(reduceMotion ? 1 : (pulsed ? minOpacity : 1))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: true)) {
                    pulsed = true
                }
            }
    }
}

public extension View {
    /// Gentle opacity pulse for live "heartbeat" signals (active-now dot,
    /// streaming markers). No-op under Reduce Motion.
    func pulsing(minOpacity: Double = 0.35, duration: Double = 0.85) -> some View {
        modifier(PulsingModifier(minOpacity: minOpacity, duration: duration))
    }
}
