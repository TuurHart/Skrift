import XCTest
import Foundation

final class SanitiserTests: XCTestCase {

    private func person(_ canonical: String, _ aliases: [String], short: String? = nil) -> Person {
        Person(canonical: canonical, aliases: aliases, short: short, lastModifiedAt: "2026-01-01T00:00:00.000Z")
    }

    func testUnambiguousFirstLinksRestShortened() {
        let people = [person("[[Nick Jansen]]", ["Nick", "Nicky"], short: "Nick")]
        let r = Sanitiser.process(text: "Nick went out. Later Nicky came back.", people: people)
        XCTAssertEqual(r.sanitised, "[[Nick Jansen]] went out. Later Nick came back.")
        XCTAssertTrue(r.ambiguous.isEmpty)
        // exactly one link
        XCTAssertEqual(r.sanitised.components(separatedBy: "[[Nick Jansen]]").count - 1, 1)
    }

    func testAmbiguousAliasRecordedNotLinked() {
        let people = [
            person("[[Sam Smith]]", ["Sam"]),
            person("[[Sam Jones]]", ["Sam"]),
        ]
        let r = Sanitiser.process(text: "I saw Sam today.", people: people)
        XCTAssertEqual(r.sanitised, "I saw Sam today.")      // left plain
        XCTAssertEqual(r.ambiguous.count, 1)
        XCTAssertEqual(r.ambiguous.first?.alias, "sam")
        XCTAssertEqual(r.ambiguous.first?.candidates.count, 2)
    }

    func testInsideExistingLinkIsSkipped() {
        let people = [person("[[Nick Jansen]]", ["Nick"], short: "Nick")]
        let r = Sanitiser.process(text: "[[Nick Jansen]] is here.", people: people)
        XCTAssertEqual(r.sanitised, "[[Nick Jansen]] is here.")   // no double-link
    }

    func testPossessivePreserved() {
        let people = [person("[[Nick Jansen]]", ["Nick"], short: "Nick")]
        let r = Sanitiser.process(text: "Nick's idea was great.", people: people)
        XCTAssertEqual(r.sanitised, "[[Nick Jansen]]'s idea was great.")
    }

    func testApplyResolvedNames() {
        let out = Sanitiser.applyResolvedNames(
            text: "I saw Sam today, then Sam left.",
            decisions: [(alias: "Sam", canonical: "[[Sam Smith]]", short: "Sam")]
        )
        XCTAssertEqual(out, "I saw [[Sam Smith]] today, then Sam left.")
    }

    func testApplyResolvedOccurrencesTwoJacks() {
        // Four "Jack" mentions → two distinct people. First mention of each canonical
        // links; later mentions of that same canonical use the short name.
        let out = Sanitiser.applyResolvedOccurrences(
            text: "Met Jack, then Jack again. Later Jack and finally Jack.",
            byAlias: ["Jack": [
                (canonical: "[[Jack Hutton]]", short: "Jack"),
                (canonical: "[[Jack Hutton]]", short: "Jack"),
                (canonical: "[[Jack Timmons]]", short: "Jack"),
                (canonical: "[[Jack Timmons]]", short: "Jack"),
            ]]
        )
        XCTAssertEqual(out, "Met [[Jack Hutton]], then Jack again. Later [[Jack Timmons]] and finally Jack.")
    }

    func testApplyResolvedOccurrencesLeavePlain() {
        let out = Sanitiser.applyResolvedOccurrences(
            text: "Jack and Jack.",
            byAlias: ["Jack": [(canonical: "[[Jack Hutton]]", short: "Jack"), (canonical: nil, short: nil)]]
        )
        XCTAssertEqual(out, "[[Jack Hutton]] and Jack.")
    }

    // MARK: plainOccurrences (drives the inline resolver UI)

