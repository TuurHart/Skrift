import XCTest
import Foundation

/// `Sanitiser.nameSpans(inRaw:)` — the phone's RAW-transcript tier derivation. These
/// tests pin its behaviour AND its PARITY with `Sanitiser.process`: the set of people a
/// linked span resolves must equal the set `process` actually links, and the
/// suggested/ambiguous spans must match `process`'s `ambiguous` occurrences (same
/// aliases + candidate counts). That parity is what guarantees the phone's tiers agree
/// with what the export / the Mac would link.
final class NameSpansTests: XCTestCase {

    private func person(_ canonical: String, _ aliases: [String], short: String? = nil) -> Person {
        Person(canonical: canonical, aliases: aliases, short: short, lastModifiedAt: "2026-01-01T00:00:00.000Z")
    }

    private func sub(_ text: String, _ r: NSRange) -> String { (text as NSString).substring(with: r) }

    /// Canonical keys (lowercased, bare) of every `[[link]]` `process` wrote.
    private func linkedKeys(processed: String) -> Set<String> {
        Set(Sanitiser.linkOccurrences(in: processed).map {
            Sanitiser.linkTarget($0.core).lowercased()
        })
    }

    /// Canonical keys of every LINKED span.
    private func linkedKeys(spans: [NameSpan]) -> Set<String> {
        Set(spans.filter { $0.tier == .linked }.compactMap {
            $0.canonical.map { NamesMerge.keyName($0).lowercased() }
        })
    }

    // MARK: parity — the linked set + the suggested/ambiguous multiset match `process`

    private func assertParity(_ text: String, _ people: [Person],
                              neverLink: Set<String> = [], namePicks: [String: String] = [:],
                              file: StaticString = #filePath, line: UInt = #line) {
        let p = Sanitiser.process(text: text, people: people, neverLink: neverLink, namePicks: namePicks)
        let spans = Sanitiser.nameSpans(inRaw: text, people: people, neverLink: neverLink, namePicks: namePicks)

        // (1) Linked people match exactly.
        XCTAssertEqual(linkedKeys(spans: spans), linkedKeys(processed: p.sanitised),
                       "linked set drifted from process", file: file, line: line)

        // (2) Suggested/ambiguous spans ⇄ process.ambiguous occurrences, by (alias, candidateCount).
        func bag(_ pairs: [(String, Int)]) -> [String: Int] {
            var b: [String: Int] = [:]
            for (a, c) in pairs { b["\(a.lowercased())#\(c)", default: 0] += 1 }
            return b
        }
        // `.plain` (leftplain) is a phone-only re-tappability affordance for silenced
        // aliases — `process` drops them — so it's excluded from the process-parity bag.
        let processBag = bag(p.ambiguous.map { ($0.alias, $0.candidates.count) })
        let spanBag = bag(spans.filter { $0.tier == .suggested || $0.tier == .ambiguous }
                            .map { ($0.alias, $0.candidates.count) })
        XCTAssertEqual(spanBag, processBag, "suggested/ambiguous spans drifted from process", file: file, line: line)

        // (3) Every span indexes the RAW text (offsets valid, substring = the alias shown).
        let ns = text as NSString
        for s in spans {
            XCTAssertLessThanOrEqual(s.offset + s.length, ns.length, "span out of range", file: file, line: line)
            XCTAssertEqual(sub(text, s.range), s.alias, "span text ≠ alias", file: file, line: line)
        }
    }

    // MARK: the mock fixture (mocks/phone-name-linking.html)

    private var studioPeople: [Person] {
        [
            person("[[Jack Hutton]]", ["Jack"]),
            person("[[Jack Tanner]]", ["Jack"]),
            person("[[Hendri van Niekerk]]", ["Hendri"], short: "Hendri"),
            person("[[Rose]]", ["Rose"], short: "Rose"),
        ]
    }
    private let studioText = """
        Met up with Jack this morning at the studio and we ran the whole set twice. \
        Hendri wants the commonplace angle up front, so I'll carve out an hour for it tomorrow. \
        Later Rose dropped by with the proofs. Hendri said he'd loop in Marcus from the print shop.
        """

    func testStudioMockTiers() {
        let spans = Sanitiser.nameSpans(inRaw: studioText, people: studioPeople)

        // Jack → AMBIGUOUS (two people), not linked.
        let jack = spans.filter { $0.alias == "Jack" }
        XCTAssertEqual(jack.count, 1)
        XCTAssertEqual(jack.first?.tier, .ambiguous)
        XCTAssertEqual(jack.first?.candidates.count, 2)
        XCTAssertNil(jack.first?.canonical)

        // Hendri → LINKED, first mention only (two "Hendri"s in the text, one span).
        let hendri = spans.filter { $0.alias == "Hendri" }
        XCTAssertEqual(hendri.count, 1, "first mention only")
        XCTAssertEqual(hendri.first?.tier, .linked)
        XCTAssertEqual(hendri.first?.canonical, "[[Hendri van Niekerk]]")
        // It's the FIRST "Hendri" in the text.
        XCTAssertEqual(hendri.first?.offset, (studioText as NSString).range(of: "Hendri").location)
        XCTAssertEqual(hendri.first?.candidates.count, 1, "uniquely owned → no Change person")

        // Rose → SUGGESTED (FP-prone common word, single candidate).
        let rose = spans.filter { $0.alias == "Rose" }
        XCTAssertEqual(rose.count, 1)
        XCTAssertEqual(rose.first?.tier, .suggested)
        XCTAssertEqual(rose.first?.canonical, "[[Rose]]")

        // Marcus is not on the roster → no span.
        XCTAssertFalse(spans.contains { $0.alias == "Marcus" })

        assertParity(studioText, studioPeople)
    }

