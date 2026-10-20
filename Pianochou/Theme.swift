import SwiftUI
import UIKit

/// Design tokens from CLAUDE.md. Each color has a light (paper) and dark (evening) value.
enum Theme {
    static let paper = dynamic(light: 0xF6F6F3, dark: 0x0E0E0D)
    static let ink = dynamic(light: 0x121212, dark: 0xEDEDE9)
    static let muted = dynamic(light: 0x6A6A66, dark: 0x9A9A95)
    static let hairline = dynamic(light: 0xDCDCD7, dark: 0x2A2A28)
    static let now = dynamic(light: 0x1F4FE0, dark: 0x8AA6FF)
    static let fix = dynamic(light: 0xC2410C, dark: 0xFB923C)

    // Staff colors, from the playing-screen mockup.
    static let staffLine = dynamic(light: 0x121212, dark: 0x5E5E5A)
    /// Notes already played.
    static let played = dynamic(light: 0xBDBDB8, dark: 0x4A4A47)
    /// Finger numbers and counts already played.
    static let playedText = dynamic(light: 0x73736F, dark: 0x8A8A85)
    /// The current-beat band behind the staff.
    static let band = dynamic(light: 0x1F4FE0, dark: 0x8AA6FF, lightAlpha: 0.08, darkAlpha: 0.14)

    /// Hanken Grotesk at a given size; it is a variable font, so `.weight()` works on it.
    static func text(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom("Hanken Grotesk", size: size, relativeTo: style)
    }

    /// Bravura (SMuFL) for music glyphs. Fixed size: staff glyphs must not scale with Dynamic Type.
    static func music(_ size: CGFloat) -> Font {
        .custom("Bravura", fixedSize: size)
    }

    private static func dynamic(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(rgb: dark).withAlphaComponent(darkAlpha)
                : UIColor(rgb: light).withAlphaComponent(lightAlpha)
        })
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