    func testPlainOccurrencesInOrderSkippingLinks() {
        // Two plain "Jack"s + one already inside a link → the link one is skipped, and
        // the two plain ones come back in reading order.
        let text = "Met Jack, then [[Jack Timmons]], and later Jack again."
        let ns = text as NSString
        let occ = Sanitiser.plainOccurrences(of: "Jack", in: text)
        XCTAssertEqual(occ.count, 2)
        XCTAssertEqual(ns.substring(with: occ[0]), "Jack")
        // First plain "Jack" precedes the link; second follows it.
        XCTAssertLessThan(occ[0].location, (text as NSString).range(of: "[[Jack Timmons]]").location)
        XCTAssertGreaterThan(occ[1].location, (text as NSString).range(of: "[[Jack Timmons]]").location)
    }

    func testPlainOccurrenceIndicesAlignWithApply() {
        // The crux of the inline-resolver contract: the i-th plainOccurrence is the
        // i-th occurrence applyResolvedOccurrences acts on. Resolve only index 1 and
        // confirm exactly that mention changed.
        let text = "Jack, Jack, Jack."
        let occ = Sanitiser.plainOccurrences(of: "Jack", in: text)
        XCTAssertEqual(occ.count, 3)
        let out = Sanitiser.applyResolvedOccurrences(
            text: text,
            byAlias: ["Jack": [
                (canonical: nil, short: nil),
                (canonical: "[[Jack Timmons]]", short: "Jack"),
                (canonical: nil, short: nil),
            ]]
        )
        XCTAssertEqual(out, "Jack, [[Jack Timmons]], Jack.")
    }

    func testPlainOccurrencesPossessiveRangeIncludesApostropheS() {
        let text = "Jack's car."
        let ns = text as NSString
        let occ = Sanitiser.plainOccurrences(of: "Jack", in: text)
        XCTAssertEqual(occ.count, 1)
        XCTAssertEqual(ns.substring(with: occ[0]), "Jack's")
    }

    /// End-to-end of what R3's inline resolver produces: the user clicks each mention;
    /// on commit we enumerate `plainOccurrences` in order to build the per-occurrence
    /// arrays (mirrors `NoteDisplayView.maybeCompleteAlias` — `InlineResolverModel`
    /// keys choices by that occurrence INDEX; this test keys by location and converts,
    /// proving the location↔order mapping is stable). Two friends named "Jack" must
    /// resolve to DIFFERENT people, "Sam" to its own.
    func testInlineResolverLocationKeyedApplyTwoDistinctJacks() {
        let body = "Met Jack at the studio. Later Jack texted. And Sam will test it next week."
        let jackLocs = Sanitiser.plainOccurrences(of: "Jack", in: body).map(\.location)
        let samLocs = Sanitiser.plainOccurrences(of: "Sam", in: body).map(\.location)
        XCTAssertEqual(jackLocs.count, 2)
        XCTAssertEqual(samLocs.count, 1)

        // Per-occurrence choices keyed by where the mention sits in the body.
        let choices: [Int: (canonical: String?, short: String?)] = [
            jackLocs[0]: ("[[Jack Timmons]]", "Jack"),
            jackLocs[1]: ("[[Jack de Vries]]", "Jack"),
            samLocs[0]: ("[[Sam Jones]]", "Sam"),
        ]
        func ordered(_ alias: String) -> [(canonical: String?, short: String?)] {
            Sanitiser.plainOccurrences(of: alias, in: body).map { choices[$0.location] ?? (nil, nil) }
        }
        let out = Sanitiser.applyResolvedOccurrences(
            text: body, byAlias: ["Jack": ordered("Jack"), "Sam": ordered("Sam")])
        XCTAssertEqual(out, "Met [[Jack Timmons]] at the studio. Later [[Jack de Vries]] texted. And [[Sam Jones]] will test it next week.")
    }

