import XCTest

/// Q469 (gate+, C29, C30): `[[vid_N]]` / `[[file_N]]` attachment markers are held like picture
/// paragraphs by copy-edit v2 — stripped before the model, returned after the same-index
/// text paragraph of the output (v1's own escrow went with v1, Q427). MLX-free: the model is a stub that records what it saw.
final class AttachmentMarkerEscrowTests: XCTestCase {
    /// A video import's kept movie leads (Q454); a file sits mid-paragraph.
    static let body = """
        [[vid_1]]

        we drove up to the farm and fed the goats.

        here is the invoice [[file_1]] for the trailer.

        then we drove home.
        """
    static let edit = """
        We drove up to the farm and fed the goats.

        Here is the invoice for the trailer.

        Then we drove home.
        """
    static let expected = """
        [[vid_1]]

        We drove up to the farm and fed the goats.

        Here is the invoice for the trailer.

        [[file_1]]

        Then we drove home.
        """

    final class Seen: @unchecked Sendable { var inputs: [String] = [] }

    static func assertProseOnly(_ inputs: [String], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(inputs.count, 1, file: file, line: line)
        for input in inputs {
            XCTAssertFalse(input.contains("vid_") || input.contains("file_") || input.contains("[["),
                           "the model sees prose only (C29): \(input)", file: file, line: line)
            XCTAssertEqual(CopyEditV2.paragraphs(input).count, 3, "the text paragraphs reach the model intact",
                           file: file, line: line)
        }
    }

    // MARK: - v2

    func testV2HoldsAttachmentsLikePictures() async throws {
        let seen = Seen()
        let r = try await CopyEditV2.copyEdit(Self.body, spoken: true, prompt: "P") { _, text, _ in
            seen.inputs.append(text); return Self.edit
        }
        Self.assertProseOnly(seen.inputs)
        XCTAssertNil(r.fallback)
        XCTAssertEqual(r.text, Self.expected)
        XCTAssertEqual(CopyEditV2.prose(Self.body), seen.inputs.first, "title and summary read the same prose")
    }

    func testV2AModelDroppingMarkersCannotLoseThem() async throws {
        // Before Q469 v2 escrowed `[[vid_1]]` as a wikilink showing "vid_1": a model that dropped
        // that word failed the link guard and the whole edit was lost.
        let r = try await CopyEditV2.copyEdit(Self.body, spoken: true, prompt: "P") { _, _, _ in Self.edit }
        XCTAssertNotEqual(r.fallback, .linkLost)
        XCTAssertEqual(NoteAttachment.markers(in: r.text).map(\.number), [1, 1])
    }
}
