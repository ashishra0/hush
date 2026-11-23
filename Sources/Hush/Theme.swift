import AppKit
import SwiftUI

/// Design tokens from docs/DESIGN.md. Dynamic colors resolve light/dark per appearance.
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
    static let nsInk = nsDyn(0x1C1C1E, 0xF2F2F3)
    static let nsAccent = nsDyn(0x0852FF, 0x3D7BFF)

    static let ground = dyn(0xEBEBEB, 0x0B0B0C)
    static let surface = dyn(0xFFFFFF, 0x1A1A1C)
    static let surfaceSunk = dyn(0xF5F5F6, 0x232326)
    static let hairline = dyn(0xDCDCDF, 0x2E2E32)
    static let ink = dyn(0x1C1C1E, 0xF2F2F3)
    static let inkMute = dyn(0x6E6E73, 0x8E8E93)
    static let inkFaint = dyn(0xA1A1A6, 0x5A5A5F)
    /// ONLY caret, focus ring, selection, drop line, completion fill.
    static let accent = dyn(0x0852FF, 0x3D7BFF)
    static let accentWash = dyn(0xE8EEFF, 0x14224A)

    static let captureFont = Font.system(size: 24, weight: .light)
    static let rowFont = Font.system(size: 15)
    static let bodyFont = Font.system(size: 14)
    static let captionFont = Font.system(size: 12)
    static let keycapFont = Font.system(size: 11, design: .monospaced)

    // Spacing (4pt grid) and radii
    static let s1: CGFloat = 4, s2: CGFloat = 8, s3: CGFloat = 12, s4: CGFloat = 16, s6: CGFloat = 24
    static let rKeycap: CGFloat = 4, rRow: CGFloat = 6, rPopover: CGFloat = 10, rModal: CGFloat = 14
    static let rowHeight: CGFloat = 32

    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
}

struct Keycap: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Theme.keycapFont)
            .foregroundStyle(Theme.inkMute)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 18)
            .background(Theme.surfaceSunk, in: RoundedRectangle(cornerRadius: Theme.rKeycap))
            .overlay(RoundedRectangle(cornerRadius: Theme.rKeycap).strokeBorder(Theme.hairline, lineWidth: 1))
    }
}
