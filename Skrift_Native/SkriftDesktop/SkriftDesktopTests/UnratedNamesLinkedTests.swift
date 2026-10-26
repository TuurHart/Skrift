import XCTest
import SwiftData
import Foundation

/// Q524: an UNRATED note shows its names linked (purple) on the Mac, like the phone, without the
/// Mac creating a row for it or writing anything back. The projection links through the shared
/// `CompilerInput.linkBody`; the memo stays RAW.
@MainActor
final class UnratedNamesLinkedTests: XCTestCase {

    private let nick = Person(canonical: "[[Nick Jansen]]", aliases: ["Nick"], short: "Nick",
                              lastModifiedAt: "2026-01-01T00:00:00.000Z")

    private func memo(_ text: String) -> Memo {
        Memo(id: UUID(), audioFilename: "memo_x.m4a", duration: 12,
             recordedAt: Date(timeIntervalSince1970: 1_700_000_000), tags: [],
             title: nil, transcript: text, transcriptStatus: .done, significance: 0)
    }

    func testUnratedNoteRendersTheKnownPersonLinkedAndCreatesNoPipelineFile() throws {
        let container = try ModelContainer(for: PipelineFile.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let m = memo("I met Nick today.")

        let pf = MemoNoteProjection.file(for: m)
        XCTAssertTrue(MemoNoteProjection.linkNames(pf, memo: m, people: [nick]))

        // What the note view reads (`bestBodyText`) shows the name linked.
        XCTAssertTrue(pf.bestBodyText.contains("[[Nick Jansen]]"), pf.bestBodyText)
        // Unrated stays unrated, and the projection is not a row.
        XCTAssertNil(pf.significance)
        XCTAssertNil(pf.modelContext)
        XCTAssertFalse(NoteConsent.isRated(pf))
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<PipelineFile>()), 0,
                       "display linking creates no PipelineFile")
        // The memo keeps the RAW words: nothing is written back.
        XCTAssertEqual(m.transcript, "I met Nick today.")
        XCTAssertEqual(m.significance, 0)
    }

    func testNoKnownPersonLeavesTheBodyOnTheTranscript() {
        let m = memo("Walked the long way back.")
        let pf = MemoNoteProjection.file(for: m)
        XCTAssertFalse(MemoNoteProjection.linkNames(pf, memo: m, people: [nick]))
        XCTAssertNil(pf.sanitised, "nothing linked: edits keep landing on the transcript")
        XCTAssertEqual(pf.bestBodyText, "Walked the long way back.")
    }

    func testTheNotesOwnUnlinkDecisionIsHonoured() {
        let m = memo("I met Nick today.")
        m.keepNamePlain(alias: "Nick")
        let pf = MemoNoteProjection.file(for: m)
        let linked = MemoNoteProjection.linkNames(pf, memo: m, people: [nick])
        XCTAssertFalse(linked && pf.bestBodyText.contains("[[Nick Jansen]]"), pf.bestBodyText)
    }

    func testAnEditInTheLinkedBodyReachesTheMemoRaw() {
        let m = memo("I met Nick today.")
        let pf = MemoNoteProjection.file(for: m)
        MemoNoteProjection.linkNames(pf, memo: m, people: [nick])
        // The body binding writes into `sanitised` while it is set.
        pf.sanitised = "I met [[Nick Jansen]] yesterday."
        pf.transcript = MemoNoteProjection.rawTranscript(ofLinked: pf, people: [nick])
        XCTAssertEqual(pf.transcript, "I met Nick yesterday.")
        XCTAssertTrue(MemoNoteProjection.writeBack(pf, to: m))
        XCTAssertEqual(m.transcript, "I met Nick yesterday.", "the memo stays raw, no brackets")
        XCTAssertEqual(m.significance, 0, "an edit does not rate the note")
    }
}
