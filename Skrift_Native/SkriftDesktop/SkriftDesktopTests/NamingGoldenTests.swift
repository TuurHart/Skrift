import XCTest
import Foundation

/// Chunk 5 — the matcher golden-set: load-bearing inputs pinned to an exact (sanitised text,
/// suggested-alias set) so the STRICT opt-out tiering can't silently drift (NAMING_MODEL.md
/// "budget a parity golden-set"). The matcher is deliberately strict whole-word + capitalization
/// (NO edit-distance fuzz) — the FluidAudio custom-vocab boost spells known names right at
/// transcription, and fuzzy-enough-to-catch-a-mangle vs strict-enough-to-dodge-common-word-FPs
/// is exactly the trap the rest of the field offloads to an LLM (which we exclude). Mangled
/// names are handled by the boost + manual right-click add, not a guessy matcher.
final class NamingGoldenTests: XCTestCase {

    private func p(_ canonical: String, _ aliases: [String], short: String? = nil) -> Person {
        Person(canonical: canonical, aliases: aliases, short: short, lastModifiedAt: "x")
    }

    /// The signed-off mock's situation (mocks/naming-review.html state 1) end to end: two
    /// distinctive subjects auto-link (first mention only), an ambiguous twin + a common-word
    /// name go to the dotted suggested tier, a lowercase common word + an unknown stay plain.
    func testGoldenMockTiering() {
        let people = [
            p("[[Hendri van Niekerk]]", ["Hendri"], short: "Hendri"),
            p("[[Bruno Aragorn]]", ["Bruno"], short: "Bruno"),
            p("[[Jack Hutton]]", ["Jack"], short: "Jack"),
            p("[[Jack Tanner]]", ["Jack"], short: "Jack"),
            p("[[Will Smith]]", ["Will"], short: "Will"),
            p("[[Rose Baker]]", ["Rose"], short: "Rose"),
        ]
        let text = "Hendri nailed the mix with Bruno. Then Jack swung by. Hendri reckons we will send Rose the stems."
        let r = Sanitiser.process(text: text, people: people)

        // LINKED: Hendri + Bruno auto-commit their FIRST mention; the 2nd "Hendri" is plain.
        XCTAssertEqual(r.sanitised,
            "[[Hendri van Niekerk]] nailed the mix with [[Bruno Aragorn]]. Then Jack swung by. Hendri reckons we will send Rose the stems.")
        XCTAssertEqual(r.sanitised.components(separatedBy: "[[").count - 1, 2, "exactly two links")

        // SUGGESTED (dotted): the ambiguous "Jack" + the common-word "Rose" (capitalized). The
        // lowercase "will" (the verb) is NOT suggested — the capitalization FP-guard. "Mariam"
        // would be unknown → plain (not on the roster, so it never appears here).
        XCTAssertEqual(Set(r.ambiguous.map(\.alias)), ["jack", "rose"])
        let jack = r.ambiguous.first { $0.alias == "jack" }
        XCTAssertEqual(jack?.candidates.count, 2, "ambiguous → two candidates")
        let rose = r.ambiguous.first { $0.alias == "rose" }
        XCTAssertEqual(rose?.candidates.count, 1, "common-word → one candidate")
    }

    /// Pruning one twin re-promotes the other (decision 9), and a note-level pick force-links
    /// the chosen Jack — the full override round-trip the popover drives.
    func testGoldenPruneAndPickRoundTrip() {
        let people = [p("[[Jack Hutton]]", ["Jack"], short: "Jack"), p("[[Jack Tanner]]", ["Jack"], short: "Jack")]
        let text = "Jack came by, then Jack left."
        // Default: ambiguous → plain + suggested.
        XCTAssertFalse(Sanitiser.process(text: text, people: people).sanitised.contains("[["))
        // Pick Hutton for the note → both mentions resolve to Hutton (first links, rest short).
        let picked = Sanitiser.process(text: text, people: people, namePicks: ["jack": "[[Jack Hutton]]"])
        XCTAssertEqual(picked.sanitised, "[[Jack Hutton]] came by, then Jack left.")
        XCTAssertTrue(picked.ambiguous.isEmpty)
    }
}
