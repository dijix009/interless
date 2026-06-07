import SwiftUI
import AppKit

// MARK: - Design Token Foundation
//
// Native macOS token ramp. Colors are backed by dynamic NSColor so they resolve
// per appearance without requiring an asset catalog.

private extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
    }
}

private func dynamicColor(light: NSColor, dark: NSColor) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
    })
}

public enum Theme {
    public enum C {
        public static let bg            = dynamicColor(light: NSColor(hex: 0xF4F1ED), dark: NSColor(hex: 0x11100F))
        public static let surface       = dynamicColor(light: NSColor(hex: 0xFFFCF8), dark: NSColor(hex: 0x171514))
        public static let surface2      = dynamicColor(light: NSColor(hex: 0xEEE8E1), dark: NSColor(hex: 0x1F1C1A))
        public static let surface3      = dynamicColor(light: NSColor(hex: 0xE3D9CF), dark: NSColor(hex: 0x2A2522))
        public static let sidebar       = dynamicColor(light: NSColor(hex: 0xE9E2DA), dark: NSColor(hex: 0x151312))
        public static let textPrimary   = dynamicColor(light: NSColor(hex: 0x25211D), dark: NSColor(hex: 0xEEE7DE))
        public static let textSecondary = dynamicColor(light: NSColor(hex: 0x5C554D), dark: NSColor(hex: 0xBDB5AA))
        public static let textTertiary  = dynamicColor(light: NSColor(hex: 0x8B8176), dark: NSColor(hex: 0x7D746B))
        public static let border        = dynamicColor(light: NSColor(hex: 0x3B2F26, alpha: 0.10), dark: NSColor(hex: 0xF6E5D2, alpha: 0.08))
        public static let borderHover   = dynamicColor(light: NSColor(hex: 0x3B2F26, alpha: 0.18), dark: NSColor(hex: 0xF6E5D2, alpha: 0.15))
        public static let accent        = dynamicColor(light: NSColor(hex: 0xC55A11), dark: NSColor(hex: 0xE0701B))
        public static let accent2       = dynamicColor(light: NSColor(hex: 0x8C4F18), dark: NSColor(hex: 0xEDB449))
        public static let accentGlow    = dynamicColor(light: NSColor(hex: 0xD96A18, alpha: 0.12), dark: NSColor(hex: 0xE0701B, alpha: 0.18))
        public static let diffAdd       = dynamicColor(light: NSColor(hex: 0x4F8A10), dark: NSColor(hex: 0x9BB344))
        public static let diffDel       = dynamicColor(light: NSColor(hex: 0xB03A2E), dark: NSColor(hex: 0xE65F55))
        public static let danger        = dynamicColor(light: NSColor(hex: 0xD7263D), dark: NSColor(hex: 0xF87171))
    }
}

// MARK: - Typography

public extension Font {
    static let displayLg = Font.system(size: 22, weight: .bold)
    static let displayMd = Font.system(size: 17, weight: .semibold)
    static let titleS    = Font.system(size: 15, weight: .semibold)
    static let bodyS     = Font.system(size: 13)
    static let labelMono = Font.system(size: 11, weight: .medium, design: .monospaced)
    static let metaMono  = Font.system(size: 11, design: .monospaced)
    static let codeMono  = Font.system(size: 12, design: .monospaced)
}

// MARK: - Spacing & radius

public extension CGFloat {
    static let space1: CGFloat = 4
    static let space2: CGFloat = 8
    static let space3: CGFloat = 12
    static let space4: CGFloat = 16
    static let space5: CGFloat = 24
    static let radius: CGFloat = 12
    static let radiusSm: CGFloat = 8
}

// MARK: - Surface modifiers (replace the ad-hoc .regularMaterial / .thinMaterial mix)

public extension View {
    /// Primary working canvas — solid, never translucent.
    func primarySurface() -> some View {
        background(Theme.C.surface)
    }

    /// Quiet chrome (pane headers, rails, strips).
    func chromeSurface() -> some View {
        background(Theme.C.sidebar)
    }

    /// Elevated floating overlay (command palette, popovers).
    func overlaySurface(radius: CGFloat = .radius) -> some View {
        background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    /// Bordered card on a secondary surface.
    func card(radius: CGFloat = .radiusSm) -> some View {
        background(Theme.C.surface2, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Theme.C.border, lineWidth: 1))
    }
}

// MARK: - Section label (replaces the repeated `Label + .headline` pane headers)

public struct SectionLabel: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text.uppercased())
            .font(.labelMono)
            .tracking(1.3)
            .foregroundStyle(Theme.C.textTertiary)
    }
}

// MARK: - Shared diff palette (de-duplicates DiffViewer & PatchReviewView)

public enum DiffPalette {
    public static func foreground(_ kind: DiffLineKind) -> Color {
        switch kind {
        case .addition: return Theme.C.diffAdd
        case .deletion: return Theme.C.diffDel
        case .hunk, .file: return Theme.C.textSecondary
        case .context: return Theme.C.textPrimary
        }
    }

    public static func background(_ kind: DiffLineKind) -> Color {
        switch kind {
        case .addition: return Theme.C.diffAdd.opacity(0.12)
        case .deletion: return Theme.C.diffDel.opacity(0.12)
        case .hunk, .file: return Theme.C.surface3.opacity(0.6)
        case .context: return .clear
        }
    }

    public static func foreground(_ kind: PatchLineKind) -> Color {
        switch kind {
        case .addition: return Theme.C.diffAdd
        case .deletion: return Theme.C.diffDel
        case .context: return Theme.C.textPrimary
        }
    }

    public static func background(_ kind: PatchLineKind) -> Color {
        switch kind {
        case .addition: return Theme.C.diffAdd.opacity(0.12)
        case .deletion: return Theme.C.diffDel.opacity(0.12)
        case .context: return .clear
        }
    }

    /// Gutter glyph so add/delete is not conveyed by color alone (a11y).
    public static func glyph(_ kind: DiffLineKind) -> String {
        switch kind {
        case .addition: return "+"
        case .deletion: return "-"
        case .hunk, .file, .context: return " "
        }
    }
}
