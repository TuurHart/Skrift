import XCTest
@testable import SkriftMobile

/// Q509 (C47, C152): the phone shows a Mac edit to a conversation note. The note page renders
/// the turns of the current (non-stale) copy-edit like it does for prose, keeping the speaker
/// turns and the gutter; a turn edit lands in the text the turns came from.
final class PhoneConversationPolishTests: XCTestCase {

    private let raw = "**Bruno Costa:** We fire the platters on Thursday.\n\n**Lotte:** The kiln is booked then."
    /// The Mac's polish after his edit there: the turns de-linked, his words added.
    private let macEdit = "**Bruno:** We fire the platters and the shelves on Thursday.\n\n**Lotte:** The kiln is booked then."

    private let bruno = Person(canonical: "[[Bruno Costa]]", aliases: ["Bruno"], short: "Bruno",
                               lastModifiedAt: "2026-09-25T09:00:00Z")
    private let lotte = Person(canonical: "[[Lotte Vos]]", aliases: ["Lotte"], short: "Lotte",
                               lastModifiedAt: "2026-09-01T09:00:00Z")

    private func memo() -> Memo {
        Memo(id: UUID(), audioFilename: "memo.m4a", recordedAt: Date(), transcript: raw,
             transcriptStatus: .done, transcriptConfidence: 0.9, significance: 0.6)
    }

    private func polish(_ m: Memo, copyedit: String, at: Date = Date()) -> MemoEnhancement {
        MemoEnhancement(memoID: m.id, copyedit: copyedit, title: "Kiln week",
                        enhancedByDeviceID: "mac-1", enhancedAt: at)
    }

    func testTheMacsConversationEditIsWhatThePhoneShows() throws {
        let m = memo()
        let e = polish(m, copyedit: macEdit)

        let shown = try XCTUnwrap(ConversationPolish.shown(e, for: m))
        let turns = try XCTUnwrap(SpeakerTranscript.parse(ConversationPolish.body(for: m, polish: shown)))
        XCTAssertEqual(turns.count, 2, "still speaker turns")
        XCTAssertEqual(turns.map(\.name), ["Bruno", "Lotte"])
        XCTAssertTrue(turns[0].text.contains("and the shelves"), "his Mac edit: \(turns[0].text)")
    }

    func testTheGutterKeepsTheSameSpeakers() throws {
        let m = memo()
        let shownTurns = try XCTUnwrap(SpeakerTranscript.parse(macEdit))
        let rawTurns = try XCTUnwrap(SpeakerTranscript.parse(m.transcript))
        let people = [bruno, lotte]
        XCTAssertEqual(SpeakerTurnStyle.slots(forParsedNames: shownTurns.map(\.name), people: people),
                       SpeakerTurnStyle.slots(forParsedNames: rawTurns.map(\.name), people: people),
                       "`Bruno` and `Bruno Costa` are one voice in the gutter")
    }

    func testAStalePolishShowsHisRawTurns() {
        let m = memo()
        let e = polish(m, copyedit: macEdit, at: Date().addingTimeInterval(-60))
        m.transcriptEditedAt = Date()   // he edited the raw turns after the Mac's polish (C153)

        XCTAssertNil(ConversationPolish.shown(e, for: m))
        XCTAssertEqual(ConversationPolish.body(for: m, polish: nil), raw)
    }

    func testAPolishThatIsNotTurnsNeverReplacesThem() {
        let m = memo()
        XCTAssertNil(ConversationPolish.shown(polish(m, copyedit: "One flat paragraph about the kiln."), for: m))
        XCTAssertNil(ConversationPolish.shown(nil, for: m))
    }

    func testAProseNoteIsNotAConversation() {
        let m = Memo(id: UUID(), audioFilename: "memo.m4a", recordedAt: Date(), transcript: "Just words.",
                     transcriptStatus: .done, transcriptConfidence: 0.9, significance: 0.6)
        XCTAssertNil(ConversationPolish.shown(polish(m, copyedit: macEdit), for: m))
    }

    // MARK: - a turn edit lands where the turns came from

    func testATurnEditOnShownPolishWritesThePolish() throws {
        let m = memo()
        let e = polish(m, copyedit: macEdit, at: Date().addingTimeInterval(-60))
        let now = Date()

        XCTAssertTrue(ConversationPolish.apply({ SpeakerTranscript.setText($0, turnAt: 1, to: "The kiln is free then.") },
                                               to: m, polish: e, device: "phone-1", now: now))

        XCTAssertTrue(e.copyedit.contains("**Lotte:** The kiln is free then."), e.copyedit)
        XCTAssertTrue(e.copyedit.contains("and the shelves"), "his Mac edit stays")
        XCTAssertEqual(e.enhancedByDeviceID, "phone-1")
        XCTAssertEqual(e.enhancedAt, now)
        XCTAssertEqual(m.transcript, raw, "the raw turns are untouched")
        XCTAssertNil(m.transcriptEditedAt, "not a raw edit, so the polish does not go stale")
    }

    func testATurnEditWithNoPolishWritesTheTranscript() {
        let m = memo()
        let now = Date()

        XCTAssertTrue(ConversationPolish.apply({ SpeakerTranscript.setText($0, turnAt: 0, to: "We fire on Friday.") },
                                               to: m, polish: nil, now: now))

        XCTAssertTrue(m.transcript?.contains("We fire on Friday.") == true)
        XCTAssertTrue(m.transcriptUserEdited)
        XCTAssertEqual(m.transcriptEditedAt, now)
    }

    func testAnUnchangedTurnEditWritesNothing() {
        let m = memo()
        let e = polish(m, copyedit: macEdit)
        let stamp = e.enhancedAt
        XCTAssertFalse(ConversationPolish.apply({ $0 }, to: m, polish: e))
        XCTAssertEqual(e.enhancedAt, stamp)
    }
}
