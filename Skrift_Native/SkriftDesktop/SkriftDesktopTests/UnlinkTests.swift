import XCTest
import Foundation

/// Unlink a `[[Name]]` (mocks/name-unlink.html): the text transformations behind
/// the review body's linked-mention popover — one mention → the plain alias as
/// spoken (possessive kept), all mentions in this note, and the persisted
/// no-relink-on-reprocess behavior (`Sanitiser.process(neverLink:)`).
final class UnlinkTests: XCTestCase {

    private func person(_ canonical: String, _ aliases: [String], short: String? = nil) -> Person {
        Person(canonical: canonical, aliases: aliases, short: short, lastModifiedAt: "2026-01-01T00:00:00.000Z")
    }

    // MARK: - linkOccurrences (the clickable linked mentions)

    func testLinkOccurrencesInReadingOrderSkippingImageMarkers() {
        let text = "[[Nick Jansen]] sent [[img_001]] to [[Sam Jones]] at [[Hotel Du Vin]]."
        let links = Sanitiser.linkOccurrences(in: text)
        XCTAssertEqual(links.map(\.core), ["Nick Jansen", "Sam Jones", "Hotel Du Vin"])
        let ns = text as NSString
        XCTAssertEqual(ns.substring(with: links[0].range), "[[Nick Jansen]]")
        XCTAssertLessThan(links[0].range.location, links[1].range.location)
    }

    func testLinkOccurrencesOfOnePersonMatchesCaseInsensitiveAndBrackets() {
        let text = "[[Nick Jansen]] then [[nick jansen]] then [[Sam Jones]]."
        XCTAssertEqual(Sanitiser.linkOccurrences(of: "Nick Jansen", in: text).count, 2)
        // Bracketed canonical (as stored in the names DB) resolves the same.
        XCTAssertEqual(Sanitiser.linkOccurrences(of: "[[Nick Jansen]]", in: text).count, 2)
        XCTAssertEqual(Sanitiser.linkOccurrences(of: "Sam Jones", in: text).count, 1)
        XCTAssertTrue(Sanitiser.linkOccurrences(of: "", in: text).isEmpty)
    }

    // MARK: - Unlink ONE mention → the alias as spoken

    func testUnlinkMentionBecomesPlainAliasAsSpoken() {
        let text = "Talking with [[Nick Jansen]] this morning about the rewrite."
        let out = Sanitiser.unlinkOccurrence(text: text, canonical: "Nick Jansen", index: 0, alias: "Nick")
        XCTAssertEqual(out, "Talking with Nick this morning about the rewrite.")
    }

    func testUnlinkMentionPreservesPossessive() {
        // The Sanitiser writes the possessive OUTSIDE the brackets — unlinking the
        // bracket range must keep it: [[Nick Jansen]]'s → Nick's (straight + curly).
        XCTAssertEqual(
            Sanitiser.unlinkOccurrence(text: "[[Nick Jansen]]'s point stood.", canonical: "Nick Jansen", index: 0, alias: "Nick"),
            "Nick's point stood.")
        XCTAssertEqual(
            Sanitiser.unlinkOccurrence(text: "[[Nick Jansen]]’s point stood.", canonical: "Nick Jansen", index: 0, alias: "Nick"),
            "Nick’s point stood.")
    }

    func testUnlinkMentionIsOrderBasedAndTargetsOnlyThatLink() {
        // Two links of the same person (e.g. hand-added) — index 1 unlinks ONLY the
        // second, the order-based contract the UI relies on.
        let text = "[[Nick Jansen]] opened. Later [[Nick Jansen]] closed."
        let out = Sanitiser.unlinkOccurrence(text: text, canonical: "Nick Jansen", index: 1, alias: "Nick")
        XCTAssertEqual(out, "[[Nick Jansen]] opened. Later Nick closed.")
    }

