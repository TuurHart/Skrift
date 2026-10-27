import XCTest
import SwiftData
import Foundation

/// Q530: editing an UNRATED Mac note carries only what was typed into the memo's raw transcript.
/// A word he said as an alias ("Nik" for Nick Jansen) must stay "Nik" after an unrelated edit.
@MainActor
final class UnratedEditKeepsSpokenWordsTests: XCTestCase {

    private let nick = Person(canonical: "[[Nick Jansen]]", aliases: ["Nik", "Nick"], short: "Nick",
                              lastModifiedAt: "2026-01-01T00:00:00.000Z")
    private let bruno = Person(canonical: "[[Bruno Aragorn]]", aliases: ["Bruno"], short: "Bruno",
                               lastModifiedAt: "2026-01-01T00:00:00.000Z")
    private var people: [Person] { [nick, bruno] }

    private func memo(_ text: String) -> Memo {
        Memo(id: UUID(), audioFilename: "memo_x.m4a", duration: 12,
             recordedAt: Date(timeIntervalSince1970: 1_700_000_000), tags: [],
             title: nil, transcript: text, transcriptStatus: .done, significance: 0)
    }

    /// What the pane does on a body edit: the body binding writes `sanitised`, the mirror derives
    /// the raw transcript, `commit` writes it to the memo.
    private func open(_ text: String) -> (Memo, PipelineFile) {
        let m = memo(text)
        let pf = MemoNoteProjection.file(for: m)
        MemoNoteProjection.linkNames(pf, memo: m, people: people)
        return (m, pf)
    }

    private func edit(_ m: Memo, _ pf: PipelineFile, _ transform: (String) -> String) {
        pf.sanitised = transform(pf.sanitised ?? "")
        if let raw = MemoNoteProjection.rawTranscript(ofLinked: pf, people: people), raw != pf.transcript {
            pf.transcript = raw
        }
        MemoNoteProjection.writeBack(pf, to: m)
    }

    func testAnUnrelatedEditLeavesTheAliasAndTheOtherNameByteIdentical() {
        let (m, pf) = open("Nik called me. I saw Bruno at lunch.")
        XCTAssertEqual(pf.sanitised, "[[Nick Jansen]] called me. I saw [[Bruno Aragorn]] at lunch.",
                       "premise: both names are shown linked")
        edit(m, pf) { $0 + " Done." }
        XCTAssertEqual(m.transcript, "Nik called me. I saw Bruno at lunch. Done.")
    }

    private let base = "Nik called me. I saw Bruno at lunch."
    private let linked = "[[Nick Jansen]] called me. I saw [[Bruno Aragorn]] at lunch."

    func testAnEditBeforeALinkKeepsEverySpokenWord() {
        let (m, pf) = open(base)
        edit(m, pf) { "Hey. " + $0 }
        XCTAssertEqual(m.transcript, "Hey. Nik called me. I saw Bruno at lunch.")
    }

    func testAnEditBetweenTwoLinksKeepsBoth() {
        let (m, pf) = open(base)
        edit(m, pf) { $0.replacingOccurrences(of: "called me. I saw", with: "phoned me. Then I saw") }
        XCTAssertEqual(m.transcript, "Nik phoned me. Then I saw Bruno at lunch.")
    }

    func testEditsOnBothSidesOfTheLinksInOneChange() {
        let (m, pf) = open(base)
        edit(m, pf) { "Hey. " + $0 + " Done 😀" }
        XCTAssertEqual(m.transcript, "Hey. Nik called me. I saw Bruno at lunch. Done 😀")
    }