    /// One Jack resolved, one deliberately left plain (the inline "Leave as plain text"
    /// choice = absent/nil decision) — only the resolved mention links.
    func testInlineResolverLeaveOneJackPlain() {
        let body = "Met Jack, later Jack."
        let locs = Sanitiser.plainOccurrences(of: "Jack", in: body).map(\.location)
        let choices: [Int: (canonical: String?, short: String?)] = [
            locs[1]: ("[[Jack Timmons]]", "Jack"),   // only the 2nd is identified
        ]
        let ordered = Sanitiser.plainOccurrences(of: "Jack", in: body).map { choices[$0.location] ?? (nil, nil) }
        let out = Sanitiser.applyResolvedOccurrences(text: body, byAlias: ["Jack": ordered])
        XCTAssertEqual(out, "Met Jack, later [[Jack Timmons]].")
    }

    // MARK: First-mention-only when the input ALREADY carries links (the 2026-06-10
    // "brackets on every mention" bug — Mac-diarized conversations arrive with
    // `**[[Person]]:**` on EVERY turn header)

    func testConversationTurnHeadersKeepOnlyFirstLink() {
        let people = [person("[[Nick Jansen]]", ["Nicky"], short: "Nick")]
        let text = """
        **[[Nick Jansen]]:** hello there

        **Speaker 2:** hi Nicky

        **[[Nick Jansen]]:** how are you
        """
        let r = Sanitiser.process(text: text, people: people)
        XCTAssertEqual(r.sanitised, """
        **[[Nick Jansen]]:** hello there

        **Speaker 2:** hi Nick

        **Nick:** how are you
        """)
        // Exactly ONE link survives.
        XCTAssertEqual(r.sanitised.components(separatedBy: "[[Nick Jansen]]").count - 1, 1)
    }

    func testExistingLinkSuppressesSecondLink() {
        // The body already introduces the person — a later plain alias becomes the
        // short name, NOT another [[link]].
        let people = [person("[[Nick Jansen]]", ["Nicky"], short: "Nick")]
        let r = Sanitiser.process(text: "[[Nick Jansen]] is here. Nicky waves.", people: people)
        XCTAssertEqual(r.sanitised, "[[Nick Jansen]] is here. Nick waves.")
    }

    func testRepeatedNonPersonLinksUntouched() {
        // Repeated links that aren't people (image markers, place links) never demote.
        let people = [person("[[Nick Jansen]]", ["Nicky"], short: "Nick")]
        let text = "[[img_001]] then [[img_001]] at [[Hotel Du Vin]] and [[Hotel Du Vin]]."
        XCTAssertEqual(Sanitiser.process(text: text, people: people).sanitised, text)
    }

    func testApplyResolvedNamesRespectsExistingLink() {
        // Resolving an ambiguous alias to a person the body ALREADY links → every
        // plain mention is a later mention (short name), no second link.
        let out = Sanitiser.applyResolvedNames(
            text: "I saw Sam today. [[Sam Smith]] left early.",
            decisions: [(alias: "Sam", canonical: "[[Sam Smith]]", short: "Sammy")]
        )
        XCTAssertEqual(out, "I saw Sammy today. [[Sam Smith]] left early.")
    }

    func testApplyResolvedOccurrencesSeededByExistingLink() {
        // A turn header already links the person — the per-occurrence apply must not
        // introduce a second link for the in-text mention.
        let out = Sanitiser.applyResolvedOccurrences(
            text: "**[[Jack Hutton]]:** hi\n\nMet Jack later.",
            byAlias: ["Jack": [(canonical: "[[Jack Hutton]]", short: "Jack")]]
        )
        XCTAssertEqual(out, "**[[Jack Hutton]]:** hi\n\nMet Jack later.")
        XCTAssertEqual(out.components(separatedBy: "[[Jack Hutton]]").count - 1, 1)
    }

    // MARK: Opt-out + risk-tiering (NAMING_MODEL.md decision 4) — known people auto-link
    // by DEFAULT (first mention); FP-prone (common-word / too-short) and ambiguous names
    // are downgraded to dotted SUGGESTIONS (carried in `Result.ambiguous`, commit on click).

