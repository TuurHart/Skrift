import XCTest
@testable import SkriftMobile

/// Per-note name-linking resolution on `Memo` — the persisted choices behind the phone's
/// tap-to-resolve surface. Round-trips through the `nameResolutionsData` JSON blob and
/// re-derives tiers via `Memo.nameSpans(people:)`. The shared tier engine is covered by
/// the desktop `NameSpansTests`; this pins the mobile persistence + gestures.
final class NameResolutionTests: XCTestCase {

    private var people: [Person] {
        [
            Person(canonical: "[[Jack Hutton]]", aliases: ["Jack"], short: nil, lastModifiedAt: "2026-01-01T00:00:00Z"),
            Person(canonical: "[[Jack Tanner]]", aliases: ["Jack"], short: nil, lastModifiedAt: "2026-01-01T00:00:00Z"),
            Person(canonical: "[[Hendri van Niekerk]]", aliases: ["Hendri"], short: "Hendri", lastModifiedAt: "2026-01-01T00:00:00Z"),
        ]
    }

    private func memo(_ transcript: String) -> Memo {
        Memo(transcript: transcript, transcriptStatus: .done)
    }

    func testDefaultResolutionsEmpty() {
        let m = memo("Met Jack and Hendri.")
        XCTAssertTrue(m.nameResolutions.isEmpty)
        XCTAssertNil(m.nameResolutionsData, "empty resolutions persist as nil (no blob)")
    }

    func testPickResolvesAmbiguousToLinked() {
        let m = memo("Met Jack today.")
        XCTAssertEqual(m.nameSpans(people: people).first { $0.alias == "Jack" }?.tier, .ambiguous)
        m.linkName(alias: "Jack", to: "[[Jack Hutton]]")
        let span = m.nameSpans(people: people).first { $0.alias == "Jack" }
        XCTAssertEqual(span?.tier, .linked)
        XCTAssertEqual(span?.canonical, "[[Jack Hutton]]")
        XCTAssertEqual(span?.candidates.count, 2, "still re-pickable → Change person")
        XCTAssertNotNil(m.nameResolutionsData, "a pick persists")
    }

    func testKeepPlainSilencesButStaysReTappable() {
        let m = memo("Hendri came by.")
        XCTAssertEqual(m.nameSpans(people: people).first { $0.alias == "Hendri" }?.tier, .linked)
        m.keepNamePlain(alias: "Hendri")
        let span = m.nameSpans(people: people).first { $0.alias == "Hendri" }
        XCTAssertEqual(span?.tier, .plain, "kept plain → re-tappable leftplain token")
    }

    func testClearReverts() {
        let m = memo("Met Jack today.")
        m.linkName(alias: "Jack", to: "[[Jack Tanner]]")
        XCTAssertEqual(m.nameSpans(people: people).first { $0.alias == "Jack" }?.tier, .linked)
        m.clearNameResolution(alias: "Jack")
        XCTAssertEqual(m.nameSpans(people: people).first { $0.alias == "Jack" }?.tier, .ambiguous,
                       "undo a pick → back to ambiguous")
        XCTAssertTrue(m.nameResolutions.isEmpty)
    }

    func testChangePersonUpdatesPick() {
        let m = memo("Met Jack today.")
        m.linkName(alias: "Jack", to: "[[Jack Hutton]]")
        m.linkName(alias: "Jack", to: "[[Jack Tanner]]")
        XCTAssertEqual(m.nameSpans(people: people).first { $0.alias == "Jack" }?.canonical, "[[Jack Tanner]]")
    }

    func testResolutionsRoundTripThroughBlob() {
        let m = memo("Met Jack and Hendri.")
        m.linkName(alias: "Jack", to: "[[Jack Hutton]]")
        m.keepNamePlain(alias: "Hendri")
        // Re-decode from the persisted blob.
        let decoded: NameResolutions? = Memo.decodeJSON(m.nameResolutionsData)
        XCTAssertEqual(decoded?.namePicks["jack"], "[[Jack Hutton]]")
        XCTAssertEqual(decoded?.namePicks["hendri"], "")
    }
}
