import XCTest
import SwiftUI
@testable import SkriftMobile

/// Q300 / D179: the feedback sheet + button draw in Skrift's palette and follow the
/// app theme (the sheet itself is forced light by FeedbackKit, so the rule reads
/// `appTheme`, not the view trait).
final class FeedbackPaletteTests: XCTestCase {
    func testThemeRuleFollowsAppTheme() {
        XCTAssertTrue(FeedbackPalette.isDark(themeRaw: "dark", systemDark: false))
        XCTAssertFalse(FeedbackPalette.isDark(themeRaw: "light", systemDark: true))
        XCTAssertTrue(FeedbackPalette.isDark(themeRaw: "auto", systemDark: true))
        XCTAssertFalse(FeedbackPalette.isDark(themeRaw: "auto", systemDark: false))
        // unset = the app default, which is dark
        XCTAssertTrue(FeedbackPalette.isDark(themeRaw: nil, systemDark: false))
    }

    func testColorResolvesToSkriftPaletteEvenInAForcedLightTrait() {
        let saved = UserDefaults.standard.string(forKey: ThemePreference.key)
        defer { UserDefaults.standard.set(saved, forKey: ThemePreference.key) }
        let ui = UIColor(FeedbackPalette.color(Palette.bg.phone))
        let light = UITraitCollection(userInterfaceStyle: .light)

        UserDefaults.standard.set("dark", forKey: ThemePreference.key)
        XCTAssertEqual(rgb(ui.resolvedColor(with: light)), rgb(Palette.bg.phone.dark))
        UserDefaults.standard.set("light", forKey: ThemePreference.key)
        XCTAssertEqual(rgb(ui.resolvedColor(with: light)), rgb(Palette.bg.phone.light))
    }

    private func rgb(_ c: UIColor) -> UInt32 {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (UInt32((r * 255).rounded()) << 16) | (UInt32((g * 255).rounded()) << 8) | UInt32((b * 255).rounded())
    }

    private func rgb(_ hex: UInt32) -> UInt32 { hex }
}
