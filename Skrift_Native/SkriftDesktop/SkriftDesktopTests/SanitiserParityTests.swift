import XCTest

/// A7 — differential parity against the Python backend (the oracle). The expected
/// strings are GOLDENS produced by running the real
/// `backend/services/sanitisation.py:process_sanitisation` on these fixtures with
/// the default linking config (see `pipecheck/gen_sanitise_goldens.py`). They pin
/// the Swift `Sanitiser` to byte-identical behaviour on the tricky cases — guarding
/// the "same results, no Python" promise. Regenerate the goldens if the Python
/// sanitiser changes.
final class SanitiserParityTests: XCTestCase {

    private func nick() -> Person {
        Person(canonical: "[[Nick Jansen]]", aliases: ["Nick"], short: "Nick", lastModifiedAt: "2026-01-01T00:00:00.000Z")
    }
    private func jacks() -> [Person] {
        [Person(canonical: "[[Jack Timmons]]", aliases: ["Jack"], short: "Jack", lastModifiedAt: "2026-01-01T00:00:00.000Z"),
         Person(canonical: "[[Jack de Vries]]", aliases: ["Jack"], short: "Jack", lastModifiedAt: "2026-01-01T00:00:00.000Z")]
    }

    private func assertParity(_ name: String, _ text: String, _ people: [Person],
                              sanitised: String, ambiguous: [String],
                              file: StaticString = #filePath, line: UInt = #line) {
        let r = Sanitiser.process(text: text, people: people)
        XCTAssertEqual(r.sanitised, sanitised, "[\(name)] sanitised text diverges from Python", file: file, line: line)
        XCTAssertEqual(Set(r.ambiguous.map(\.alias)), Set(ambiguous), "[\(name)] ambiguous aliases diverge", file: file, line: line)
    }

    func testParity_firstLinkThenShort() {
        assertParity("first_link_then_short", "Nick and I met today. Nick is great.", [nick()],
                     sanitised: "[[Nick Jansen]] and I met today. Nick is great.", ambiguous: [])
    }
    func testParity_possessivePreserved() {
        assertParity("possessive_preserved", "That is Nick's idea, Nick said.", [nick()],
                     sanitised: "That is [[Nick Jansen]]'s idea, Nick said.", ambiguous: [])
    }
    func testParity_insideLinkSkipped() {
        assertParity("inside_link_skipped", "[[Nick Jansen]] and I talked at length.", [nick()],
                     sanitised: "[[Nick Jansen]] and I talked at length.", ambiguous: [])
    }
    func testParity_twoJacksAmbiguous() {
        assertParity("two_jacks_ambiguous", "Jack and Jack argued about it.", jacks(),
                     sanitised: "Jack and Jack argued about it.", ambiguous: ["jack"])
    }
    func testParity_enNlMix() {
        assertParity("en_nl_mix", "Ik sprak met Nick vandaag. Nick was blij.", [nick()],
                     sanitised: "Ik sprak met [[Nick Jansen]] vandaag. Nick was blij.", ambiguous: [])
    }
    func testParity_noMatch() {
        assertParity("no_match", "Nobody here matches anyone.", [nick()],
                     sanitised: "Nobody here matches anyone.", ambiguous: [])
    }
}
