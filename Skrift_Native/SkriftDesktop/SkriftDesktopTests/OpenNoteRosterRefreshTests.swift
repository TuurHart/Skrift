import XCTest
import Foundation

/// Q421 (C258): a roster change that arrives by sync while a note is open re-derives that note's
/// name spans at once. The "synced rename" is `NamesSyncCore.notifyIfChanged` on a private center,
/// the exact post a CloudKit names reconcile makes.
@MainActor
final class OpenNoteRosterRefreshTests: XCTestCase {

    private func person(_ canonical: String, alias: String) -> Person {
        Person(canonical: canonical, aliases: [alias], short: alias, lastModifiedAt: "2026-01-01T00:00:00.000Z")
    }

    private func syncedChange(on center: NotificationCenter, changed: Bool = true) {
        NamesSyncCore.notifyIfChanged(
            .init(merged: NamesData(lastModifiedAt: "", people: []), localChanged: changed), center: center)
    }

    /// A processed note whose body links Nick to the roster as it was.
    private func linkedNote(roster: [Person]) -> PipelineFile {
        let pf = PipelineFile(id: UUID().uuidString, filename: "a.m4a")
        pf.transcript = "I met Nick today."
        pf.relinkNames(working: "I met Nick today.", isConversation: false, people: roster)
        return pf
    }

    func testOpenNoteRederivesAfterASyncedRename() {
        var roster = [person("[[Nick Jansen]]", alias: "Nick")]
        let pf = linkedNote(roster: roster)
        XCTAssertTrue((pf.sanitised ?? "").contains("[[Nick Jansen]]"), pf.sanitised ?? "nil")

        let center = NotificationCenter()
        var saved = 0
        let refresh = OpenNoteRosterRefresh(center: center, people: { roster }, author: { "Me" },
                                            afterRefresh: { _ in saved += 1 })
        refresh.open(pf)

        // The rename arrives by sync: same person, new canonical.
        roster = [person("[[Nicholas Jansen]]", alias: "Nick")]
        syncedChange(on: center)

        XCTAssertTrue((pf.sanitised ?? "").contains("[[Nicholas Jansen]]"), pf.sanitised ?? "nil")
        XCTAssertFalse((pf.sanitised ?? "").contains("[[Nick Jansen]]"), pf.sanitised ?? "nil")
        XCTAssertTrue((pf.compiledText ?? "").contains("Nicholas Jansen"), "the compiled note follows")
        XCTAssertEqual(refresh.refreshCount, 1)
        XCTAssertEqual(saved, 1, "the app saves after the refresh")
    }

    func testAnUnchangedReconcileLeavesTheNoteAlone() {
        let roster = [person("[[Nick Jansen]]", alias: "Nick")]
        let pf = linkedNote(roster: roster)
        let center = NotificationCenter()
        let refresh = OpenNoteRosterRefresh(center: center, people: { roster }, author: { "Me" })
        refresh.open(pf)
        syncedChange(on: center, changed: false)
        XCTAssertEqual(refresh.refreshCount, 0)
    }

    func testNoOpenNoteMeansNothingToRefresh() {
        let roster = [person("[[Nick Jansen]]", alias: "Nick")]
        let pf = linkedNote(roster: roster)
        let center = NotificationCenter()
        let refresh = OpenNoteRosterRefresh(center: center, people: { [self.person("[[Nicholas Jansen]]", alias: "Nick")] },
                                            author: { "Me" })
        refresh.open(pf)
        refresh.open(nil)
        syncedChange(on: center)
        XCTAssertEqual(refresh.refreshCount, 0)
        XCTAssertTrue((pf.sanitised ?? "").contains("[[Nick Jansen]]"), "a note that is not open is not touched")
    }

    func testANoteNeverNameLinkedIsLeftToItsFirstRun() {
        let pf = PipelineFile(id: UUID().uuidString, filename: "a.m4a")
        pf.transcript = "I met Nick today."
        let center = NotificationCenter()
        let refresh = OpenNoteRosterRefresh(center: center,
                                            people: { [self.person("[[Nick Jansen]]", alias: "Nick")] }, author: { "Me" })
        refresh.open(pf)
        syncedChange(on: center)
        XCTAssertNil(pf.sanitised)
        XCTAssertEqual(refresh.refreshCount, 0)
    }
}
