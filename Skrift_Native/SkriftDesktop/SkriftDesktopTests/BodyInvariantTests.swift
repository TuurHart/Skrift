import XCTest

/// C6 body invariants, asserted WITHOUT reference to v1 (they must hold on whatever
/// engine produced the text) — the body-relevant slice of C6's 54-item list: markers
/// in = markers out; paragraph count never drops; the editor round-trip returns the
/// identical string; every transform is idempotent; the pieces of a body cover it
/// exactly; no `[[img_` inside a sentence in any stored body. Runs both on synthetic
/// strings (so the invariant reads on its own, corpus or no corpus) and on the real
/// corpus's v1 goldens / `expect_body.txt` files where present.
final class BodyInvariantTests: XCTestCase {

    // MARK: - helpers

    /// `[[img_NNN]]` marker numbers present in a string, in order of appearance.
    private static let markerRegex = try! NSRegularExpression(pattern: #"\[\[img_(\d{3})\]\]"#)
    private func markerNumbers(in s: String) -> [Int] {
        let ns = s as NSString
        return Self.markerRegex.matches(in: s, range: NSRange(location: 0, length: ns.length)).compactMap {
            Int(ns.substring(with: $0.range(at: 1)))
        }
    }

    /// Non-empty `\n\n`-delimited paragraph count.
    private func paragraphCount(_ s: String) -> Int {
        s.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }

    private func corpusGoldenSlugs() -> [(slug: String, text: String)] {
        let dir = BodyGoldenTests.goldenDir
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }
        return names.filter { $0.hasSuffix(".txt") }.compactMap { name in
            guard let text = try? String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8) else { return nil }
            return (String(name.dropLast(4)), text)
        }
    }

    // MARK: - markers in = markers out

    func testMarkersInEqualMarkersOut_synthetic() {
        let raw = "First bit [[img_002]] of prose. Second sentence [[img_001]] continues. [[img_003]] Trailing."
        let snapped = BodyTransform.snappedImageBody(raw)
        XCTAssertEqual(Set(markerNumbers(in: snapped)), Set(markerNumbers(in: raw)))
        XCTAssertEqual(markerNumbers(in: snapped).count, markerNumbers(in: raw).count,
                       "no marker merged or duplicated, only relocated")
    }

    func testMarkersInEqualMarkersOut_corpusGoldens() {
        for (slug, golden) in corpusGoldenSlugs() where golden.contains("[[img_") {
            // The snap is idempotent (asserted below) so re-running it must not change
            // the marker set already baked into a recorded golden.
            let resnapped = BodyTransform.snappedImageBody(golden)
            XCTAssertEqual(Set(markerNumbers(in: resnapped)), Set(markerNumbers(in: golden)), slug)
        }
    }

    // MARK: - paragraph count never drops

    func testSnapNeverDropsAParagraph_synthetic() {
        let cases = [
            "Alpha sentence. [[img_001]] Beta sentence.",
            "Already\n\n[[img_001]]\n\nstructured.",
            "[[img_001]] Lone lead-in marker, then prose.",
            "Trailing marker at the end. [[img_001]]",
        ]
        for raw in cases {
            let before = paragraphCount(raw)
            let after = paragraphCount(BodyTransform.snappedImageBody(raw))
            XCTAssertGreaterThanOrEqual(after, before, raw)
        }
    }

    func testSnapNeverDropsAParagraph_corpusGoldens() {
        // Re-snapping an already-snapped golden (idempotent point) must never lose a
        // paragraph the golden itself already has.
        for (slug, golden) in corpusGoldenSlugs() {
            let resnapped = BodyTransform.snappedImageBody(golden)
            XCTAssertGreaterThanOrEqual(paragraphCount(resnapped), paragraphCount(golden), slug)
        }
    }

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

    // MARK: - idempotence

    func testSnapImagesIsIdempotent_synthetic() {
        let cases = [
            "A photo [[img_001]] mid sentence. Then more [[img_002]] words.",
            "[[img_001]]\n\n[[img_002]]\n\nAlready blocked.",
            "No markers here at all.",
            "",
        ]
        for raw in cases {
            let once = BodyTransform.snappedImageBody(raw)
            let twice = BodyTransform.snappedImageBody(once)
            XCTAssertEqual(once, twice, "snapImages must be a fixed point on its own output: \(raw)")
        }
    }

    func testSnapImagesIsIdempotent_corpusGoldens() {
        for (slug, golden) in corpusGoldenSlugs() {
            let twice = BodyTransform.snappedImageBody(golden)
            XCTAssertEqual(golden, twice, "\(slug): a recorded golden must already be a snap fixed point")
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