    // MARK: focused behaviours

    func testFirstMentionOnlyLinkedRestPlain() {
        let people = [person("[[Nick Jansen]]", ["Nick", "Nicky"], short: "Nick")]
        let text = "Nick went out. Later Nicky came back and Nick stayed."
        let spans = Sanitiser.nameSpans(inRaw: text, people: people)
        let linked = spans.filter { $0.tier == .linked }
        XCTAssertEqual(linked.count, 1, "exactly one linked span for the person")
        XCTAssertEqual(linked.first?.offset, 0)               // first "Nick"
        XCTAssertEqual(linked.first?.alias, "Nick")
        assertParity(text, people)
    }

    func testPossessiveStrippedFromLinkedSpan() {
        let people = [person("[[Nick Jansen]]", ["Nick"], short: "Nick")]
        let text = "Nick's idea was great."
        let spans = Sanitiser.nameSpans(inRaw: text, people: people)
        XCTAssertEqual(spans.count, 1)
        XCTAssertEqual(spans.first?.alias, "Nick", "the 's stays plain, outside the span")
        XCTAssertEqual(spans.first?.range.length, 4)
        assertParity(text, people)
    }

    func testAmbiguousEveryOccurrence() {
        let people = [person("[[Sam Smith]]", ["Sam"]), person("[[Sam Jones]]", ["Sam"])]
        let text = "I saw Sam today, then Sam left."
        let spans = Sanitiser.nameSpans(inRaw: text, people: people)
        XCTAssertEqual(spans.count, 2, "both Sams are ambiguous")
        XCTAssertTrue(spans.allSatisfy { $0.tier == .ambiguous && $0.candidates.count == 2 })
        assertParity(text, people)
    }

    func testForcePickedAmbiguousIsLinkedWithChangeableCandidates() {
        let people = [person("[[Jack Hutton]]", ["Jack"]), person("[[Jack Tanner]]", ["Jack"])]
        let text = "Met Jack today."
        let spans = Sanitiser.nameSpans(inRaw: text, people: people,
                                        namePicks: ["jack": "[[Jack Hutton]]"])
        XCTAssertEqual(spans.count, 1)
        XCTAssertEqual(spans.first?.tier, .linked)
        XCTAssertEqual(spans.first?.canonical, "[[Jack Hutton]]")
        XCTAssertEqual(spans.first?.candidates.count, 2, "still 2 sharers → UI offers Change person")
        assertParity(text, people, namePicks: ["jack": "[[Jack Hutton]]"])
    }

    func testNeverLinkKeepsNameAsSuggestion() {
        // A distinctive name kept plain (the "keep as plain text" / unlink choice) stays a
        // re-promotable dotted suggestion, not a link.
        let people = [person("[[Hendri van Niekerk]]", ["Hendri"], short: "Hendri")]
        let text = "Hendri came by twice; Hendri again later."
        let spans = Sanitiser.nameSpans(inRaw: text, people: people,
                                        neverLink: ["[[Hendri van Niekerk]]"])
        XCTAssertFalse(spans.contains { $0.tier == .linked }, "pruned → not linked")
        XCTAssertTrue(spans.contains { $0.tier == .suggested && $0.alias == "Hendri" })
        assertParity(text, people, neverLink: ["[[Hendri van Niekerk]]"])
    }

    func testSilencedAliasIsKeptPlainAndReTappable() {
        // An empty namePick silences the alias → not linked / not suggested, but the
        // name of a live person stays a re-tappable PLAIN (leftplain) span.
        let people = [person("[[Rose]]", ["Rose"], short: "Rose")]
        let text = "Rose stopped by, then Rose left."
        let spans = Sanitiser.nameSpans(inRaw: text, people: people, namePicks: ["rose": ""])
        XCTAssertEqual(spans.count, 2, "both Roses stay re-tappable")
        XCTAssertTrue(spans.allSatisfy { $0.tier == .plain && $0.alias == "Rose" })
        XCTAssertNil(spans.first?.canonical)
        XCTAssertEqual(spans.first?.candidates.count, 1, "re-link offers the owning person")
        // No linked/suggested/ambiguous → process parity (it drops silenced aliases).
        assertParity(text, people, namePicks: ["rose": ""])
    }

    func testSilencedAliasWithNoLivePersonHasNoSpan() {
        // A silence for an alias no live person owns produces nothing (nothing to re-link).
        let spans = Sanitiser.nameSpans(inRaw: "Ghost was here.", people: [person("[[Rose]]", ["Rose"])],
                                        namePicks: ["ghost": ""])
        XCTAssertTrue(spans.isEmpty)
    }

    func testEmptyAndNoPeople() {
        XCTAssertTrue(Sanitiser.nameSpans(inRaw: "", people: studioPeople).isEmpty)
        XCTAssertTrue(Sanitiser.nameSpans(inRaw: "Nobody here.", people: []).isEmpty)
    }
}
