import XCTest
@testable import SkriftMobile

/// Q104 (C115, D148, C212; parity audit list-sidebar-34/36/47, recsj-054/055): chip + date +
/// search apply to EVERY row kind through the shared `NotesListModel` rules. This is the
/// phone half of the parity test: the SAME synthetic library and the SAME expected row ids as
/// the Mac's `NotesListFilterTests`, driven through the phone adapter (`MemosListView`'s
/// static `listRows` / `relatedRows`, which the list's `derived` pass calls). On the phone
/// every note is a `Memo`; "done" = a polish pass ran (`enhanced`).
@MainActor
final class NotesListFilterParityTests: XCTestCase {

    private let now = Date()
    private func daysAgo(_ n: Int) -> Date { Calendar.current.date(byAdding: .day, value: -n, to: now)! }

    // MARK: - the synthetic library (mirror of NotesListFilterTests)

    private struct Library {
        var memos: [String: Memo] = [:]
        var enhanced: Set<UUID> = []
        func name(_ id: UUID) -> String { memos.first { $0.value.id == id }!.key }
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
        lib.enhanced = [lib.memos["r2"]!.id]
        return lib
    }

    private enum Window { case none, recent, old }
    private func filter(_ w: Window) -> MemoFilter {
        switch w {
        case .none:   return MemoFilter()
        case .recent: return MemoFilter(from: daysAgo(5), to: now)
        case .old:    return MemoFilter(from: daysAgo(50), to: daysAgo(9))
        }
    }

    /// chip, date window, query → expected row names. IDENTICAL to the Mac's table.
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

    /// semantic hits (best first) → expected Related names, in order. IDENTICAL to the Mac's table.
    private let relatedCases: [(QueueFilter, Window, String, [String])] = [
        (.notRated, .none, "harbour", ["f2", "u2"]),
        (.all, .old, "harbour", ["f2", "u2"]),
        (.needsWork, .none, "kitchen", ["r1"]),
        (.all, .recent, "kitchen", ["r1", "u1"]),
    ]
    private let hitOrder = ["f2", "u2", "r2", "r1", "u1"]

    private func phoneRows(_ lib: Library, _ chip: QueueFilter, _ w: Window, _ q: String) -> [Memo] {
        let all = Array(lib.memos.values)
        let split = MemosListView.lifecycle(all, backlinked: MemoLifecycle.backlinkedIDs(in: all), now: now)
        return MemosListView.listRows(lifecycle: split, search: q, chip: chip, filter: filter(w),
                                      enhanced: lib.enhanced, isUnlocked: { _ in false })
    }

    func testPhoneRowsMatchTheSharedTable() {
        let lib = library()
        for (chip, w, q, expected) in cases {
            let ids = phoneRows(lib, chip, w, q).map(\.id)
            XCTAssertEqual(ids.count, Set(ids).count, "one row per note: \(chip) \(w) '\(q)'")
            XCTAssertEqual(Set(ids.map(lib.name)), expected, "\(chip) \(w) '\(q)'")
        }
    }

    func testPhoneRelatedRowsObeyChipAndDate() {
        let lib = library()
        let hits = hitOrder.map { lib.memos[$0]! }
        for (chip, w, q, expected) in relatedCases {
            let shown = Set(phoneRows(lib, chip, w, q).map(\.id))
            let related = MemosListView.relatedRows(hits, shown: shown, chip: chip, filter: filter(w),
                                                    enhanced: lib.enhanced, isLocked: { _ in false })
            XCTAssertEqual(related.map { lib.name($0.id) }, expected, "\(chip) \(w) '\(q)'")
        }
    }
}
