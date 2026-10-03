import XCTest
import Foundation

/// Q292 / D175: ONE conversation rule on both apps. A transcript is a conversation when it
/// parses with two or more speaker headers, named or `Speaker N`; distinct names are not required.
final class ConversationRuleTests: XCTestCase {

    func testTwoNamedHeadersIsAConversation() {
        XCTAssertTrue(SpeakerTranscript.isConversation("**Tiuri:** hi\n\n**Roksana:** yo"))
    }

    func testTwoSpeakerNHeadersIsAConversation() {
        XCTAssertTrue(SpeakerTranscript.isConversation("**Speaker 1:** hi\n\n**Speaker 2:** yo"))
    }

    func testTwoHeadersWithTheSameNameIsAConversation() {
        XCTAssertTrue(SpeakerTranscript.isConversation("**Tiuri:** hi\n\n**Tiuri:** and again"),
                      "distinct names are no longer required (D175)")
    }

    func testThreeHeadersIsAConversation() {
        XCTAssertTrue(SpeakerTranscript.isConversation("**A:** 1\n\n**B:** 2\n\n**A:** 3"))
    }

    func testOneHeaderIsNotAConversation() {
        XCTAssertFalse(SpeakerTranscript.isConversation("**Tiuri:** only me"))
    }

    func testMonologueNilAndEmptyAreNotConversations() {
        XCTAssertFalse(SpeakerTranscript.isConversation("just a plain monologue"))
        XCTAssertFalse(SpeakerTranscript.isConversation(nil))
        XCTAssertFalse(SpeakerTranscript.isConversation(""))
    }

    func testInlineBoldLabelsMidSentenceAreNotConversations() {
        XCTAssertFalse(SpeakerTranscript.isConversation("Notes. **Pros:** fast. **Cons:** pricey."))
    }

    /// The rule agrees with the parser the phone's views use (`parse != nil`).
    func testRuleIsExactlyParseSucceeds() {
        for t in ["**A:** x\n\n**B:** y", "**A:** x\n\n**A:** y", "**A:** x", "plain", ""] {
            XCTAssertEqual(SpeakerTranscript.isConversation(t), SpeakerTranscript.parse(t) != nil, t)
        }
    }

    /// The Mac adds only "is an audio memo" on top of the shared text rule.
    func testMacNoteMenuUsesTheSameRuleForAudioOnly() {
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
}
