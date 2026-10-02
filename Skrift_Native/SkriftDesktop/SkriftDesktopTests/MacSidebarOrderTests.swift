import XCTest
import SwiftData

/// Q105 (C70, C115; parity audit list-sidebar-46/51/58/102): the Mac sidebar shows ONE row per
/// note id, offers the phone's Recorded / Added date picker, sorts Newest on the note's ADDED
/// date, and keys day headers on the shared `NotesListModel.groupDate`.
final class MacSidebarOrderTests: XCTestCase {

    private let day: TimeInterval = 86_400
    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    private func at(_ days: Int) -> Date { base.addingTimeInterval(Double(days) * day) }

    /// A note recorded `rec` days after base that entered Skrift `added` days after base
    /// (an import: old content, new arrival).
    private func note(_ name: String, rec: Int, added: Int) -> (Memo, PipelineFile) {
        let m = Memo(audioFilename: "\(name).m4a", recordedAt: at(rec), transcript: name,
                     transcriptStatus: .done, significance: 0.5, createdAt: at(added))
        let f = PipelineFile(id: m.id.uuidString, filename: "\(name).m4a", sourceType: .audio, uploadedAt: m.recordedAt)
        f.significance = 0.5
        return (m, f)
    }

    // MARK: - one row per note id (list-sidebar-102)

    func testSnapshotCollapsesSameIdClonesToOneRow() throws {
        let container = try ModelContainer(for: Memo.self, MemoAsset.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let ctx = ModelContext(container)
        let id = UUID()
        for _ in 0..<2 {
            ctx.insert(Memo(id: id, audioFilename: "a.m4a", recordedAt: at(0), transcript: "same words",
                            transcriptStatus: .done, createdAt: at(0)))
        }
        ctx.insert(Memo(audioFilename: "b.m4a", recordedAt: at(1), transcript: "other", transcriptStatus: .done))
        try ctx.save()
        let snap = CloudMemoSnapshot(container: container)
        XCTAssertEqual(snap.memos.count, 2, "the clone pair is ONE row, plus the other note")
        XCTAssertEqual(snap.memos.filter { $0.id == id }.count, 1)
    }

    // MARK: - the picker (list-sidebar-46)

    func testPickerOffersRecordedThenAdded() {
        XCTAssertEqual(MemoDateField.allCases.map(\.rawValue), ["Recorded", "Added"])
    }

    func testDateRangeReadsTheFieldThePickerChose() {
        // Recorded day 0, added day 20.
        let (m, f) = note("import", rec: 0, added: 20)
        let window = (from: at(18), to: at(22))
        var filter = MacListFilter(chip: .all, from: window.from, to: window.to,
                                   dateField: .recorded, addedAtByID: MacListFilter.addedDates(memos: [m]))
        XCTAssertFalse(filter.passesFilter(f), "Recorded: day 0 is outside the 18-22 window")
        XCTAssertFalse(filter.passesFilter(m))
        filter.dateField = .added
        XCTAssertTrue(filter.passesFilter(f), "Added: the pipeline row reads its memo's added date")
        XCTAssertTrue(filter.passesFilter(m))
    }

    func testAFileWithNoMemoFallsBackToItsRecordedDate() {
        let f = PipelineFile(id: "orphan", filename: "x.m4a", sourceType: .audio, uploadedAt: at(3))
        let filter = MacListFilter(chip: .all, dateField: .added)
        XCTAssertEqual(filter.addedAt(f), at(3))
    }

    // MARK: - Newest sorts on the added date (list-sidebar-51)

    func testNewestSortsOnAddedNotRecorded() {
        // old.rec=0 added=30 (a fresh import of an old recording) · new.rec=10 added=10.
        let (om, of) = note("old", rec: 0, added: 30)
        let (nm, nf) = note("new", rec: 10, added: 10)
        let filter = MacListFilter(chip: .all, addedAtByID: MacListFilter.addedDates(memos: [om, nm]))
        XCTAssertEqual(filter.sort([nf, of], by: .newest).map(\.filename), ["old.m4a", "new.m4a"],
                       "Newest = most recently ADDED first")
        XCTAssertEqual(filter.sort([nf, of], by: .oldest).map(\.filename), ["old.m4a", "new.m4a"],
                       "Oldest stays on the recorded date (the phone's .oldest)")
    }

    func testInterleavedEntriesFollowTheSameKey() {
        let (om, of) = note("rated", rec: 0, added: 30)
        let quiet = Memo(audioFilename: "q.m4a", recordedAt: at(20), transcript: "quiet",
                         transcriptStatus: .done, createdAt: at(20))
        let filter = MacListFilter(chip: .all, addedAtByID: MacListFilter.addedDates(memos: [om, quiet]))
        let sorted = filter.sort([.memo(quiet), .file(of)], by: .newest)
        guard case .file = sorted[0] else { return XCTFail("the added-day-30 rated row leads under Newest") }
    }

    // MARK: - the day header key (list-sidebar-58)

    func testDayHeaderKeysOnTheRecordedDateNeverTheAddedDate() {
        let (m, f) = note("import", rec: 2, added: 40)
        XCTAssertEqual(SidebarEntry.file(f).groupDate, m.recordedAt)
        XCTAssertEqual(SidebarEntry.memo(m).groupDate, m.recordedAt)
        XCTAssertEqual(SidebarEntry.file(f).groupDate,
                       NotesListModel.groupDate(recordedAt: m.recordedAt, lastEditedAt: m.lastEditedAt, byEditTime: false))
    }
}