    func testOptOutLinksAllDistinctiveByDefault() {
        // No gate — every distinctive known person auto-links their first mention.
        let people = [
            person("[[Nick Jansen]]", ["Nick"], short: "Nick"),
            person("[[Bruno Aragorn]]", ["Bruno"], short: "Bruno"),
        ]
        let r = Sanitiser.process(text: "Nick met Bruno today.", people: people)
        XCTAssertEqual(r.sanitised, "[[Nick Jansen]] met [[Bruno Aragorn]] today.")
        XCTAssertTrue(r.ambiguous.isEmpty)
    }

    func testCommonWordNameSuggestedNotAutoLinked() {
        // A first name that's also a common word ("Will") never auto-writes a link — it's
        // recorded as a single-candidate suggestion (dotted, commit on click).
        let people = [person("[[Will Smith]]", ["Will"], short: "Will")]
        let r = Sanitiser.process(text: "Will called me back.", people: people)
        XCTAssertEqual(r.sanitised, "Will called me back.", "common-word name stays plain text")
        XCTAssertEqual(r.ambiguous.count, 1, "recorded as a suggestion")
        XCTAssertEqual(r.ambiguous.first?.alias, "will")
        XCTAssertEqual(r.ambiguous.first?.candidates.count, 1, "single candidate (not ambiguous)")
    }

    func testCommonWordLowercaseStaysPlainNoSuggestion() {
        // The capitalization FP-guard: a lowercase "will" (the verb) is neither linked nor
        // suggested — defuses "I will call" while a capitalized "Will" still surfaces.
        let people = [person("[[Will Smith]]", ["Will"], short: "Will")]
        let r = Sanitiser.process(text: "I will call you tomorrow.", people: people)
        XCTAssertEqual(r.sanitised, "I will call you tomorrow.")
        XCTAssertTrue(r.ambiguous.isEmpty, "lowercase common word → not even suggested")
    }

    func testFullNameAutoCommitsEvenWhenFirstNameIsCommon() {
        // A multi-token full name is distinctive → auto-commits, even though the bare first
        // name ("Will") is FP-prone. The later bare "Will" demotes to the short.
        let people = [person("[[Will Smith]]", ["Will Smith", "Will"], short: "Will")]
        let r = Sanitiser.process(text: "Will Smith arrived. Will spoke first.", people: people)
        XCTAssertEqual(r.sanitised, "[[Will Smith]] arrived. Will spoke first.")
        XCTAssertTrue(r.ambiguous.isEmpty, "the person is linked → no suggestion")
    }

    func testTooShortSingleNameSuggestedNotLinked() {
        // A ≤2-char single token collides too easily to auto-write → suggested instead.
        let people = [person("[[Bo Jansen]]", ["Bo"], short: "Bo")]
        let r = Sanitiser.process(text: "Bo dropped by earlier.", people: people)
        XCTAssertEqual(r.sanitised, "Bo dropped by earlier.", "too-short name stays plain")
        XCTAssertEqual(r.ambiguous.count, 1)
        XCTAssertEqual(r.ambiguous.first?.candidates.count, 1)
    }

    // MARK: Non-prose skip (build-guard) — a name inside a verbatim audiobook-quote span
    // is NOT "about" that roster person, so it's never linked.

    func testNameInsideAudiobookQuoteIsNotLinked() {
        let people = [person("[[Bruno Aragorn]]", ["Bruno"], short: "Bruno")]
        let body = "> Bruno walked into the room.\n\nBruno is my closest friend."
        let r = Sanitiser.process(text: body, people: people)
        // The quote's "Bruno" stays plain; the ramble's "Bruno" is the (first) link.
        XCTAssertEqual(r.sanitised, "> Bruno walked into the room.\n\n[[Bruno Aragorn]] is my closest friend.")
        XCTAssertEqual(r.sanitised.components(separatedBy: "[[Bruno Aragorn]]").count - 1, 1)
    }

    // MARK: Conversation — opt-out + risk-tiering (FIRST-ONLY per person)

