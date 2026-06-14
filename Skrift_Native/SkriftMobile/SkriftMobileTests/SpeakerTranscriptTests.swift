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

    /// Inline turn-text edit: replace only that turn's text, keep its speaker (move a
    /// boundary word — trim "time." off the front of B's line; you'd append it to A separately).
    func testSetTextReplacesOnlyThatTurnsText() {
        let t = "**Tiuri:** recognize you next time\n\n**Roksana:** time. You stole my data"
        XCTAssertEqual(SpeakerTranscript.setText(t, turnAt: 1, to: "You stole my data"),
                       "**Tiuri:** recognize you next time\n\n**Roksana:** You stole my data")
        XCTAssertNil(SpeakerTranscript.setText(t, turnAt: 9, to: "x"))
        XCTAssertNil(SpeakerTranscript.setText("plain prose", turnAt: 0, to: "x"))
    }

    /// Slot-aware rename: two turns share the display name "Tiuri" but are DIFFERENT slots
    /// (one voice split into two). Renaming slot 1 must move ONLY slot 1's turn — slot 0's
    /// "Tiuri" stays (the same-name-collapse bug). turnSlots = [0, 1, 2].
    func testRelabelSlotRenamesOnlyThatSlot() {
        let t = "**Tiuri:** hi\n\n**Tiuri:** there\n\n**Roksana:** ok"
        XCTAssertEqual(SpeakerTranscript.relabelSlot(t, turnSlots: [0, 1, 2], slot: 1, to: "Sam"),
                       "**Tiuri:** hi\n\n**Sam:** there\n\n**Roksana:** ok")
    }

    /// Renaming a slot to a name an adjacent turn already has merges them (the desired
    /// "these two slots are actually the same person" outcome).
    func testRelabelSlotMergesWhenItMakesAdjacentSameSpeaker() {
        let t = "**A:** one\n\n**B:** two\n\n**A:** three"
        XCTAssertEqual(SpeakerTranscript.relabelSlot(t, turnSlots: [0, 1, 0], slot: 1, to: "A"),
                       "**A:** one two three")
    }

    /// A stale slot map (count ≠ current turns, e.g. after a structural edit) returns nil
    /// so the caller falls back to name-based relabeling.
    func testRelabelSlotNilOnStaleMap() {
        XCTAssertNil(SpeakerTranscript.relabelSlot("**A:** x\n\n**B:** y", turnSlots: [0], slot: 0, to: "Z"))
        XCTAssertNil(SpeakerTranscript.relabelSlot("plain prose", turnSlots: [0], slot: 0, to: "Z"))
    }

    /// `turnSlots` round-trips through the diar sidecar JSON, and is absent (nil) on an
    /// older sidecar — byte-compatible (encodeIfPresent).
    func testDiarizationDataTurnSlotsRoundTripAndOptional() throws {
        let data = DiarizationData(segments: [DiarizedSegment(speaker: 0, start: 0, end: 1)],
                                   slotNames: ["0": "Tiuri"], turnSlots: [0, 1, 0])
        let decoded = try JSONDecoder().decode(DiarizationData.self, from: JSONEncoder().encode(data))
        XCTAssertEqual(decoded.turnSlots, [0, 1, 0])
        // Older sidecar without the key decodes to nil + omits it on re-encode.
        let legacy = Data(#"{"segments":[],"slotNames":{}}"#.utf8)
        let old = try JSONDecoder().decode(DiarizationData.self, from: legacy)
        XCTAssertNil(old.turnSlots)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(old), as: UTF8.self).contains("turnSlots"))
    }

    /// Inline photos coexist with turns: an `[[img_NNN]]` marker stays inside the turn it
    /// was spoken in, and isn't counted as a spoken word (so karaoke stays aligned).
    func testImageMarkerStaysInTurnAndIsntASpokenWord() {
        let turns = SpeakerTranscript.parse("**Tiuri:** hello [[img_001]] world\n\n**Roksana:** hi there")
        XCTAssertEqual(turns?.first?.text, "hello [[img_001]] world")
        XCTAssertEqual(SpeakerTurnsView.spokenWordCount("hello [[img_001]] world"), 2)
        XCTAssertEqual(SpeakerTurnsView.spokenWordCount("[[img_001]] hi"), 1)
    }
}
