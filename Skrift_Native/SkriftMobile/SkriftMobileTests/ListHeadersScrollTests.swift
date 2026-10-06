import XCTest
@testable import SkriftMobile

/// Q324 / D180 — the Notes list's section headers scroll with the notes and do not pin. The header is the
/// section's first row (`ListSectionHeaderRow`), not a `Section` header (a plain List pins those, and the
/// pinned-supplementary solve cost ~27% of scroll work at 2,000 notes). The look stays the same, and the
/// sections stay, so search/filter grouping is untouched. Synthetic notes only.
@MainActor
final class ListHeadersScrollTests: XCTestCase {

    func testHeadersDoNotPin() {
        XCTAssertFalse(ListSectionHeaderStyle.pinsToTop, "D180: day headers scroll away with the notes")
    }

    func testHeaderLookIsTheSharedListChromeLook() {
        // Same numbers the Mac sidebar reads; only the pinning went.
        XCTAssertEqual(ListChrome.headerSize, 11.5)
        XCTAssertEqual(ListChrome.headerKerning, 0.5)
        XCTAssertEqual(ListSectionHeaderStyle.text(for: "Sat 3 Oct"), "SAT 3 OCT")
        XCTAssertEqual(ListSectionHeaderStyle.text(for: "Today"), "TODAY")
        XCTAssertEqual(ListSectionHeaderStyle.text(for: "Longest first"), "LONGEST FIRST")
    }

    func testHeaderRowLinesUpWithTheCardRows() {
        // Card rows use leading/trailing 16; the header text starts at the same x.
        XCTAssertEqual(ListSectionHeaderStyle.insets.leading, 16)
        XCTAssertEqual(ListSectionHeaderStyle.insets.trailing, 16)
        // It sits closer to its own cards than to the section above it.
        XCTAssertGreaterThan(ListSectionHeaderStyle.insets.top, ListSectionHeaderStyle.insets.bottom + 5)
    }

    func testSectionsAreStillGroupedByDay() {
        let now = Date()
        func memo(_ i: Int, daysAgo: Int) -> Memo {
            let at = now.addingTimeInterval(-Double(daysAgo) * 86_400 - Double(i) * 60)
            return Memo(audioFilename: "h\(i).m4a", duration: 30, recordedAt: at, transcript: "Words \(i)",
                        transcriptStatus: .done, significance: 0.5, createdAt: at)
        }
        let rows = [memo(1, daysAgo: 0), memo(2, daysAgo: 0), memo(3, daysAgo: 3)]
        let groups = ListDerivedCache.groups(from: rows, sort: .recent)
        XCTAssertEqual(groups.count, 2, "one section per day; the header row is not a group")
        XCTAssertEqual(groups.first?.memos.count, 2)
        XCTAssertEqual(ListDerivedCache.groups(from: rows, sort: .longest).map(\.title), ["Longest first"])
    }
}