    func testUnlinkMentionOutOfRangeIndexLeavesTextUnchanged() {
        let text = "[[Nick Jansen]] is here."
        XCTAssertEqual(Sanitiser.unlinkOccurrence(text: text, canonical: "Nick Jansen", index: 5, alias: "Nick"), text)
        XCTAssertEqual(Sanitiser.unlinkOccurrence(text: text, canonical: "Nick Jansen", index: -1, alias: "Nick"), text)
        XCTAssertEqual(Sanitiser.unlinkOccurrence(text: text, canonical: "Sam Jones", index: 0, alias: "Sam"), text)
    }

    func testUnlinkMentionLeavesOtherPeopleAndPlainMentionsAlone() {
        let text = "Met [[Nick Jansen]] and [[Sam Jones]]. Nick waved."
        let out = Sanitiser.unlinkOccurrence(text: text, canonical: "Nick Jansen", index: 0, alias: "Nick")
        XCTAssertEqual(out, "Met Nick and [[Sam Jones]]. Nick waved.")
    }

    // MARK: - Unlink ALL mentions in this note

    func testUnlinkAllReplacesEveryLinkOfThatPersonOnly() {
        let text = "**[[Nick Jansen]]:** hi\n\n[[Sam Jones]] joined. [[Nick Jansen]]'s build is green."
        let out = Sanitiser.unlinkAll(text: text, canonical: "Nick Jansen", alias: "Nick")
        XCTAssertEqual(out, "**Nick:** hi\n\n[[Sam Jones]] joined. Nick's build is green.")
    }

    func testUnlinkAllWithNoLinksIsANoOp() {
        let text = "Nick was already plain. [[img_002]] stays."
        XCTAssertEqual(Sanitiser.unlinkAll(text: text, canonical: "Nick Jansen", alias: "Nick"), text)
    }

    // MARK: - spokenAlias (what the unlinked mention reads as)

    func testSpokenAliasShortOverrideThenFirstWordThenCanonical() {
        XCTAssertEqual(Sanitiser.spokenAlias(for: person("[[Nick Jansen]]", ["Nicky"], short: "Nick")), "Nick")
        XCTAssertEqual(Sanitiser.spokenAlias(for: person("[[Nick Jansen]]", ["Nicky"])), "Nick")   // first word
        XCTAssertEqual(Sanitiser.spokenAlias(for: person("[[Cher]]", [])), "Cher")
    }

    // MARK: - neverLink (PRUNE): re-processing must NOT auto-RE-LINK an unlinked person,
    // but the OPT-OUT model keeps them a dotted, re-promotable SUGGESTION
    // (mocks/naming-review.html state 3: "the unlinked name stays a dotted suggestion").

    func testProcessNeverLinkSkipsLinkingAndDemotionButSuggests() {
        let people = [person("[[Nick Jansen]]", ["Nick", "Nicky"], short: "Nick")]
        let raw = "Nick went out. Later Nicky came back."
        // Sanity: without neverLink the person links as usual.
        XCTAssertEqual(Sanitiser.process(text: raw, people: people).sanitised,
                       "[[Nick Jansen]] went out. Later Nick came back.")
        // Pruned: the body stays exactly as spoken — no link, no Nicky→Nick demotion …
        let r = Sanitiser.process(text: raw, people: people, neverLink: ["Nick Jansen"])
        XCTAssertEqual(r.sanitised, raw)
        // … but the mentions are recorded as dotted suggestions (re-promotable), one per
        // matched alias occurrence (Nick + Nicky), all pointing at the single candidate.
        XCTAssertFalse(r.ambiguous.isEmpty, "pruned name stays a dotted suggestion")
        XCTAssertTrue(r.ambiguous.allSatisfy { $0.candidates.map(\.canonical) == ["[[Nick Jansen]]"] })
    }

    func testProcessNeverLinkAcceptsBracketedKeyAndAnyCase() {
        let people = [person("[[Nick Jansen]]", ["Nick"], short: "Nick")]
        let raw = "Nick is here."
        XCTAssertEqual(Sanitiser.process(text: raw, people: people, neverLink: ["[[Nick Jansen]]"]).sanitised, raw)
        XCTAssertEqual(Sanitiser.process(text: raw, people: people, neverLink: ["nick jansen"]).sanitised, raw)
    }

