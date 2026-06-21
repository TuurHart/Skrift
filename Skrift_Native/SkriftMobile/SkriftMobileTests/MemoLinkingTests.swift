import XCTest
@testable import SkriftMobile

/// On-device name-linking (standalone Phase 2): the phone re-derives `[[Name]]` links from the
/// RAW transcript via the SAME shared `Sanitiser` the Mac uses, for standalone Obsidian export.
/// These prove the wiring + routing on iOS; full linker behaviour is covered by the desktop
/// `SanitiserTests`/`NamingGoldenTests` (the SAME shared source → identical by construction).
final class MemoLinkingTests: XCTestCase {

    private let hendri = Person(canonical: "[[Hendri van Niekerk]]",
                                aliases: ["Hendri van Niekerk", "Hendri"],
                                short: "Hendri",
                                lastModifiedAt: "2026-01-01T00:00:00Z")

    /// A monologue routes through `Sanitiser.process` and actually links a distinctive name.
    func testMonologueLinksDistinctiveName() {
        let raw = "Met up with Hendri today."
        let linked = MemoLinking.linkedTranscript(raw, people: [hendri])
        XCTAssertTrue(linked.contains("[[Hendri van Niekerk]]"),
                      "distinctive name should auto-link on export — got: \(linked)")
        // Routing proof: identical to calling the monologue linker directly.
        XCTAssertEqual(linked, Sanitiser.process(text: raw, people: [hendri]).sanitised)
    }

    /// A ≥2-turn `**Name:**` transcript routes through the CONVERSATION linker.
    func testConversationRoutesToConversationLinker() {
        let raw = "**Hendri:** Hey, how's it going?\n\n**Sam:** Pretty good, thanks."
        XCTAssertNotNil(SpeakerTranscript.parse(raw), "fixture must be a conversation")
        let linked = MemoLinking.linkedTranscript(raw, people: [hendri])
        XCTAssertEqual(linked, Sanitiser.processConversation(text: raw, people: [hendri]).sanitised,
                       "attributed transcript must use processConversation, not process")
    }

    /// Deleted (tombstoned) people are excluded — a deleted person's name stays plain.
    func testDeletedPeopleExcluded() {
        let deleted = Person(canonical: "[[Hendri van Niekerk]]", aliases: ["Hendri"],
                             short: "Hendri", lastModifiedAt: "2026-01-01T00:00:00Z", deleted: true)
        let raw = "Met up with Hendri today."
        XCTAssertEqual(MemoLinking.linkedTranscript(raw, people: [deleted]), raw,
                       "a deleted person must not link")
    }

    /// No live people → the raw transcript passes through unchanged.
    func testNoPeoplePassthrough() {
        let raw = "Met up with Hendri today."
        XCTAssertEqual(MemoLinking.linkedTranscript(raw, people: []), raw)
    }

    /// Empty / nil transcript → empty string, never a crash.
    func testEmptyTranscript() {
        XCTAssertEqual(MemoLinking.linkedTranscript("", people: [hendri]), "")
        XCTAssertEqual(MemoLinking.linkedTranscript(nil, people: [hendri]), "")
    }

    /// Re-derivation is deterministic (no hidden state) — same input, same output.
    func testDeterministic() {
        let raw = "Met up with Hendri today."
        XCTAssertEqual(MemoLinking.linkedTranscript(raw, people: [hendri]),
                       MemoLinking.linkedTranscript(raw, people: [hendri]))
    }
}
