import SwiftUI
import UIKit

// Grateful Day design foundation. Colours are the web app's palette
// (gratefulday `src/index.css`, :root and .dark), so both apps look like one
// product. Every colour adapts to Dark Mode; every font is a system text
// style, so it follows Dynamic Type.

enum GDColor {
    static let background = dynamic(light: (30, 40, 98), dark: (20, 15, 10))
    static let foreground = dynamic(light: (20, 10, 20), dark: (30, 25, 95))
    static let card = dynamic(light: (0, 0, 100), dark: (20, 20, 14))
    static let secondary = dynamic(light: (35, 100, 94), dark: (25, 20, 20))
    static let mutedForeground = dynamic(light: (25, 15, 45), dark: (30, 15, 65))
    static let border = dynamic(light: (30, 25, 88), dark: (25, 15, 22))
    /// Web `--primary`. For tints and icons only: it is too light for body
    /// text on the background.
    static let accent = dynamic(light: (25, 95, 53), dark: (25, 90, 60))

    /// HSL triples (degrees, percent, percent), as written in the web CSS.
    typealias HSL = (h: Double, s: Double, l: Double)

    static func dynamic(light: HSL, dark: HSL) -> Color {
        Color(uiColor: UIColor { traits in
            uiColor(traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    static func uiColor(_ hsl: HSL) -> UIColor {
        let (r, g, b) = rgb(hsl)
        return UIColor(red: r, green: g, blue: b, alpha: 1)
    }

    /// Standard HSL → RGB, components in 0...1.
    static func rgb(_ hsl: HSL) -> (Double, Double, Double) {
        let s = hsl.s / 100, l = hsl.l / 100
        let c = (1 - abs(2 * l - 1)) * s
        let hp = hsl.h.truncatingRemainder(dividingBy: 360) / 60
        let x = c * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1))
        let (r1, g1, b1): (Double, Double, Double)
        switch hp {
        case ..<1: (r1, g1, b1) = (c, x, 0)
        case ..<2: (r1, g1, b1) = (x, c, 0)
        case ..<3: (r1, g1, b1) = (0, c, x)
        case ..<4: (r1, g1, b1) = (0, x, c)
        case ..<5: (r1, g1, b1) = (x, 0, c)
        default: (r1, g1, b1) = (c, 0, x)
        }
        let m = l - c / 2
        return (r1 + m, g1 + m, b1 + m)
    }
}

/// Type scale: system text styles only, so Dynamic Type applies everywhere.
enum GDFont {
    static let dateTitle = Font.system(.largeTitle, design: .serif).weight(.semibold)
    static let sectionLabel = Font.subheadline.weight(.medium)
    static let body = Font.body
    static let wisdomPassage = Font.system(.title3, design: .serif)
}

/// Spacing scale (points).
enum GDSpacing {
    static let small: CGFloat = 8
    static let medium: CGFloat = 16
    static let large: CGFloat = 24
}

enum GDRadius {
    /// Web `--radius: 1rem`.
    static let card: CGFloat = 16
}
