import XCTest
import SwiftData
import Foundation

/// Q528: on an UNRATED Mac note, a name decision ("Which Bruno?" pick, "Keep as plain text",
/// an unlink, their undo) is saved to the memo's synced `nameResolutions`. The transcript stays
/// the raw words, nothing is rated and no `PipelineFile` is created.
@MainActor
final class UnratedNamePickPersistsTests: XCTestCase {

    private let brunoA = Person(canonical: "[[Bruno Alves]]", aliases: ["Bruno"], short: "Bruno",
                                lastModifiedAt: "2026-01-01T00:00:00.000Z")
    private let brunoB = Person(canonical: "[[Bruno Barros]]", aliases: ["Bruno"], short: "Bruno",
                                lastModifiedAt: "2026-01-01T00:00:00.000Z")
    private var people: [Person] { [brunoA, brunoB] }
    private let text = "I had lunch with Bruno today."

    private func memo() -> Memo {
        Memo(id: UUID(), audioFilename: "memo_x.m4a", duration: 12,
             recordedAt: Date(timeIntervalSince1970: 1_700_000_000), tags: [],
             title: nil, transcript: text, transcriptStatus: .done, significance: 0)
    }

    /// What `NoteDisplayView.applyNaming` + `ProcessingCoordinator.resanitiseForNames` do to the projection.
    private func decide(_ pf: PipelineFile, _ mutate: (inout NameResolutions) -> Void) {
        var r = pf.nameResolutions
        mutate(&r)
        pf.nameResolutions = r
        pf.relinkNames(working: pf.enhancedCopyedit ?? pf.transcript ?? "",
                       isConversation: false, people: people)
    }

    func testAPickOnAnUnratedNoteReachesTheMemoAndSurvivesReopen() throws {
        let container = try ModelContainer(for: PipelineFile.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let m = memo()
        let pf = MemoNoteProjection.file(for: m)
        MemoNoteProjection.linkNames(pf, memo: m, people: people)
        XCTAssertFalse(pf.bestBodyText.contains("[[Bruno"), "two Brunos: nothing is auto-linked")

        decide(pf) { $0.link(alias: "Bruno", to: "[[Bruno Barros]]") }
        XCTAssertTrue(pf.bestBodyText.contains("[[Bruno Barros]]"), pf.bestBodyText)
        // The pane's body mirror finds nothing to carry: the transcript is untouched.
        XCTAssertNil(MemoNoteProjection.rawTranscript(ofLinked: pf, people: people))

        XCTAssertTrue(MemoNoteProjection.writeBack(pf, to: m), "a pick is a change worth saving")
        XCTAssertEqual(m.nameResolutions.namePicks["bruno"], "[[Bruno Barros]]")
        XCTAssertEqual(m.transcript, text, "the memo keeps the raw words")
        XCTAssertFalse(m.transcriptUserEdited, "a name decision is not a hand-edit of the words")
        XCTAssertEqual(m.significance, 0)
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<PipelineFile>()), 0)
        XCTAssertNil(pf.modelContext)

        // Saving again with nothing new is a no-op.
        XCTAssertFalse(MemoNoteProjection.writeBack(pf, to: m))

        // Reopen: a fresh projection of the same memo shows the person linked.
        let reopened = MemoNoteProjection.file(for: m)
        XCTAssertTrue(MemoNoteProjection.linkNames(reopened, memo: m, people: people))
        XCTAssertTrue(reopened.bestBodyText.contains("[[Bruno Barros]]"), reopened.bestBodyText)
        XCTAssertNil(MemoNoteProjection.rawTranscript(ofLinked: reopened, people: people))
    }

    func testKeepAsPlainTextAndItsUndoPersist() {
        let m = memo()
        let pf = MemoNoteProjection.file(for: m)
        MemoNoteProjection.linkNames(pf, memo: m, people: people)
        decide(pf) { $0.link(alias: "Bruno", to: "[[Bruno Alves]]") }
        XCTAssertTrue(MemoNoteProjection.writeBack(pf, to: m))
        let linked = m.nameResolutions

        // "Keep as plain text".
        decide(pf) { $0.keepPlain(alias: "Bruno") }
        XCTAssertTrue(MemoNoteProjection.writeBack(pf, to: m))
        XCTAssertEqual(m.nameResolutions.namePicks["bruno"], "")
        XCTAssertEqual(m.transcript, text)
        let plain = MemoNoteProjection.file(for: m)
        MemoNoteProjection.linkNames(plain, memo: m, people: people)
        XCTAssertFalse(plain.bestBodyText.contains("[["), plain.bestBodyText)

        // Undo restores the earlier resolutions and saves that too.
        decide(pf) { $0 = linked }
        XCTAssertTrue(MemoNoteProjection.writeBack(pf, to: m))
        XCTAssertEqual(m.nameResolutions, linked)
        XCTAssertEqual(m.transcript, text)
        let back = MemoNoteProjection.file(for: m)
        XCTAssertTrue(MemoNoteProjection.linkNames(back, memo: m, people: people))
        XCTAssertTrue(back.bestBodyText.contains("[[Bruno Alves]]"), back.bestBodyText)
    }

    func testUnlinkingAnAutoLinkedPersonPersists() {
        let nick = Person(canonical: "[[Nick Jansen]]", aliases: ["Nick"], short: "Nick",
                          lastModifiedAt: "2026-01-01T00:00:00.000Z")
        let m = Memo(id: UUID(), audioFilename: "memo_y.m4a", duration: 5,
                     recordedAt: Date(timeIntervalSince1970: 1_700_000_000), tags: [],
                     title: nil, transcript: "I met Nick today.", transcriptStatus: .done, significance: 0)
        let pf = MemoNoteProjection.file(for: m)
        XCTAssertTrue(MemoNoteProjection.linkNames(pf, memo: m, people: [nick]))
        var r = pf.nameResolutions
        r.unlinkPerson("[[Nick Jansen]]")
        pf.nameResolutions = r
        pf.relinkNames(working: "I met Nick today.", isConversation: false, people: [nick])
        XCTAssertTrue(MemoNoteProjection.writeBack(pf, to: m))
        XCTAssertEqual(m.nameResolutions.unlinkedNames.count, 1)
        XCTAssertEqual(m.transcript, "I met Nick today.")
        let reopened = MemoNoteProjection.file(for: m)
        MemoNoteProjection.linkNames(reopened, memo: m, people: [nick])
        XCTAssertFalse(reopened.bestBodyText.contains("[[Nick Jansen]]"), reopened.bestBodyText)
    }

    func testOpeningWithNoDecisionWritesNothing() {
        let m = memo()
        let pf = MemoNoteProjection.file(for: m)
        MemoNoteProjection.linkNames(pf, memo: m, people: people)
        XCTAssertFalse(MemoNoteProjection.writeBack(pf, to: m))
        XCTAssertNil(m.nameResolutionsData)
    }
}
