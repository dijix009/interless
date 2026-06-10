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

/// User-selectable appearance override. Persisted via AppStorage under
/// "appearance.mode" and applied at the app root with `.preferredColorScheme`.
public enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

public enum Theme {
    // MARK: Color semantics (dual-accent identity)
    //
    // Interless runs two disciplined accents. They must never blur together.
    //
    //   • `accent` / `accent2` — AMBER. The brand. Anything the *user* drives:
    //     primary actions, send, focus rings, selection, brand chrome. Amber-CRT
    //     warmth is the resting identity.
    //
    //   • `phosphor` — GREEN. "The machine is alive." Used *only* for live/active
    //     signal: the running agent, active sessions, streaming, live telemetry,
    //     the input caret. This is the deliberate Matrix nod — never decorative.
    //
    //   • `diffAdd` / `diffDel` — diffs ONLY. Never reuse for live state or badges.
    //
    // Dark is the hero appearance; light is a quiet, clean counterpart.
    public enum C {
        public static let bg            = dynamicColor(light: NSColor(hex: 0xF4F1ED), dark: NSColor(hex: 0x11100F))
        public static let surface       = dynamicColor(light: NSColor(hex: 0xFFFCF8), dark: NSColor(hex: 0x171514))
        public static let surface2      = dynamicColor(light: NSColor(hex: 0xEEE8E1), dark: NSColor(hex: 0x1F1C1A))
        public static let surface3      = dynamicColor(light: NSColor(hex: 0xE3D9CF), dark: NSColor(hex: 0x2A2522))
        public static let sidebar       = dynamicColor(light: NSColor(hex: 0xE9E2DA), dark: NSColor(hex: 0x151312))
        public static let textPrimary   = dynamicColor(light: NSColor(hex: 0x25211D), dark: NSColor(hex: 0xEEE7DE))
        public static let textSecondary = dynamicColor(light: NSColor(hex: 0x5C554D), dark: NSColor(hex: 0xBDB5AA))
        // textTertiary tuned to clear WCAG AA (4.5:1) for small text in both modes.
        public static let textTertiary  = dynamicColor(light: NSColor(hex: 0x6A625A), dark: NSColor(hex: 0x938A7F))
        public static let border        = dynamicColor(light: NSColor(hex: 0x3B2F26, alpha: 0.12), dark: NSColor(hex: 0xF6E5D2, alpha: 0.14))
        public static let borderHover   = dynamicColor(light: NSColor(hex: 0x3B2F26, alpha: 0.20), dark: NSColor(hex: 0xF6E5D2, alpha: 0.22))

        // Amber brand accents (user-driven). Light variants darkened to keep white
        // text on `accent` and small `accent2` text above AA.
        public static let accent        = dynamicColor(light: NSColor(hex: 0xB35210), dark: NSColor(hex: 0xE0701B))
        public static let accent2       = dynamicColor(light: NSColor(hex: 0x8A5E12), dark: NSColor(hex: 0xEDB449))
        public static let accentGlow    = dynamicColor(light: NSColor(hex: 0xB35210, alpha: 0.12), dark: NSColor(hex: 0xE0701B, alpha: 0.18))

        // Green phosphor — live/active signal ONLY (see semantics note above).
        public static let phosphor      = dynamicColor(light: NSColor(hex: 0x167A3F), dark: NSColor(hex: 0x46E08B))
        public static let phosphorGlow  = dynamicColor(light: NSColor(hex: 0x167A3F, alpha: 0.12), dark: NSColor(hex: 0x46E08B, alpha: 0.16))

        // Diffs only.
        public static let diffAdd       = dynamicColor(light: NSColor(hex: 0x4F8A10), dark: NSColor(hex: 0x9BB344))
        public static let diffDel       = dynamicColor(light: NSColor(hex: 0xB03A2E), dark: NSColor(hex: 0xE65F55))

        // Status semantics (replace ad-hoc `.orange` / `.red` / `.blue` / `.green`).
        public static let caution       = dynamicColor(light: NSColor(hex: 0x9A6212), dark: NSColor(hex: 0xE0A03A))
        public static let danger        = dynamicColor(light: NSColor(hex: 0xD7263D), dark: NSColor(hex: 0xF87171))
        public static let info          = dynamicColor(light: NSColor(hex: 0x2C6E8F), dark: NSColor(hex: 0x6FC2DE))
        /// Ready/installed/healthy success — distinct from live `phosphor` and diffs.
        public static let success       = dynamicColor(light: NSColor(hex: 0x167A3F), dark: NSColor(hex: 0x46E08B))
    }
}

// MARK: - Typography

public extension Font {
    // Each token maps to a system text style so it scales with the user's
    // Dynamic Type setting (WCAG 1.4.4). The styles are chosen to preserve a
    // clean, strictly descending ramp at the default size (macOS point sizes
    // noted), so hierarchy is consistent: header > subhead > title > body ≥
    // code > label = meta > small-meta.
    //
    //   displayLg  .title       22  — page / app title
    //   displayMd  .title2      17  — section header
    //   titleS     .title3      15  — card / sub-section title
    //   bodyS      .body        13  — body text
    //   codeMono   .body mono   13  — code (matches body, stays readable)
    //   labelMono  .subheadline 11  — uppercase section labels
    //   metaMono   .subheadline 11  — metadata / timestamps
    //   metaMonoSm .footnote    10  — smallest meta (pills, badges)
    static let displayLg = Font.system(.title, design: .default).weight(.bold)
    static let displayMd = Font.system(.title2, design: .default).weight(.semibold)
    static let titleS    = Font.system(.title3, design: .default).weight(.semibold)
    static let bodyS     = Font.system(.body, design: .default)
    static let codeMono  = Font.system(.body, design: .monospaced)
    static let labelMono = Font.system(.subheadline, design: .monospaced).weight(.medium)
    static let metaMono  = Font.system(.subheadline, design: .monospaced)
    static let metaMonoSm = Font.system(.footnote, design: .monospaced).weight(.semibold)
    /// Inline pill/control glyphs & chevrons (decorative icons; kept small & fixed).
    static let controlGlyph = Font.system(size: 9, weight: .semibold)
    static let controlGlyphSm = Font.system(size: 7, weight: .bold)
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
    static let radiusLg: CGFloat = 14
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

    /// Soft phosphor halo for "live/active" signal elements (agent badge, active
    /// dot). The deliberate Matrix glow — kept restrained so the UI stays clean.
    func phosphorGlow(_ active: Bool = true, radius: CGFloat = 5) -> some View {
        shadow(color: active ? Theme.C.phosphor.opacity(0.55) : .clear, radius: radius)
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