    func testConversationInlineFirstOnlyOptOut() {
        // A distinctive non-speaker mentioned twice inline auto-links by default: only the
        // FIRST mention links; the second demotes to the short ("one note, one link").
        let bruno = person("[[Bruno Aragorn]]", ["Bruno"], short: "Bruno")
        let input = "**Speaker 1:** I saw Bruno today\n\n**Speaker 2:** Bruno again?"
        let s = Sanitiser.processConversation(text: input, people: [bruno]).sanitised
        XCTAssertEqual(s, "**Speaker 1:** I saw [[Bruno Aragorn|Bruno]] today\n\n**Speaker 2:** Bruno again?")
        XCTAssertEqual(s.components(separatedBy: "[[").count - 1, 1, "exactly one inline link")
    }

    func testConversationSpeakerAndInlineBothAutoLink() {
        // The matched SPEAKER links in their header; a distinctive inline mention auto-links too.
        let tiuri = person("[[Tiuri Hartog]]", ["Tiuri Hartog", "Tuur"], short: "Tuur")
        let bruno = person("[[Bruno Aragorn]]", ["Bruno"], short: "Bruno")
        let input = "**Tiuri Hartog:** I saw Bruno today\n\n**Speaker 2:** cool"
        let s = Sanitiser.processConversation(text: input, people: [tiuri, bruno]).sanitised
        XCTAssertEqual(s, "**[[Tiuri Hartog]]:** I saw [[Bruno Aragorn|Bruno]] today\n\n**Speaker 2:** cool")
    }

    func testConversationTwoSameAliasStaysAmbiguous() {
        // Two people share "Jack" → ambiguous → never auto-linked; every occurrence is
        // recorded as a suggestion for the click-popover.
        let jackH = person("[[Jack Hutton]]", ["Jack"], short: "Jack")
        let jackT = person("[[Jack Timmons]]", ["Jack"], short: "Jack")
        let input = "**Speaker 1:** I saw Jack today\n\n**Speaker 2:** which Jack"
        let r = Sanitiser.processConversation(text: input, people: [jackH, jackT])
        XCTAssertFalse(r.sanitised.contains("[["), "ambiguous → plain; got: \(r.sanitised)")
        XCTAssertEqual(r.ambiguous.count, 2, "both occurrences recorded")
        XCTAssertEqual(r.ambiguous.first?.candidates.count, 2)
    }

    // MARK: Chip-bar detection helpers (detectedPeople / matchedSpeakers)

    func testDetectedPeopleInReadingOrderExcludesUnmentioned() {
        let people = [
            person("[[Bruno Aragorn]]", ["Bruno"], short: "Bruno"),
            person("[[Hendri Van Niekerk]]", ["Hendri", "Henry"], short: "Hendri"),
            person("[[Nobody Here]]", ["Zztop"]),
        ]
        let detected = Sanitiser.detectedPeople(in: "Henry met Bruno today.", people: people)
        // Reading order (Henry before Bruno); the unmentioned person is excluded.
        XCTAssertEqual(detected.map(\.canonical), ["[[Hendri Van Niekerk]]", "[[Bruno Aragorn]]"])
    }

    func testMatchedSpeakersResolvesTurnSpeakersOnly() {
        let tiuri = person("[[Tiuri Hartog]]", ["Tiuri Hartog", "Tuur"], short: "Tuur")
        let bruno = person("[[Bruno Aragorn]]", ["Bruno"], short: "Bruno")
        let input = "**Tiuri Hartog:** hi Bruno\n\n**Speaker 2:** hey"
        // Tiuri is a turn speaker → matched; Bruno is only mentioned inline; Speaker 2 unmatched.
        XCTAssertEqual(Sanitiser.matchedSpeakers(in: input, people: [tiuri, bruno]), ["tiuri hartog"])
    }

    func testMatchedSpeakersEmptyForMonologue() {
        let tiuri = person("[[Tiuri Hartog]]", ["Tuur"], short: "Tuur")
        XCTAssertTrue(Sanitiser.matchedSpeakers(in: "Just Tuur talking.", people: [tiuri]).isEmpty)
    }
}
