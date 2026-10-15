import XCTest
@testable import SkriftMobile

/// Q469 (C29, C30): the phone's v1 Polish holds `[[vid_N]]` / `[[file_N]]` markers like the
/// Mac's `CopyEditPipeline` — the model never sees them, they return by paragraph index.
final class PolishEscrowAttachmentTests: XCTestCase {
    func testAttachmentsNeverReachTheModelAndComeBackByParagraph() async throws {
        let body = "[[vid_1]]\n\nwe fed the goats.\n\nhere is the invoice [[file_1]] for the trailer.\n\nthen home."
        var seen: [String] = []
        let out = try await PolishEscrow.copyEdit(body) { input in
            seen.append(input)
            return "We fed the goats.\n\nHere is the invoice for the trailer.\n\nThen home."
        }
        XCTAssertEqual(seen.count, 1)
        XCTAssertFalse(seen[0].contains("[["), seen[0])
        XCTAssertEqual(out, "[[vid_1]]\n\nWe fed the goats.\n\nHere is the invoice for the trailer.\n\n[[file_1]]\n\nThen home.")
    }

    func testNoAttachmentsMeansTheSameInputAsBefore() async throws {
        let body = "a picture [[img_001]] here.\n\nand more."
        var seen = ""
        _ = try await PolishEscrow.copyEdit(body) { seen = $0; return $0 }
        XCTAssertEqual(seen, ImageMarkerReinsert.extractAnchors(body).stripped)
    }
}