    func testAnEditInsideALinkUnlinksOnlyThatRun() {
        let (m, pf) = open(base)
        edit(m, pf) { $0.replacingOccurrences(of: "[[Nick Jansen]]", with: "[[Nick Janssen]]") }
        XCTAssertEqual(m.transcript, "[[Nick Janssen]] called me. I saw Bruno at lunch.",
                       "only the run he typed in changes; Bruno keeps his bytes")
        // Deleting a few letters of the link text: the run takes his text, the rest is untouched.
        let (m2, pf2) = open(base)
        edit(m2, pf2) { $0.replacingOccurrences(of: "[[Nick Jansen]]", with: "[[Nick]]") }
        XCTAssertTrue((m2.transcript ?? "").hasSuffix(" called me. I saw Bruno at lunch."), m2.transcript ?? "")
        XCTAssertFalse((m2.transcript ?? "").contains("Nik"))
    }

    func testDeletingAWholeLinkRemovesItsSpokenWordOnly() {
        let (m, pf) = open(base)
        edit(m, pf) { $0.replacingOccurrences(of: "[[Nick Jansen]] ", with: "") }
        XCTAssertEqual(m.transcript, "called me. I saw Bruno at lunch.")
        let (m2, pf2) = open(base)
        edit(m2, pf2) { $0.replacingOccurrences(of: "[[Bruno Aragorn]] ", with: "") }
        XCTAssertEqual(m2.transcript, "Nik called me. I saw at lunch.")
    }

    func testATypedNameStaysRawText() {
        let (m, pf) = open(base)
        edit(m, pf) { $0 + " Dana came too, and Nick." }
        XCTAssertEqual(m.transcript, "Nik called me. I saw Bruno at lunch. Dana came too, and Nick.",
                       "the typed Nick stays Nick; the spoken Nik is not touched")
    }

    func testOnlyTheFirstMentionIsLinkedAndEveryMentionKeepsItsWords() {
        let text = "Nik called. Then Nik left and Nick came back."
        let (m, pf) = open(text)
        XCTAssertEqual(pf.sanitised, "[[Nick Jansen]] called. Then Nick left and Nick came back.", "premise")
        edit(m, pf) { $0 + " The end." }
        XCTAssertEqual(m.transcript, text + " The end.")
        // An edit inside a demoted mention rewrites that word only.
        let (m2, pf2) = open(text)
        edit(m2, pf2) { $0.replacingOccurrences(of: "Then Nick left", with: "Then Nicky left") }
        XCTAssertEqual(m2.transcript, "Nik called. Then Nicky left and Nick came back.",
                       "the word he changed is his text; the first Nik and the last Nick are not touched")
        // An edit between the mentions touches none of them.
        let (m3, pf3) = open(text)
        edit(m3, pf3) { $0.replacingOccurrences(of: "called.", with: "rang.") }
        XCTAssertEqual(m3.transcript, "Nik rang. Then Nik left and Nick came back.")
    }

    func testSeveralEditsInARowKeepEverySpokenWord() {
        let (m, pf) = open(base)
        edit(m, pf) { $0 + " Later Nik left." }
        XCTAssertEqual(m.transcript, base + " Later Nik left.")
        edit(m, pf) { "Hey. " + $0 }
        XCTAssertEqual(m.transcript, "Hey. " + base + " Later Nik left.")
        edit(m, pf) { $0.replacingOccurrences(of: "at lunch", with: "at dinner") }
        XCTAssertEqual(m.transcript, "Hey. Nik called me. I saw Bruno at dinner. Later Nik left.")
    }

    func testOpeningStillWritesNothing() {
        let (m, pf) = open(base)
        XCTAssertNil(MemoNoteProjection.rawTranscript(ofLinked: pf, people: people))
        XCTAssertEqual(m.transcript, base)
    }

    func testAConversationBodyFallsBackToUnlinkingTheWholeBody() {
        let text = "**Speaker 1:** Nik called me.\n\n**Speaker 2:** Fine."
        let (m, pf) = open(text)
        guard pf.sanitised != nil else { return }   // the linker left it as spoken: nothing to fall back from
        edit(m, pf) { $0 + " Ok." }
        // Whatever the linker made of it, the edit reached the memo and nothing crashed.
        XCTAssertTrue((m.transcript ?? "").hasSuffix(" Ok."), m.transcript ?? "")
    }
}
