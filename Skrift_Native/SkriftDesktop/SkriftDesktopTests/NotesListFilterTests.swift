import XCTest

/// Q104 (C115, D148, C212; parity audit list-sidebar-34/36/47, recsj-054/055): chip + date +
/// search apply to EVERY row kind through the shared `NotesListModel` rules. This is the Mac
/// half of the parity test: the SAME synthetic library and the SAME expected row ids as the
/// phone's `NotesListFilterParityTests`, driven through the Mac adapter (`MacListFilter`,
/// which `AppModel.visible` and `SidebarView` call). Change one table, change both.
final class NotesListFilterTests: XCTestCase {

    private let now = Date()
    private func daysAgo(_ n: Int) -> Date { Calendar.current.date(byAdding: .day, value: -n, to: now)! }

    // MARK: - the synthetic library (mirror of NotesListFilterParityTests)

    private struct Library {
        var memos: [String: Memo] = [:]
        var files: [PipelineFile] = []
        func id(_ name: String) -> String { memos[name]!.id.uuidString }
        func name(_ id: String) -> String { memos.first { $0.value.id.uuidString == id }!.key }
    }

    /// r1 rated, needs work, 2d · r2 rated, done, 10d · u1 unrated, 3d · u2 unrated, 12d ·
    /// f1 unrated fading, 40d · f2 unrated fading, 45d. "harbour" hits r1 r2 u1 f1;
    /// "kitchen" hits u2 f2.
    private func library() -> Library {
        var lib = Library()
        func memo(_ name: String, days: Int, rated: Bool, text: String) {
            lib.memos[name] = Memo(audioFilename: "\(name).m4a", recordedAt: daysAgo(days),
                                   transcript: text, transcriptStatus: .done,
                                   significance: rated ? 0.5 : 0)
        }
        memo("r1", days: 2, rated: true, text: "harbour walk notes")
        memo("r2", days: 10, rated: true, text: "harbour budget")
        memo("u1", days: 3, rated: false, text: "harbour sketch")
        memo("u2", days: 12, rated: false, text: "kitchen idea")
        memo("f1", days: 40, rated: false, text: "harbour old thought")
        memo("f2", days: 45, rated: false, text: "kitchen old")
        // The Mac's rated notes are pipeline rows (same id, uploadedAt = the recorded date).
        for (name, complete) in [("r1", false), ("r2", true)] {
            let m = lib.memos[name]!
            let f = PipelineFile(id: m.id.uuidString, filename: "x.m4a", sourceType: .audio, uploadedAt: m.recordedAt)
            f.significance = 0.5
            f.transcript = m.transcript
            if complete {
                f.transcribeStatus = .done; f.sanitiseStatus = .done; f.enhanceStatus = .done; f.exportStatus = .done
            }
            lib.files.append(f)
        }
        return lib
    }

    private enum Window { case none, recent, old }
    private func range(_ w: Window) -> (Date?, Date?) {
        switch w {
        case .none:   return (nil, nil)
        case .recent: return (daysAgo(5), now)
        case .old:    return (daysAgo(50), daysAgo(9))
        }
    }

    /// chip, date window, query → expected row names. IDENTICAL to the phone's table.
    private let cases: [(QueueFilter, Window, String, Set<String>)] = [
        (.all, .none, "", ["r1", "r2", "u1", "u2"]),
        (.all, .none, "harbour", ["r1", "r2", "u1", "f1"]),
        (.needsWork, .none, "", ["r1"]),
        (.done, .none, "", ["r2"]),
        (.notRated, .none, "", ["u1", "u2"]),
        (.notRated, .none, "harbour", ["u1", "f1"]),
        (.needsWork, .none, "harbour", ["r1"]),
        (.all, .recent, "", ["r1", "u1"]),
        (.all, .old, "", ["r2", "u2"]),
        (.all, .old, "harbour", ["r2", "f1"]),
        (.notRated, .old, "", ["u2"]),
        (.notRated, .recent, "harbour", ["u1"]),
        (.all, .recent, "harbour", ["r1", "u1"]),
        (.done, .old, "harbour", ["r2"]),
        (.notRated, .old, "kitchen", ["u2", "f2"]),
    ]

    /// semantic hits (best first) → expected Related names, in order. IDENTICAL to the phone's table.
    private let relatedCases: [(QueueFilter, Window, String, [String])] = [
        (.notRated, .none, "harbour", ["f2", "u2"]),
        (.all, .old, "harbour", ["f2", "u2"]),
        (.needsWork, .none, "kitchen", ["r1"]),
        (.all, .recent, "kitchen", ["r1", "u1"]),
    ]
    private let hitOrder = ["f2", "u2", "r2", "r1", "u1"]

