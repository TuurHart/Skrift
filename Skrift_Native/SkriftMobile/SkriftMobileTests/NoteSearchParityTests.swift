import XCTest
@testable import SkriftMobile

/// Q103 (C236/C111/C115) — the phone list's `Memo.matches` goes through the SAME shared
/// matcher as the Mac lists. The table below is identical to
/// `SkriftDesktopTests/NoteSearchTests.table`; both must give the same hit list for the same
/// note fixture. Synthetic notes only.
final class NoteSearchParityTests: XCTestCase {

    private struct Note {
        let key: String
        let memo: Memo
        let generatedTitle: String?
        let summary: String?
    }

    private func fixture() -> [Note] {
        func make(title: String?, locked: Bool, full: Bool) -> Memo {
            let m = Memo(title: title, transcript: full ? "the pump needs a finer nozzle" : "other words")
            m.locked = locked
            if full {
                m.tags = ["irrigation"]
                m.metadata = MemoMetadata(
                    location: LocationInfo(latitude: 1, longitude: 2, placeName: "Hotel Du Vin"),
                    imageManifest: [ImageManifestEntry(filename: "a.jpg", offsetSeconds: 0, text: "GREY BODY")])
                m.sharedContent = SharedContent(type: .url, url: "https://example.test/x",
                                                urlTitle: "Linkcase", text: "flamingo")
            }
            return m
        }
        return [
            Note(key: "N1", memo: make(title: "Rooftop plan", locked: false, full: true),
                 generatedTitle: nil, summary: "gist-of-it"),
            Note(key: "N2", memo: make(title: nil, locked: false, full: false),
                 generatedTitle: "Zenith", summary: nil),
            Note(key: "N3", memo: make(title: "Locked ledger", locked: true, full: true),
                 generatedTitle: nil, summary: "gist-of-it"),
        ]
    }

    /// Same table as the Mac's `NoteSearchTests.table`.
    private let table: [(String, [String])] = [
        ("", ["N1", "N2", "N3"]),
        ("rooftop", ["N1"]),
        ("zenith", ["N2"]),
        ("ledger", ["N3"]),
        ("nozzle", ["N1"]),
        ("irrigation", ["N1"]),
        ("hotel du vin", ["N1"]),
        ("gist-of", ["N1"]),
        ("linkcase", ["N1"]),
        ("flamingo", ["N1"]),
        ("grey body", ["N1"]),
        ("other", ["N2"]),
        ("absent", []),
    ]

    func testPhoneAdapterGivesTheSameHitListAsTheMacAdapters() {
        let notes = fixture()
        for (q, expected) in table {
            let hits = notes.filter {
                $0.memo.matches(query: q, unlockedThisSession: false,
                                enhancedTitle: $0.generatedTitle, summary: $0.summary)
            }.map(\.key)
            XCTAssertEqual(hits, expected, "phone list, query '\(q)'")
        }
    }

    func testPhoneNowSearchesTheGeneratedTitleAndSummary() {
        let m = Memo(title: nil, transcript: "plain words")
        XCTAssertFalse(m.matches(query: "zenith"))
        XCTAssertTrue(m.matches(query: "zenith", enhancedTitle: "Zenith"))
        XCTAssertTrue(m.matches(query: "gist", summary: "the gist of it"))
    }

    func testAnnotationStillHits() {
        let m = Memo(title: nil, transcript: "x")
        m.annotationText = "typed afterthought"
        XCTAssertTrue(m.matches(query: "afterthought"))
    }

    func testLockedBodyStaysOutUntilUnlockedThisSession() {
        let n3 = fixture()[2].memo
        for q in ["nozzle", "irrigation", "hotel du vin", "linkcase", "flamingo", "grey body"] {
            XCTAssertFalse(n3.matches(query: q), q)
            XCTAssertTrue(n3.matches(query: q, unlockedThisSession: true), q)
        }
        XCTAssertFalse(n3.matches(query: "gist", summary: "gist-of-it"), "a hidden note's summary stays out")
        XCTAssertTrue(n3.matches(query: "ledger"), "the set title still hits")
    }
}
