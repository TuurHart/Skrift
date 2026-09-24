import XCTest
import SwiftData

/// Q31: the last four write sites Q13 left on v1 (dictation append, voice-annotate
/// append, Mac text imports, the Mac editor commit) now go through `BodyV2.committed`,
/// and the v1 `ImageMarkers.insert` stopgap is gone from `ASRPostProcess`. This file
/// pins the SHARED behaviour those sites lean on — the indentation fix (C19) and the
/// v2 marker placement `ASRPostProcess` now uses — plus one end-to-end check of the
/// Mac text-import write site (`IngestService`).
final class BodyV2WriteSitesTests: XCTestCase {

    // MARK: - C19: leading indentation survives, interior runs still collapse

    /// A nested list: each line's leading spaces are its indentation depth, not
    /// whitespace to collapse. Interior double-spaces (a run inside the line) still
    /// collapse to one, and the blank-line / CRLF / trim rules are unchanged.
    func testNestedListIndentationSurvives_C19() {
        let input = "- top  item\r\n  - nested  one\r\n    - double  nested\r\n- back to top\n\n\n\ndone"
        let expected = "- top item\n  - nested one\n    - double nested\n- back to top\n\ndone"
        XCTAssertEqual(BodyV2Text.normalised(input), expected)
    }

    /// Tabs as indentation are kept verbatim (not converted to spaces), only the
    /// interior run collapses. (The top-level item is unindented, as a real list's
    /// always is — an indented FIRST line of the whole body would fall to "ends
    /// trimmed" instead, same as leading blank lines.)
    func testTabIndentationSurvives_C19() {
        XCTAssertEqual(BodyV2Text.normalised("- top\n\t\t- deep  item\n\t- shallow"),
                       "- top\n\t\t- deep item\n\t- shallow")
    }

    /// Narrowed per the dispatcher (2026-09-24): a leading run before PLAIN text (not a
    /// list item) still collapses to one space, same as pre-fix — a bare leading tab
    /// renders as a code block in Obsidian, and this is the pinned corpus fixture
    /// `024-typed-crlf-tabs-nbsp` (`expect_body.txt`: "\tIndented" → " Indented").
    func testTabBeforePlainTextStillCollapses_C19() {
        XCTAssertEqual(BodyV2Text.normalised("Line one\n\n\tIndented with a tab\n\nEnd."),
                       "Line one\n\n Indented with a tab\n\nEnd.")
    }

    /// An ordered list (`1.` / `2)`) keeps its indentation exactly like a bulleted one.
    func testOrderedListIndentationSurvives_C19() {
        XCTAssertEqual(BodyV2Text.normalised("1. top  item\n   2) nested  one"),
                       "1. top item\n   2) nested one")
    }

    /// The ≥3-line-break rule is untouched by the per-line indentation change: still
    /// exactly one blank line survives a run of 4.
    func testBlankRunStillCollapses_C19() {
        XCTAssertEqual(BodyV2Text.normalised("a\n\n\n\nb"), "a\n\nb")
    }

    // MARK: - ASRPostProcess: v2 marker placement, not the v1 inline stopgap

    private func tokens(_ pairs: [(String, TimeInterval, TimeInterval)]) -> [RawToken] {
        pairs.map { RawToken(token: $0.0, startTime: $0.1, endTime: $0.2) }
    }

    /// The v1 stopgap (`ImageMarkers.insert`) placed a marker mid-string with no
    /// paragraph wrap. `ASRPostProcess` now routes through `BodyV2.committed`, so a
    /// picture lands as its OWN paragraph (C10) — `\n\n[[img_NNN]]\n\n` shape, not an
    /// inline splice.
    func testASRPostProcessMarkerIsOwnParagraph() async {
        let r = await ASRPostProcess.finish(
            rawText: "script rules", tokens: tokens([(" script", 0, 1.0), (" rules", 1.1, 2.0)]),
            confidence: 0.9, durationMs: 300,
            imageManifest: [ImageManifestEntry(filename: "a.jpg", offsetSeconds: 1.5)],
            rms: { 0.5 }, rescore: { _ in "Skrift rules" })

        XCTAssertTrue(r.markersInjected)
        XCTAssertTrue(r.text.contains("\n\n[[img_001]]"), "the marker opens its own paragraph")
        XCTAssertFalse(r.text.contains("[[img_001]]\n\n[[img_001]]"), "no duplicate")
    }

    // MARK: - Mac text imports: the write site now commits through v2

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// A dropped `.md` file with a nested list and interior double-spaces: the
    /// imported transcript keeps the list's indentation but collapses the interior runs
    /// — proof the Mac text-import write site now runs through `BodyV2.committed`,
    /// not a bare file-content passthrough.
    func testMacTextImportCommitsThroughBodyV2() async throws {
        let work = try tempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let noteURL = work.appendingPathComponent("Shopping list.md")
        try "- milk  and  eggs\n  - semi  skimmed\n- bread".write(to: noteURL, atomically: true, encoding: .utf8)

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: PipelineFile.self, configurations: config)
        let ctx = ModelContext(container)
        let created = try await IngestService(outputDir: work.appendingPathComponent("out"))
            .ingest(localURLs: [noteURL], into: ctx)

        let pf = try XCTUnwrap(created.first)
        XCTAssertEqual(pf.transcript, "- milk and eggs\n  - semi skimmed\n- bread")
    }
}
