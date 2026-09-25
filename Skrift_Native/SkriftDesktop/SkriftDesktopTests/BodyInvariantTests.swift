import XCTest

/// C6 body invariants, asserted WITHOUT reference to v1 (they must hold on whatever
/// engine produced the text) — the body-relevant slice of C6's 54-item list: the editor
/// round-trip returns the identical string; the pieces of a body cover it exactly; no
/// `[[img_` inside a sentence in any stored body.
///
/// Q15: the v1-snap-specific invariants (markers-in=markers-out, paragraph-count-never-
/// drops, idempotence — all asserted by calling v1's own body-snap function, plus
/// their shared `corpusGoldenSlugs()` helper and `knownSnapIdempotenceGaps`) are deleted
/// along with v1 (tag `v1-body`); `BodyV2HarnessTests.testV2IsIdempotent` /
/// `testV2PicturesAreOwnParagraphsAndWordsSurvive` now assert the v2 equivalents with no
/// snap-gap excuses (C17).
final class BodyInvariantTests: XCTestCase {

    // MARK: - helpers

    /// `[[img_NNN]]` marker numbers present in a string, in order of appearance.
    private static let markerRegex = try! NSRegularExpression(pattern: #"\[\[img_(\d{3})\]\]"#)

    // MARK: - pieces cover the body exactly + editor round-trip

    func testPiecesCoverTheBodyExactly() {
        let samples = [
            "Plain text, no attachments at all.",
            "A photo [[img_001]] mid sentence.",
            "- [ ] a task\nsome text\n- [x] done task",
            "Linked to [[memo:9E1E7F3A-0B0E-4B0B-9C0B-000000000001|Some Note]] here.",
            "  - [ ] indented task keeps its indent",
        ]
        for raw in samples {
            let ns = raw as NSString
            let pieces = BodyTransform.pieces(of: raw)
            var cursor = 0
            var reconstructed = ""
            for piece in pieces {
                XCTAssertEqual(piece.rawRange.location, cursor, "gap or overlap before this piece: \(raw)")
                reconstructed += ns.substring(with: piece.rawRange)
                cursor = piece.rawRange.location + piece.rawRange.length
            }
            XCTAssertEqual(cursor, ns.length, "pieces don't reach the end of the body: \(raw)")
            XCTAssertEqual(reconstructed, raw, "pieces don't reconstruct the raw body verbatim")
        }
    }

    /// The one serializer `BodyTransform` actually exposes (`rawTask`) must reconstruct
    /// exactly what the regex matched, for both checkbox states.
    func testEditorRoundTrip_taskLiteral() {
        let raw = "- [ ] open item\n- [x] done item\n  - [X] indented, capital X"
        for piece in BodyTransform.pieces(of: raw) {
            guard case .task(let checked) = piece.segment else { continue }
            let literal = (raw as NSString).substring(with: piece.rawRange)
            XCTAssertEqual(BodyTransform.rawTask(checked: checked).lowercased(), literal.lowercased(),
                           "rawTask(checked:) must round-trip the matched task syntax")
        }
    }

    // MARK: - no [[img_ inside a sentence (C10/C6), checked on the v2 TARGET text

    /// Checked against `expect_body.txt` (the settled v2 shape), not v1's own golden —
    /// several v1 goldens are ON RECORD as violating this (the R2/R95 bugs); asserting
    /// it there would just re-fail a pre-registered bug the harness already classes.
    /// This instead guards the Q9 fixtures themselves: every settled expected body must
    /// already keep a picture on its own paragraph.
    func testNoImageMarkerInsideASentence_expectBodyFixtures() throws {
        let notesDir = BodyGoldenTests.corpusRoot.appendingPathComponent("notes")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: notesDir.path), "corpus not generated")
        let folders = (try? FileManager.default.contentsOfDirectory(atPath: notesDir.path)) ?? []
        var checked = 0
        for folder in folders.sorted() {
            let expectURL = notesDir.appendingPathComponent(folder).appendingPathComponent("expect_body.txt")
            guard let body = try? String(contentsOf: expectURL, encoding: .utf8) else { continue }
            guard body.contains("[[img_") else { continue }
            checked += 1
            let ns = body as NSString
            for m in Self.markerRegex.matches(in: body, range: NSRange(location: 0, length: ns.length)) {
                let start = m.range.location
                let end = m.range.location + m.range.length
                let before = start >= 2 ? ns.substring(with: NSRange(location: start - 2, length: 2)) : ""
                let after = end + 2 <= ns.length ? ns.substring(with: NSRange(location: end, length: 2)) : ""
                XCTAssertTrue(before.isEmpty || before == "\n\n", "\(folder): marker not paragraph-led")
                XCTAssertTrue(after.isEmpty || after == "\n\n", "\(folder): marker not paragraph-trailed")
            }
        }
        XCTAssertGreaterThan(checked, 0, "no expect_body.txt with a marker was found to check")
    }
}
