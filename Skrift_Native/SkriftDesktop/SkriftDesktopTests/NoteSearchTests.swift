import XCTest
import Foundation

/// Q103 (C236/C111/C115) — ONE note-search matcher. The Mac rated list (`PipelineFile`
/// adapter) and the Mac quiet list (`WayOutRules.matchesSearch` over a `Memo`) must return
/// the SAME hit list for the same note; the phone's twin lives in
/// `SkriftMobileTests/NoteSearchParityTests` and pins the SAME table. Synthetic notes only.
final class NoteSearchTests: XCTestCase {

    private struct Note {
        let key: String
        let memo: Memo
        let generatedTitle: String?
        let summary: String?
    }

    /// N1 open, every field set; N2 has only a generated title; N3 is N1's content, locked.
    private func fixture() -> [Note] {
        func make(_ key: String, title: String?, locked: Bool, full: Bool) -> Memo {
            let id = UUID()
            let m = Memo(id: id, audioFilename: "memo_\(id.uuidString).m4a", recordedAt: Date(),
                         title: title,
                         transcript: full ? "the pump needs a finer nozzle" : "other words",
                         transcriptStatus: .done, significance: 1)
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
            Note(key: "N1", memo: make("N1", title: "Rooftop plan", locked: false, full: true),
                 generatedTitle: nil, summary: "gist-of-it"),
            Note(key: "N2", memo: make("N2", title: nil, locked: false, full: false),
                 generatedTitle: "Zenith", summary: nil),
            Note(key: "N3", memo: make("N3", title: "Locked ledger", locked: true, full: true),
                 generatedTitle: nil, summary: "gist-of-it"),
        ]
    }

    /// THE table (identical in NoteSearchParityTests): query → hit keys while N3 is hidden.
    static let table: [(String, [String])] = [
        ("", ["N1", "N2", "N3"]),
        ("rooftop", ["N1"]),            // set title
        ("zenith", ["N2"]),             // generated title
        ("ledger", ["N3"]),             // a hidden locked note's SET title still hits
        ("nozzle", ["N1"]),             // transcript (N3's is hidden)
        ("irrigation", ["N1"]),         // tags
        ("hotel du vin", ["N1"]),       // place
        ("gist-of", ["N1"]),            // summary
        ("linkcase", ["N1"]),           // link title
        ("flamingo", ["N1"]),           // shared text / PDF text
        ("grey body", ["N1"]),          // photo OCR (C111 corpus check)
        ("other", ["N2"]),
        ("absent", []),
    ]

    private func macRated(_ n: Note, query: String, unlocked: Bool) -> Bool {
        let f = MemoNoteProjection.file(for: n.memo)
        f.enhancedSummary = n.summary
        if let g = n.generatedTitle { f.enhancedTitle = g }
        return f.matchesNoteSearch(query: query, unlockedThisSession: unlocked)
    }

    private func macQuiet(_ n: Note, query: String, unlocked: Bool) -> Bool {
        // The quiet list reads a bare Memo: the generated title / summary belong to the
        // enhancement, which a quiet row has none of — so this adapter is compared on the
        // Memo fields only (N2's generated title and every summary are out).
        WayOutRules.matchesSearch(n.memo, query: query, unlockedThisSession: unlocked)
    }

    func testMacRatedAdapterGivesTheTable() {
        let notes = fixture()
        for (q, expected) in Self.table {
            let hits = notes.filter { macRated($0, query: q, unlocked: false) }.map(\.key)
            XCTAssertEqual(hits, expected, "rated list, query '\(q)'")
        }
    }

    func testMacQuietAdapterAgreesOnEveryMemoField() {
        let notes = fixture()
        // Fields a bare Memo holds: everything except the polish's title + summary.
        let memoOnly: Set<String> = ["zenith", "gist-of"]
        for (q, expected) in Self.table where !memoOnly.contains(q) {
            let hits = notes.filter { macQuiet($0, query: q, unlocked: false) }.map(\.key)
            XCTAssertEqual(hits, expected, "quiet list, query '\(q)'")
        }
    }

    func testRatedAndQuietHitListsMatchWhenTheSnapshotsCarrySameFields() {
        // Same note through both adapters: identical hit lists for every Memo-held field.
        let notes = fixture()
        for (q, _) in Self.table where q != "zenith" && q != "gist-of" {
            let rated = notes.filter { macRated($0, query: q, unlocked: false) }.map(\.key)
            let quiet = notes.filter { macQuiet($0, query: q, unlocked: false) }.map(\.key)
            XCTAssertEqual(rated, quiet, "query '\(q)'")
        }
    }

    func testUnlockedThisSessionBringsTheLockedBodyBack() {
        let notes = fixture()
        for check in [macRated, macQuiet] {
            XCTAssertTrue(notes.contains { $0.key == "N3" && check($0, "nozzle", true) })
            XCTAssertTrue(notes.contains { $0.key == "N3" && check($0, "grey body", true) })
            XCTAssertFalse(notes.contains { $0.key == "N3" && check($0, "nozzle", false) })
            XCTAssertFalse(notes.contains { $0.key == "N3" && check($0, "grey body", false) })
        }
    }

    func testSnapshotMatcherCoversEveryC236Field() {
        let s = NoteSearchSnapshot(title: "T", generatedTitle: "G", transcript: "tr", summary: "su",
                                   tags: ["tg"], place: "pl", annotation: "an",
                                   shared: ["li", "tx"], ocr: ["oc"])
        for q in ["T", "G", "tr", "su", "tg", "pl", "an", "li", "tx", "oc"] {
            XCTAssertTrue(NoteSearch.matches(query: q, s), q)
        }
        XCTAssertFalse(NoteSearch.matches(query: "zz", s))
        var hidden = s; hidden.locked = true
        XCTAssertTrue(NoteSearch.matches(query: "t", hidden), "title only")
        for q in ["su", "tr", "oc", "pl", "tg", "an", "li"] {
            XCTAssertFalse(NoteSearch.matches(query: q, hidden), "locked body field \(q)")
        }
    }
}
