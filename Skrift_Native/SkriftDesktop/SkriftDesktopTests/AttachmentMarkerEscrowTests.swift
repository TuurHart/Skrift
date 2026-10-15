import XCTest

/// Q469 (gate+, C29, C30): `[[vid_N]]` / `[[file_N]]` attachment markers are held like picture
/// paragraphs in BOTH copy-edits — stripped before the model, returned after the same-index
/// text paragraph of the output. MLX-free: the model is a stub that records what it saw.
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

    // MARK: - v1 (live)

    func testV1HoldsAttachmentsLikePictures() async throws {
        let seen = Seen()
        let out = try await CopyEditPipeline.copyEdit(Self.body, prompts: AppSettings.Prompts()) { _, text, _ in
            seen.inputs.append(text); return Self.edit
        }
        Self.assertProseOnly(seen.inputs)
        XCTAssertEqual(out, Self.expected)
    }

    func testV1AModelThatMergesParagraphsStillKeepsEveryMarker() async throws {
        let wall = "We drove up to the farm and fed the goats. Here is the invoice for the trailer. Then we drove home."
        let out = try await CopyEditPipeline.copyEdit(Self.body, prompts: AppSettings.Prompts()) { _, _, _ in wall }
        XCTAssertTrue(out.hasPrefix("[[vid_1]]\n\n"), out)
        XCTAssertEqual(NoteAttachment.markers(in: out).count, 2, "neither marker is lost: \(out)")
    }

    func testV1PicturesAndAttachmentsTogether() async throws {
        let body = "[[vid_1]]\n\nfirst we fed the goats [[img_001]] by the barn.\n\nthe invoice [[file_1]] is here."
        let seen = Seen()
        let out = try await CopyEditPipeline.copyEdit(body, prompts: AppSettings.Prompts()) { _, text, _ in
            seen.inputs.append(text); return "First we fed the goats by the barn.\n\nThe invoice is here."
        }
        XCTAssertFalse(seen.inputs[0].contains("[["), seen.inputs[0])
        XCTAssertTrue(out.hasPrefix("[[vid_1]]\n\n"), out)
        XCTAssertTrue(out.contains("[[img_001]]"), out)
        XCTAssertTrue(out.hasSuffix("The invoice is here.\n\n[[file_1]]"), out)
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

    // MARK: - the escrow itself

    func testHoldIsTheIdentityWithoutAttachments() {
        let text = "a picture [[img_001]] and [[memo:00000000-0000-0000-0000-000000000000|a link]]\n\n\nkept"
        let held = AttachmentMarkerEscrow.hold(text)
        XCTAssertEqual(held.prose, text, "notes without attachments reach the model byte for byte (recorded keys)")
        XCTAssertEqual(AttachmentMarkerEscrow.place(held.markers, in: "edited"), "edited")
    }

    func testPlacementClampsToTheEnd() {
        let held = AttachmentMarkerEscrow.hold("one.\n\ntwo.\n\nthree [[file_002]]")
        XCTAssertEqual(held.markers, [.init(marker: "[[file_002]]", after: 3)])
        XCTAssertEqual(AttachmentMarkerEscrow.place(held.markers, in: "One, two, three."), "One, two, three.\n\n[[file_002]]")
    }
}
