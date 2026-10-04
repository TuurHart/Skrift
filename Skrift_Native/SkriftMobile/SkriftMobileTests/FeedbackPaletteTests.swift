import XCTest
import SwiftUI
import FeedbackKit
@testable import SkriftMobile

/// Q300 / Q305 / D179: the feedback sheet + button draw in Skrift's palette. FeedbackKit
/// no longer forces its sheet light (`interfaceStyle: .unspecified`), so the tokens are the
/// ordinary dynamic ones and resolve against the trait the sheet inherits.
@MainActor
final class FeedbackPaletteTests: XCTestCase {
    func testSheetFollowsTheHostInterfaceStyleAndDrawsWhiteOnAccent() {
        let a = FeedbackPalette.appearance(privacyLine: "x")
        XCTAssertEqual(a.interfaceStyle, .unspecified)
        XCTAssertEqual(rgb(UIColor(a.onAccent)), 0xffffff)
    }

    func testColoursResolveAgainstTheTrait() {
        let a = FeedbackPalette.appearance(privacyLine: "x")
        let light = UITraitCollection(userInterfaceStyle: .light)
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        XCTAssertEqual(rgb(UIColor(a.background).resolvedColor(with: dark)), Palette.bg.phone.dark)
        XCTAssertEqual(rgb(UIColor(a.background).resolvedColor(with: light)), Palette.bg.phone.light)
        XCTAssertEqual(rgb(UIColor(a.accent).resolvedColor(with: dark)), Palette.accent.dark)
        XCTAssertEqual(rgb(UIColor(a.recording).resolvedColor(with: light)), Palette.red.light)
    }

    private func rgb(_ c: UIColor) -> UInt32 {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, al: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &al)
        return (UInt32((r * 255).rounded()) << 16) | (UInt32((g * 255).rounded()) << 8) | UInt32((b * 255).rounded())
    }
}
