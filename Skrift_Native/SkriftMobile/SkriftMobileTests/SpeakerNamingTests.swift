import XCTest
@testable import SkriftMobile

/// Q82 group 11: naming a speaker is ONE shared rule (`SpeakerNaming`) — matched by resolved
/// identity, so a full-name first turn and a short-name later turn are the same speaker.
/// Identical file in the phone and Mac test targets: same input, same output.
final class SpeakerNamingTests: XCTestCase {

    private let people = [Person(canonical: "[[Tiuri Hartog]]", aliases: ["Tiuri"], short: "Tiuri",
                                 lastModifiedAt: "2027-01-15T08:00:00Z")]
    private let convo = "**[[Tiuri Hartog]]:** hello there\n\n**Speaker 2:** hi\n\n**Tiuri:** and again"

    func testRenameFollowsTheIdentityNotTheHeaderText() {
        let out = SpeakerNaming.rename(convo, displayed: "Tiuri", to: " Bob ", people: people)
        XCTAssertNotNil(out)
        XCTAssertTrue(out!.contains("**Bob:** hello there"), out!)
        XCTAssertTrue(out!.contains("**Bob:** and again"), out!)
        XCTAssertTrue(out!.contains("**Speaker 2:** hi"), out!)
        XCTAssertFalse(out!.contains("Tiuri"), "both spellings of the speaker were renamed: \(out!)")
    }

    func testSlotMapRenamesOnlyThatSlot() {
        let out = SpeakerNaming.rename(convo, displayed: "Speaker 2", to: "Sam", people: people,
                                       turnSlots: [0, 1, 0], slot: 1)
        XCTAssertNotNil(out)
        XCTAssertTrue(out!.contains("**Sam:** hi"), out!)
        XCTAssertTrue(out!.contains("Tiuri"), "the other slot is untouched: \(out!)")
    }

    func testBlankNameOrNoConversationIsNil() {
        XCTAssertNil(SpeakerNaming.rename(convo, displayed: "Tiuri", to: "  ", people: people))
        XCTAssertNil(SpeakerNaming.rename("just a monologue", displayed: "Tiuri", to: "Bob", people: people))
    }

    func testOtherSpeakersAreDistinctIdentitiesInOrder() {
        XCTAssertEqual(SpeakerNaming.otherSpeakers(than: "Tiuri", in: convo, people: people), ["Speaker 2"])
        XCTAssertEqual(SpeakerNaming.otherSpeakers(than: "Speaker 2", in: convo, people: people).count, 1,
                       "Tiuri's two spellings are one speaker")
    }
}
