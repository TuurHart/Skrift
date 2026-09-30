import XCTest
import SwiftUI
@testable import SkriftMobile

/// Q88, for the eyes: the pill row on the share sheet's dark surface (#1b1d28) in each
/// state — the share extension and the audiobook capture sheet both draw exactly this
/// `PhoneRatingRow`. Point `SKRIFT_RENDER_DIR` at a folder to keep the PNG.
@MainActor
final class RatingRowSheetRenderQ88Tests: XCTestCase {
    func testRenderThePillOnTheShareSheetSurface() throws {
        let sheet = VStack(alignment: .leading, spacing: 22) {
            PhoneRatingRow(value: .constant(0))
            PhoneRatingRow(value: .constant(0.5))
            PhoneRatingRow(value: .constant(0.8))
            PhoneRatingRow(value: .constant(1.0))
            PhoneRatingRow(value: .constant(0), fadingLine: "starts fading in 30d — rate it to keep it")
        }
        .padding(16)
        .frame(width: 390, alignment: .leading)
        .background(Color(red: 0.106, green: 0.110, blue: 0.157))
        .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.uiImage)
        XCTAssertGreaterThan(image.size.height, 150, "the pill rows collapsed")
        let dir = ProcessInfo.processInfo.environment["SKRIFT_RENDER_DIR"] ?? NSTemporaryDirectory()
        try XCTUnwrap(image.pngData()).write(
            to: URL(fileURLWithPath: dir).appendingPathComponent("capture-sheet-pill.png"))
    }
}