    private func macFilter(_ chip: QueueFilter, _ w: Window, _ q: String) -> MacListFilter {
        let (from, to) = range(w)
        return MacListFilter(chip: chip, query: q, from: from, to: to)
    }

    private func macRows(_ lib: Library, _ f: MacListFilter) -> [String] {
        f.fileRows(lib.files).map(\.id)
            + f.memoRows(memos: Array(lib.memos.values), files: lib.files, now: now).map(\.id.uuidString)
    }

    // MARK: - tests

    func testMacRowsMatchTheSharedTable() {
        let lib = library()
        for (chip, w, q, expected) in cases {
            let ids = macRows(lib, macFilter(chip, w, q))
            XCTAssertEqual(ids.count, Set(ids).count, "one row per note: \(chip) \(w) '\(q)'")
            XCTAssertEqual(Set(ids.map(lib.name)), expected, "\(chip) \(w) '\(q)'")
        }
    }

    func testMacRelatedRowsObeyChipAndDate() {
        let lib = library()
        let hits = hitOrder.map { lib.memos[$0]!.id }
        for (chip, w, q, expected) in relatedCases {
            let f = macFilter(chip, w, q)
            let shown = Set(macRows(lib, f))
            let related = f.relatedRows(hits: hits, files: lib.files, memos: Array(lib.memos.values), shown: shown,
                                        isLockedFile: { _ in false }, isLockedMemo: { _ in false })
            XCTAssertEqual(related.map { lib.name($0.key) }, expected, "\(chip) \(w) '\(q)'")
        }
    }

    func testRelatedDropsHiddenNotes() {
        let lib = library()
        let f = macFilter(.all, .none, "kitchen")
        let r1 = lib.memos["r1"]!.id
        let related = f.relatedRows(hits: [r1, lib.memos["u1"]!.id], files: lib.files,
                                    memos: Array(lib.memos.values), shown: [],
                                    isLockedFile: { $0.id == r1.uuidString }, isLockedMemo: { _ in false })
        XCTAssertEqual(related.map { lib.name($0.key) }, ["u1"])
    }

    /// The date range used to apply to pipeline rows only (list-sidebar-47): an unrated row
    /// outside the range stayed in the list. Now it leaves with everything else.
    func testDateRangeReachesUnratedAndStrandedRows() {
        let lib = library()
        // r2 loses its pipeline row → stranded memo row.
        let files = lib.files.filter { $0.id != lib.id("r2") }
        let (from, to) = range(.recent)
        let f = MacListFilter(chip: .all, query: "", from: from, to: to)
        let rows = f.memoRows(memos: Array(lib.memos.values), files: files, now: now).map { lib.name($0.id.uuidString) }
        XCTAssertEqual(Set(rows), ["u1"], "u2 (12d) and stranded r2 (10d) are outside the last 5 days")
        let unfiltered = MacListFilter(chip: .all).memoRows(memos: Array(lib.memos.values), files: files, now: now)
        XCTAssertEqual(Set(unfiltered.map { lib.name($0.id.uuidString) }), ["u1", "u2", "r2"])
    }

    // MARK: - the shared rules themselves

    func testSharedListRuleHoldsFadingToTheSameTests() {
        let rows = NotesListModel.listRows(live: [1, 2, 3], fading: [10, 11], searching: true,
                                           matchesSearch: { $0 != 3 }, passesFilter: { $0 != 11 })
        XCTAssertEqual(rows, [1, 2, 10])
        let browsing = NotesListModel.listRows(live: [1, 2, 3], fading: [10, 11], searching: false,
                                               matchesSearch: { _ in true }, passesFilter: { _ in true })
        XCTAssertEqual(browsing, [1, 2, 3], "fading rows join only while searching")
    }

    func testSharedFilterRule() {
        let d = daysAgo(3)
        XCTAssertTrue(NotesListModel.passesFilter(inChip: true, date: d, from: nil, to: nil))
        XCTAssertFalse(NotesListModel.passesFilter(inChip: false, date: d, from: nil, to: nil))
        XCTAssertFalse(NotesListModel.passesFilter(inChip: true, date: d, from: daysAgo(1), to: nil))
        XCTAssertFalse(NotesListModel.passesFilter(inChip: true, date: d, from: nil, to: nil, extra: false))
        XCTAssertEqual(NotesListModel.relatedRows([1, 2, 3, 4], shown: [2], id: { $0 }, hidden: { $0 == 3 },
                                                  passesFilter: { $0 != 4 }), [1])
    }
}
