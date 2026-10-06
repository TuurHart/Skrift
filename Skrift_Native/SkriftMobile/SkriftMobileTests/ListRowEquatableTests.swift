import XCTest
@testable import SkriftMobile

/// Q323 — the Notes list skips rows whose inputs did not change (`MemoRow` is Equatable and the list
/// applies `.equatable()`), and a search keystroke keeps every surviving section's identity.
/// Synthetic notes only; no store.
@MainActor
final class ListRowEquatableTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func memo(_ i: Int, text: String? = nil, daysAgo: Int = 0) -> Memo {
        let at = now.addingTimeInterval(-Double(daysAgo) * 86_400 - Double(i) * 60)
        return Memo(audioFilename: "m\(i).m4a", duration: Double(30 + i), recordedAt: at,
                    transcript: text ?? "Quiet words \(i)", transcriptStatus: .done, significance: 0.5, createdAt: at)
    }

    private func row(_ m: Memo, enhancedTitle: String? = nil, fading: Bool = false, clockLine: String? = nil,
                     quiet: Bool = false, selected: Bool = false, regular: Bool = false,
                     onTap: @escaping () -> Void = {}) -> MemoRow {
        MemoRow(memo: m, enhancedTitle: enhancedTitle, fading: fading, clockLine: clockLine, quiet: quiet,
                selected: selected, regularWidth: regular, onTap: onTap)
    }

    // MARK: - Rows

    func testRowsWithUnchangedInputsCompareEqual() {
        let m = memo(1)
        XCTAssertEqual(row(m), row(m))
        XCTAssertEqual(row(m, enhancedTitle: "Zenith", fading: true, clockLine: "starts fading 4 Oct", quiet: true),
                       row(m, enhancedTitle: "Zenith", fading: true, clockLine: "starts fading 4 Oct", quiet: true))
    }

    func testTapClosureIsNotPartOfTheComparison() {
        let m = memo(1)
        var taps = 0
        XCTAssertEqual(row(m, onTap: { taps += 1 }), row(m, onTap: {}))
        XCTAssertEqual(taps, 0)
    }

    func testEveryDisplayedInputBreaksEquality() {
        let m = memo(1)
        let base = row(m)
        XCTAssertNotEqual(base, row(m, enhancedTitle: "A title"))
        XCTAssertNotEqual(base, row(m, fading: true))
        XCTAssertNotEqual(base, row(m, clockLine: "starts fading 4 Oct"))
        XCTAssertNotEqual(base, row(m, quiet: true))
        XCTAssertNotEqual(base, row(m, selected: true))
        XCTAssertNotEqual(base, row(m, regular: true), "a tap closure built for the other width must not be reused")
        XCTAssertNotEqual(row(m, clockLine: "a"), row(m, clockLine: "b"))
    }

    func testDifferentNotesNeverCompareEqual() {
        XCTAssertNotEqual(row(memo(1)), row(memo(2)))
    }

    // MARK: - Sections

    private func derived(_ c: ListDerivedCache, _ memos: [Memo], search: String) -> NotesListDerived {
        let base = c.base(rawMemos: memos, enhancements: [], externalVersion: 0, now: now,
                          backlinks: BacklinkIndex.build(rows: memos.map {
                              Backlinks.Row(id: $0.id, transcript: $0.transcript, copyedit: nil) }))
        let p = ListDerivedCache.Params(search: search, chip: .all, filter: MemoFilter(), sort: .recent, unlocked: [])
        return c.derived(base: base, params: p, related: [])
    }

    func testSectionIdentityIsTheTitleAndSurvivesASearchKeystroke() {
        var memos: [Memo] = []
        for day in 0..<6 {
            for j in 0..<4 {
                let i = day * 4 + j
                memos.append(memo(i, text: j % 2 == 0 ? "Morning walk \(i)" : "Evening quiet \(i)", daysAgo: day * 3))
            }
        }
        let c = ListDerivedCache()
        let all = derived(c, memos, search: "")
        XCTAssertEqual(all.groups.map(\.id), all.groups.map(\.title), "a section's identity is its title")
        XCTAssertEqual(Set(all.groups.map(\.id)).count, all.groups.count, "section ids are unique")

        let a = derived(c, memos, search: "morn")
        let b = derived(c, memos, search: "morni")   // one more keystroke
        XCTAssertFalse(a.groups.isEmpty)
        let aIDs = a.groups.map(\.id)
        for g in b.groups {
            XCTAssertTrue(aIDs.contains(g.id), "a section of the longer query existed for the shorter one")
            let before = a.groups.first { $0.id == g.id }!.memos.map(\.id)
            XCTAssertEqual(g.memos.map(\.id), before.filter { id in g.memos.contains { $0.id == id } },
                           "rows keep their order inside a surviving section")
        }
        // The same keystroke applied twice yields the same section ids (nothing is re-keyed).
        XCTAssertEqual(derived(c, memos, search: "morni").groups.map(\.id), b.groups.map(\.id))
        // Clearing returns to the full list's sections.
        XCTAssertEqual(derived(c, memos, search: "").groups.map(\.id), all.groups.map(\.id))
    }
}
