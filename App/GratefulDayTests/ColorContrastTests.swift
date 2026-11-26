import XCTest
import SwiftUI
import UIKit
@testable import GratefulDay

/// Chief P58/P59: text colours must reach WCAG AA (4.5:1) on every surface
/// they're drawn on, in light and dark mode. Arithmetic on the real tokens,
/// so it doesn't depend on what an audit screenshot happens to sample.
final class ColorContrastTests: XCTestCase {
    private let texts: [(String, Color)] = [
        ("mutedForeground", GDColor.mutedForeground),
        ("foreground", GDColor.foreground),
    ]
    private let surfaces: [(String, Color)] = [
        ("background", GDColor.background),
        ("secondary", GDColor.secondary),
        ("card", GDColor.card),
    ]

    func testTextColoursReachAAOnEverySurface() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            for (textName, text) in texts {
                for (surfaceName, surface) in surfaces {
                    let ratio = Self.contrast(text, surface, traits)
                    XCTAssertGreaterThanOrEqual(ratio, 4.5,
                        "\(textName) on \(surfaceName), \(style == .dark ? "dark" : "light"): \(String(format: "%.2f", ratio)):1")
                }
            }
        }
    }

    /// WCAG 2 contrast ratio between two resolved colours.
    static func contrast(_ a: Color, _ b: Color, _ traits: UITraitCollection) -> Double {
        let la = luminance(a, traits), lb = luminance(b, traits)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// WCAG 2 relative luminance of `color` in the given trait environment.
    static func luminance(_ color: Color, _ traits: UITraitCollection) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, alpha: CGFloat = 0
        UIColor(color).resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &alpha)
        func linear(_ c: CGFloat) -> Double {
            let v = Double(c)
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }
}
