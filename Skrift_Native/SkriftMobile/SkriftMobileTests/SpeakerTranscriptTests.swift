import XCTest
@testable import SkriftMobile

/// `SpeakerTranscript` parsing helpers behind the assign sheet: listing the speakers in a
/// conversation, and re-fusing adjacent same-speaker turns after a reassign/merge (the
/// phantom-speaker fix). Pure string logic, so unit-tested here.
final class SpeakerTranscriptTests: XCTestCase {
    func testSpeakersInFirstAppearanceOrder() {
        let t = "**Speaker 1:** a\n\n**Speaker 2:** b\n\n**Speaker 1:** c"
        XCTAssertEqual(SpeakerTranscript.speakers(in: t), ["Speaker 1", "Speaker 2"])
        XCTAssertEqual(SpeakerTranscript.speakers(in: nil), [])
        XCTAssertEqual(SpeakerTranscript.speakers(in: "just prose"), [])
    }

    /// The realistic merge: a phantom 3rd speaker between two reals is reassigned to a
    /// neighbour (here Speaker 3 → Speaker 2 by the sheet's relabel), and the adjacent
    /// Speaker 2 turns fuse — leaving the conversation 2-speaker.
    func testMergeFoldsReassignedTurnIntoNeighbour() {
        // After the sheet relabels "**Speaker 3:**" → "**Speaker 2:**":
        let relabeled = "**Speaker 1:** hi\n\n**Speaker 2:** well\n\n**Speaker 2:** oh\n\n**Speaker 1:** why"
        let merged = SpeakerTranscript.mergeAdjacentTurns(relabeled)
        XCTAssertEqual(merged, "**Speaker 1:** hi\n\n**Speaker 2:** well oh\n\n**Speaker 1:** why")
        // Still a 2-speaker conversation (renders as turns).
        XCTAssertEqual(SpeakerTranscript.parse(merged)?.count, 3)
    }

    /// Merging the only other speaker away collapses to a single turn (→ monologue).
    func testMergeToSingleSpeakerCollapses() {
        let relabeled = "**Tiuri:** a\n\n**Tiuri:** b\n\n**Tiuri:** c"
        XCTAssertEqual(SpeakerTranscript.mergeAdjacentTurns(relabeled), "**Tiuri:** a b c")
        XCTAssertNil(SpeakerTranscript.parse("**Tiuri:** a b c"))   // 1 turn → not a conversation
    }

    func testMergeLeavesNonConversationUntouched() {
        XCTAssertEqual(SpeakerTranscript.mergeAdjacentTurns("plain prose"), "plain prose")
    }

    /// Per-LINE merge (the bug fix): reassigning ONE turn moves only that line, not every
    /// turn of the speaker. "A B A B A", merge the 2nd B (index 3) into A → "A, B, A".
    func testReassignTurnIsPerLineNotWholeSpeaker() {
        let t = "**A:** one\n\n**B:** two\n\n**A:** three\n\n**B:** four\n\n**A:** five"
        let r = SpeakerTranscript.reassign(t, turnAt: 3, to: "A")
        XCTAssertEqual(r, "**A:** one\n\n**B:** two\n\n**A:** three four five")
        XCTAssertEqual(SpeakerTranscript.parse(r)?.count, 3)   // B's first line survives → still 2 speakers
    }

    func testReassignOutOfRangeReturnsNil() {
        XCTAssertNil(SpeakerTranscript.reassign("**A:** x\n\n**B:** y", turnAt: 9, to: "A"))
        XCTAssertNil(SpeakerTranscript.reassign("plain prose", turnAt: 0, to: "A"))
    }
}
