import XCTest
import Foundation

/// `SpeakerTurnStyle` — the SHARED rule behind the conversation turn gutter (signed mock
/// `mocks/conversation-turns-D-hifi.html`, E1): which speaker owns which turn, and which
/// hue slot they wear. Both apps render from this, so a speaker can't be one colour on the
/// Mac and another on the phone.
final class SpeakerTurnStyleTests: XCTestCase {

    private func person(_ canonical: String, _ aliases: [String], short: String? = nil) -> Person {
        Person(canonical: "[[\(canonical)]]", aliases: aliases, short: short,
               lastModifiedAt: "2026-07-27T00:00:00Z")
    }

    private var roster: [Person] {
        [person("Tiuri Hartog", ["Tiuri Hartog", "Tiuri", "Tuur"], short: "Tiuri"),
         person("Bulldops", ["Bulldops"])]
    }

    /// THE bug this rule exists to kill. Conversation naming writes a speaker's FIRST header
    /// as the full `[[Tiuri Hartog]]` and every later one as the short `Tiuri` — a map keyed
    /// on the header TEXT hands one voice two colours.
    func testFirstMentionAndShortNameAreOneSpeaker() {
        let body = """
        **[[Tiuri Hartog]]:** They get

        **[[Bulldops]]:** together in Droof.

        **Tiuri:** Droof is a place in Wageningen.

        **Bulldops:** Yes, where I live.
        """
        let turns = SpeakerTurnStyle.turns(in: body, people: roster)
        XCTAssertEqual(turns.map(\.slot), [0, 1, 0, 1])
        XCTAssertEqual(turns.map(\.display), ["Tiuri Hartog", "Bulldops", "Tiuri", "Bulldops"])
        XCTAssertEqual(turns.map(\.isLinked), [true, true, false, false])
    }

    /// The invariant `Palette.speakerHues` is written against: renaming a speaker must not
    /// reshuffle the note's colours. "Speaker 2" → "Bulldops" keeps slot 1.
    func testRenamingASpeakerDoesNotReshuffleColours() {
        let before = "**[[Tiuri Hartog]]:** Hi.\n\n**Speaker 2:** Hello.\n\n**Tiuri:** Bye."
        let after  = "**[[Tiuri Hartog]]:** Hi.\n\n**[[Bulldops]]:** Hello.\n\n**Tiuri:** Bye."
        XCTAssertEqual(SpeakerTurnStyle.turns(in: before, people: roster).map(\.slot), [0, 1, 0])
        XCTAssertEqual(SpeakerTurnStyle.turns(in: after, people: roster).map(\.slot), [0, 1, 0])
    }

    /// The header range must cover the WHOLE `**Name:**` literal, because the Mac stands a
    /// single gutter glyph in for it and reconstructs it from `literal` for the model/export.
    func testHeaderRangeCoversTheWholeMarkdownLiteral() {
        let body = "**Tiuri:** one\n\n**Bulldops:** two"
        let ns = body as NSString
        let turns = SpeakerTurnStyle.turns(in: body, people: roster)
        XCTAssertEqual(turns.count, 2)
        XCTAssertEqual(ns.substring(with: turns[0].headerRange), "**Tiuri:** ")
        XCTAssertEqual(ns.substring(with: turns[1].headerRange), "**Bulldops:** ")
    }

    /// A lone bold lead-in is NOT a conversation — it must never sprout a 118pt gutter.
    func testSingleHeaderIsNotAConversation() {
        XCTAssertTrue(SpeakerTurnStyle.turns(in: "**Note:** buy milk", people: roster).isEmpty)
    }

    /// Two headers that resolve to the SAME person aren't a conversation either (one voice).
    func testOneSpeakerUnderTwoNamesIsNotAConversation() {
        let body = "**[[Tiuri Hartog]]:** one\n\n**Tuur:** two"
        XCTAssertTrue(SpeakerTurnStyle.turns(in: body, people: roster).isEmpty)
    }

    /// Mid-sentence `**bold:**` is not a turn header — the line anchor is load-bearing
    /// (the 2026-06-14 false positive that skipped copy-edit on ordinary notes).
    func testInlineBoldIsNotATurnHeader() {
        let body = "I weighed it up — **pros:** cheap, **cons:** slow."
        XCTAssertTrue(SpeakerTurnStyle.turns(in: body, people: roster).isEmpty)
    }

    /// Unknown speakers stay distinct from each other rather than collapsing to one colour.
    func testUnresolvedSpeakersGetSeparateSlots() {
        let body = "**Speaker 1:** a\n\n**Speaker 2:** b\n\n**Speaker 1:** c"
        XCTAssertEqual(SpeakerTurnStyle.turns(in: body, people: []).map(\.slot), [0, 1, 0])
    }

    /// An Obsidian alias-display header shows the SPOKEN part in the gutter.
    func testAliasDisplayHeaderShowsTheSpokenName() {
        XCTAssertEqual(SpeakerTurnStyle.label(for: "Tiuri Hartog|Tuur"), "Tuur")
        XCTAssertEqual(SpeakerTurnStyle.label(for: "Tiuri Hartog"), "Tiuri Hartog")
        XCTAssertEqual(SpeakerTurnStyle.label(for: "Tiuri Hartog|"), "Tiuri Hartog")
    }

    /// The phone's entry point must agree with the Mac's, turn for turn — that agreement is
    /// the entire reason this rule is shared rather than written twice.
    func testParsedNameSlotsMatchTheRangeBasedTurns() {
        let body = """
        **[[Tiuri Hartog]]:** one

        **[[Bulldops]]:** two

        **Tiuri:** three

        **Bulldops:** four
        """
        let mac = SpeakerTurnStyle.turns(in: body, people: roster).map(\.slot)
        let names = SpeakerTranscript.parse(body)!.map(\.name)
        XCTAssertEqual(SpeakerTurnStyle.slots(forParsedNames: names, people: roster), mac)
    }

    /// The resolver the Sanitiser now shares: canonical key, unambiguous alias, nothing else.
    func testHeaderResolverMatchesCanonicalAndUnambiguousAlias() {
        let r = SpeakerTurnStyle.HeaderResolver(people: roster)
        XCTAssertEqual(r.person(for: "Tiuri Hartog")?.displayName, "Tiuri Hartog")
        XCTAssertEqual(r.person(for: "tuur")?.displayName, "Tiuri Hartog")
        XCTAssertNil(r.person(for: "Speaker 2"))
        XCTAssertNil(r.person(for: ""))
    }

    /// An alias two people share resolves to NEITHER — an ambiguous header stays plain, so
    /// the two Jacks can't be silently merged into one colour.
    func testAmbiguousAliasResolvesToNobody() {
        let twins = [person("Jack Smith", ["Jack Smith", "Jack"]),
                     person("Jack Jones", ["Jack Jones", "Jack"])]
        let r = SpeakerTurnStyle.HeaderResolver(people: twins)
        XCTAssertNil(r.person(for: "Jack"))
        XCTAssertEqual(r.person(for: "Jack Smith")?.displayName, "Jack Smith")
    }
}
