import XCTest
import SwiftUI
@testable import SkriftMobile

/// Q119, for the eyes: the iPad Connections panel's new AI-zone states (the Mac's
/// downloading / preparing / indexing + the "Connections unavailable" failure line)
/// at the panel's width on its surface. Point `SKRIFT_RENDER_DIR` at a folder to
/// keep the PNG.
@MainActor
final class ConnectionsStatesRenderQ119Tests: XCTestCase {
    func testRenderTheNewPanelStates() throws {
        let panel = ConnectionsPanel(memo: Memo(transcript: "The harbor at dawn.", significance: 0.6))
        let sheet = VStack(spacing: 0) {
            panel.progressHint(title: RetrievalGate.Copy.downloadingTitle,
                               sub: RetrievalGate.Copy.downloadingSub(fraction: 0.4),
                               fraction: 0.4, fill: Color.skAccent)
            panel.progressHint(title: RetrievalGate.Copy.preparingTitle,
                               sub: RetrievalGate.Copy.preparingSub,
                               fraction: 1, fill: Color.skAccent)
            panel.progressHint(title: RetrievalGate.Copy.indexingTitle,
                               sub: RetrievalGate.Copy.indexingSub(done: 37, total: 120),
                               fraction: 37.0 / 120.0, fill: Color.skGreen)
            panel.unavailableState("Related lookup failed: The operation couldn’t be completed. (EmbeddingIndex error 1.)")
        }
        .padding(.horizontal, 16)
        .frame(width: Adaptive.sidePanelWidth)
        .background(Color.skSurface)
        .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.uiImage)
        XCTAssertGreaterThan(image.size.height, 300, "the state views collapsed")
        let dir = ProcessInfo.processInfo.environment["SKRIFT_RENDER_DIR"] ?? NSTemporaryDirectory()
        try XCTUnwrap(image.pngData()).write(
            to: URL(fileURLWithPath: dir).appendingPathComponent("q119-ipad-connections-states.png"))
    }
}