    func testProcessNeverLinkOnlyAffectsThatPerson() {
        let people = [
            person("[[Nick Jansen]]", ["Nick"], short: "Nick"),
            person("[[Sam Jones]]", ["Sam"], short: "Sam"),
        ]
        let r = Sanitiser.process(text: "Nick and Sam talked.", people: people, neverLink: ["Nick Jansen"])
        XCTAssertEqual(r.sanitised, "Nick and [[Sam Jones]] talked.")
    }

    func testProcessNeverLinkPersonDropsOutOfAmbiguity() {
        // Documents the chosen semantics: the excluded person is absent from the
        // names DB FOR THIS NOTE — a previously two-way "Jack" becomes unambiguous
        // and links to the remaining Jack.
        let people = [
            person("[[Jack Hutton]]", ["Jack"], short: "Jack"),
            person("[[Jack Timmons]]", ["Jack"], short: "Jack"),
        ]
        XCTAssertEqual(Sanitiser.process(text: "Met Jack today.", people: people).ambiguous.count, 1)
        let r = Sanitiser.process(text: "Met Jack today.", people: people, neverLink: ["Jack Hutton"])
        XCTAssertTrue(r.ambiguous.isEmpty)
        XCTAssertEqual(r.sanitised, "Met [[Jack Timmons]] today.")
    }

    /// The full round-trip the feature promises: sanitise → "Unlink all mentions in
    /// this note" → re-process (retranscribe/redo path feeds the persisted choice
    /// back as `neverLink`) → the person stays plain, others keep linking.
    func testUnlinkAllThenReprocessDoesNotRelink() {
        let people = [
            person("[[Nick Jansen]]", ["Nick"], short: "Nick"),
            person("[[Sam Jones]]", ["Sam"], short: "Sam"),
        ]
        let raw = "Talking with Nick this morning. Nick's point was good. Sam will test it."
        let first = Sanitiser.process(text: raw, people: people).sanitised
        XCTAssertEqual(first, "Talking with [[Nick Jansen]] this morning. Nick's point was good. [[Sam Jones]] will test it.")

        // The popover's "Unlink all mentions in this note".
        let unlinked = Sanitiser.unlinkAll(text: first, canonical: "Nick Jansen", alias: "Nick")
        XCTAssertEqual(unlinked, "Talking with Nick this morning. Nick's point was good. [[Sam Jones]] will test it.")

        // Re-process from the raw transcript (e.g. re-transcribe) with the choice
        // persisted on the PipelineFile → Nick stays exactly as spoken.
        let again = Sanitiser.process(text: raw, people: people, neverLink: ["Nick Jansen"]).sanitised
        XCTAssertEqual(again, unlinked)

        // Re-sanitising the unlinked body itself must be stable too.
        XCTAssertEqual(Sanitiser.process(text: unlinked, people: people, neverLink: ["Nick Jansen"]).sanitised, unlinked)
    }

    // MARK: - Change to → <other person> (wrong-person fix)

    func testRelinkOccurrenceSwapsOnlyThatMention() {
        let text = "Met [[Jack Timmons]] today. Later [[Jack Timmons]] called again."
        let out = Sanitiser.relinkOccurrence(text: text, canonical: "Jack Timmons",
                                             index: 1, newCanonical: "Jack Hutton")
        XCTAssertEqual(out, "Met [[Jack Timmons]] today. Later [[Jack Hutton]] called again.")
    }

    func testRelinkOccurrenceOutOfRangeIsUnchanged() {
        let text = "Met [[Jack Timmons]] today."
        XCTAssertEqual(Sanitiser.relinkOccurrence(text: text, canonical: "Jack Timmons",
                                                  index: 3, newCanonical: "Jack Hutton"), text)
    }

    func testRelinkOccurrencePreservesPossessiveOutsideBrackets() {
        let text = "That was [[Jack Timmons]]'s idea."
        let out = Sanitiser.relinkOccurrence(text: text, canonical: "Jack Timmons",
                                             index: 0, newCanonical: "Jack Hutton")
        XCTAssertEqual(out, "That was [[Jack Hutton]]'s idea.")
    }
}
