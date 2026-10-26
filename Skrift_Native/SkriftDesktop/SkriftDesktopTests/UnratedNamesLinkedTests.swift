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

    /// Opening a note must never rewrite the synced memo: for every shape of body, load then
    /// "the pane's mirror" (what `.onChange(of: sanitised)` would run) hands back nothing.
    func testLoadWithoutAnEditNeverRewritesTheTranscript() {
        let nicky = Person(canonical: "[[Nick Jansen]]", aliases: ["Nick", "Nicky"], short: "Nick",
                           lastModifiedAt: "2026-01-01T00:00:00.000Z")
        let bodies = [
            "I met Nick Jansen today.",                    // full name spoken
            "I met Nicky today.",                          // alias spoken
            "I met Nick today.",                           // short name spoken
            "Nick came. Then nick left. Nick again.",      // repeats, mixed case
            "NICK said hello.",                            // upper case
            "Remember [[Some Idea]] and Nick.",            // his own link beside a name
            "Only [[Some Idea]] here.",                    // his own link alone
            "The Nickelback gig, nicknames too.",          // a name inside a word
            "  Nick  \n\n\n and   spacing\t ",             // spacing
        ]
        for text in bodies {
            let m = memo(text)
            let pf = MemoNoteProjection.file(for: m)
            MemoNoteProjection.linkNames(pf, memo: m, people: [nicky])
            XCTAssertNil(MemoNoteProjection.rawTranscript(ofLinked: pf, people: [nicky]),
                         "opening must not mirror: \(text.debugDescription) -> \(pf.sanitised.debugDescription)")
            XCTAssertEqual(pf.transcript, text)
            XCTAssertEqual(m.transcript, text)
            // A roster re-link of the open note (same shape the refresh runs) is not an edit either.
            pf.relinkNames(working: text, isConversation: false, people: [nicky])
            XCTAssertNil(MemoNoteProjection.rawTranscript(ofLinked: pf, people: [nicky]), text.debugDescription)
        }
    }

    /// A real edit after load carries back with the edit, and his own `[[Some Idea]]` keeps its brackets.
    func testARealEditAfterLoadMirrorsBackAndKeepsHisOwnBrackets() {
        let m = memo("Remember [[Some Idea]] and Nick.")
        let pf = MemoNoteProjection.file(for: m)
        MemoNoteProjection.linkNames(pf, memo: m, people: [nick])
        XCTAssertNotNil(pf.sanitised)
        pf.sanitised = (pf.sanitised ?? "") + " Plus more."   // the body binding writes here
        let raw = MemoNoteProjection.rawTranscript(ofLinked: pf, people: [nick])
        XCTAssertEqual(raw, "Remember [[Some Idea]] and Nick. Plus more.")
        pf.transcript = raw
        XCTAssertTrue(MemoNoteProjection.writeBack(pf, to: m))
        XCTAssertEqual(m.transcript, "Remember [[Some Idea]] and Nick. Plus more.")
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
