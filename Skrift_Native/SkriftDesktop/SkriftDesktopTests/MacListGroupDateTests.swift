import XCTest

/// Q377 / D197: the Mac list's sections follow the Recorded / Added picker (Recorded by default),
/// through the same shared `NotesListModel.dateGroups` + `MemoDate.bucket` the phone and iPad use.
/// An old recording imported today lands in its real month; under Added it lands under Today.
/// Synthetic notes only, no store.
@MainActor
final class MacListGroupDateTests: XCTestCase {

    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Lisbon")!
        return c
    }()
    private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }
    private var now: Date { at(2026, 10, 13, 10) }

    private func file(_ name: String, recorded: Date) -> PipelineFile {
        PipelineFile(id: UUID().uuidString, filename: name, path: "/tmp/x", size: 1, sourceType: .audio, uploadedAt: recorded)
    }

    private func derive(_ files: [PipelineFile], added: [String: Date], field: MemoDateField,
                        sort: SidebarSort = .newest) -> MacListDerivedCache.Derived {
        MacListDerivedCache().derived(
            .init(files: files, memos: [], memoVersion: 1, backlinked: [], addedAtByID: added,
                  processedIDs: [], now: now),
            params: .init(dateField: field, sort: sort),
            fileTitle: { $0.filename }, entryTitle: { _ in "" },
            dayLabel: { MemoDate.bucket($0, now: self.now, calendar: self.cal) })
    }

    func testYesterdayIsItsOwnGroupBetweenTodayAndTheWeek() {
        let t = file("today.m4a", recorded: at(2026, 10, 13, 9))
        let y = file("yesterday.m4a", recorded: at(2026, 10, 12, 21))
        let w = file("week.m4a", recorded: at(2026, 10, 9, 11))
        let d = derive([w, y, t], added: [:], field: .recorded)
        XCTAssertEqual(d.groups.map(\.title), ["Today", "Yesterday", "Previous 7 Days"])
    }

    func testAnOldImportAddedTodayLandsInItsRealMonthByDefault() {
        let imp = file("import.m4a", recorded: at(2026, 3, 9))
        let today = file("today.m4a", recorded: at(2026, 10, 13, 9))
        let added = [imp.id: at(2026, 10, 13, 8), today.id: at(2026, 10, 13, 9)]
        let rec = derive([imp, today], added: added, field: .recorded)
        XCTAssertEqual(rec.groups.map(\.title), ["Today", "March"])
        XCTAssertEqual(rec.displayedIDs, [today.id, imp.id], "the drawn order follows the groups")
        let add = derive([imp, today], added: added, field: .added)
        XCTAssertEqual(add.groups.map(\.title), ["Today"])
        XCTAssertEqual(add.groups[0].items.map(\.id), ["pf-" + today.id, "pf-" + imp.id], "newest added first")
    }

    func testOldestSortRunsTheSectionsOldestFirst() {
        let imp = file("import.m4a", recorded: at(2026, 3, 9))
        let today = file("today.m4a", recorded: at(2026, 10, 13, 9))
        let d = derive([today, imp], added: [:], field: .recorded, sort: .oldest)
        XCTAssertEqual(d.groups.map(\.title), ["March", "Today"])
    }
}
