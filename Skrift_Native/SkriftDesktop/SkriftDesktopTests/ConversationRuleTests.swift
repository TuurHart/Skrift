import XCTest
import Foundation

/// Q292 / D175 + D178: ONE conversation rule on both apps. A note is a conversation when it is a
/// RECORDING whose transcript parses with two or more speaker headers, named or `Speaker N`.
/// Distinct names are not required; a typed note or capture is never a conversation.
final class ConversationRuleTests: XCTestCase {

    private func yes(_ t: String?, _ s: NoteSourceType = .audio) -> Bool {
        SpeakerTranscript.isConversation(t, source: s)
    }

    func testTwoNamedHeadersIsAConversation() {
        XCTAssertTrue(yes("**Tiuri:** hi\n\n**Roksana:** yo"))
    }

    func testTwoSpeakerNHeadersIsAConversation() {
        XCTAssertTrue(yes("**Speaker 1:** hi\n\n**Speaker 2:** yo"))
    }

    func testTwoHeadersWithTheSameNameIsAConversation() {
        XCTAssertTrue(yes("**Tiuri:** hi\n\n**Tiuri:** and again"),
                      "distinct names are no longer required (D175)")
    }

    func testThreeHeadersIsAConversation() {
        XCTAssertTrue(yes("**A:** 1\n\n**B:** 2\n\n**A:** 3"))
    }

    func testOneHeaderIsNotAConversation() {
        XCTAssertFalse(yes("**Tiuri:** only me"))
    }

    func testMonologueNilAndEmptyAreNotConversations() {
        XCTAssertFalse(yes("just a plain monologue"))
        XCTAssertFalse(yes(nil))
        XCTAssertFalse(yes(""))
    }

    func testInlineBoldLabelsMidSentenceAreNotConversations() {
        XCTAssertFalse(yes("Notes. **Pros:** fast. **Cons:** pricey."))
    }

    /// D178: a typed note with two distinct bold labels is NOT a conversation.
    func testTypedNoteWithTwoDistinctBoldLabelsIsNotAConversation() {
        let typed = "**Pros:** fast\n\n**Cons:** pricey"
        XCTAssertNotNil(SpeakerTranscript.parse(typed), "fixture parses as headers")
        XCTAssertFalse(yes(typed, .note))
    }

    func testTypedNoteWithRepeatedBoldLabelsIsNotAConversation() {
        XCTAssertFalse(yes("**Pros:** a\n\n**Pros:** b", .note))
    }

    func testCaptureIsNeverAConversation() {
        XCTAssertFalse(yes("**Tiuri:** hi\n\n**Roksana:** yo", .capture))
    }

    /// For a recording the rule is exactly "the parser found headers".
    func testRecordingRuleIsExactlyParseSucceeds() {
        for t in ["**A:** x\n\n**B:** y", "**A:** x\n\n**A:** y", "**A:** x", "plain", ""] {
            XCTAssertEqual(yes(t), SpeakerTranscript.parse(t) != nil, t)
        }
    }

    /// The Mac note menu reads the same shared rule through the note's source type.
    func testMacNoteMenuUsesTheSharedRule() {
        let body = "**Tiuri:** hi\n\n**Tiuri:** and again"
        let audio = PipelineFile(id: UUID().uuidString, filename: "a.m4a")
        audio.sourceType = .audio
        audio.transcript = body
        XCTAssertTrue(MacNoteMenu.isConversation(audio))
        let note = PipelineFile(id: UUID().uuidString, filename: "n.md")
        note.sourceType = .note
        note.transcript = body
        XCTAssertFalse(MacNoteMenu.isConversation(note))
    }

    /// The shared export linker: a typed note's `**Name:**` lines are not routed to the turn
    /// linker, a recording's are (D178).
    func testLinkBodyRoutesOnlyRecordingsToTheConversationLinker() {
        let nick = Person(canonical: "[[Nick Jansen]]", aliases: ["Nick"], short: "Nick",
                          lastModifiedAt: "2026-01-01T00:00:00.000Z")
        let raw = "**Nick:** Hello there.\n\n**Speaker 2:** Hi."
        XCTAssertEqual(CompilerInput.linkBody(raw, source: .audio, people: [nick]),
                       Sanitiser.processConversation(text: raw, people: [nick]).sanitised)
        XCTAssertEqual(CompilerInput.linkBody(raw, source: .note, people: [nick]),
                       Sanitiser.process(text: raw, people: [nick]).sanitised)
    }
}
