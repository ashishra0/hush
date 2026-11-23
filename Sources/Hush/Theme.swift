import AppKit
import SwiftUI

/// Vercel Geist tokens (https://vercel.com/geist): gray scale, background-100/200, blue-700. See docs/DESIGN.md. Dynamic colors resolve light/dark per appearance.
enum Theme {
    private static func nsDyn(_ light: UInt32, _ dark: UInt32) -> NSColor {
        func ns(_ hex: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        return NSColor(name: nil) { appearance in
            ns(appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light)
        }
    }
    private static func dyn(_ light: UInt32, _ dark: UInt32) -> Color { Color(nsColor: nsDyn(light, dark)) }

    // AppKit-side (text fields, caret) equivalents.
    static let nsInk = nsDyn(0x171717, 0xEDEDED)
    static let nsAccent = nsDyn(0x0070F3, 0x0070F3)
    static func nsSans(_ size: CGFloat) -> NSFont { NSFont(name: "Geist", size: size) ?? .systemFont(ofSize: size) }

    /// background-200: popover body, so the background-100 capture field reads as a field.
    static let popover = dyn(0xFAFAFA, 0x000000)
    static let ground = dyn(0xFAFAFA, 0x000000)        // background-200
    static let surface = dyn(0xFFFFFF, 0x0A0A0A)       // background-100
    static let surfaceSunk = dyn(0xF2F2F2, 0x1A1A1A)   // gray-100: hover, keycap fill
    static let selection = dyn(0xF2F2F2, 0x1A1A1A)     // gray-100: the one selected row (neutral, Geist-style)
    static let hover = dyn(0xFAFAFA, 0x111111)         // lighter than selection so the two never read alike
    static let hairline = dyn(0xEBEBEB, 0x2E2E2E)      // gray-400 (alpha-equivalent on bg-100)
    static let ink = dyn(0x171717, 0xEDEDED)           // gray-1000
    static let inkMute = dyn(0x666666, 0xA1A1A1)       // gray-900
    static let inkFaint = dyn(0xA1A1A1, 0x6E6E6E)      // placeholder, done, counts
    /// blue-700. ONLY caret, focus ring, drop line, completion fill.
    static let accent = dyn(0x0070F3, 0x0070F3)
    static let accentWash = selection

    static let captureFont = Font.geist(size: 22)
    static let rowFont = Font.geist(size: 14)
    static let bodyFont = Font.geist(size: 14)
    static let captionFont = Font.geist(size: 12)
    static let keycapFont = Font.geist(size: 11, design: .monospaced)

    // Spacing (4pt grid) and radii
    static let s1: CGFloat = 4, s2: CGFloat = 8, s3: CGFloat = 12, s4: CGFloat = 16, s6: CGFloat = 24
    static let rKeycap: CGFloat = 4, rRow: CGFloat = 6, rPopover: CGFloat = 12, rModal: CGFloat = 12
    static let rowHeight: CGFloat = 32

    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
}

/// Inline keycap (Paper "Keyboard shortcut indicators"): SF Pro glyphs, 20 high, 22+ wide, surface-sunk + 1px hairline.
struct Keycap: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.geist(size: 12))
            .foregroundStyle(Theme.inkMute)
            .padding(.horizontal, 6)
            .frame(minWidth: 22, minHeight: 20)
            .background(Theme.surfaceSunk, in: RoundedRectangle(cornerRadius: Theme.rKeycap))
            .overlay(RoundedRectangle(cornerRadius: Theme.rKeycap).strokeBorder(Theme.hairline, lineWidth: 1))
            .accessibilityLabel(text)
    }
}

extension Font {
    /// Geist Sans / Geist Mono, bundled in Hush.app/Contents/Resources/Fonts (OFL). Falls back to system if missing.
    static func geist(size: CGFloat, weight: Weight = .regular, design: Design = .default) -> Font {
        .custom(design == .monospaced ? "Geist Mono" : "Geist", fixedSize: size).weight(weight)
    }
}
