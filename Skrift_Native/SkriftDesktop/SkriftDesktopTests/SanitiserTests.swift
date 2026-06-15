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

    // MARK: Opt-in naming gate (mocks/opt-in-naming.html) — link ONLY the people the note
    // is marked ABOUT; everyone else stays plain. `aboutPeople: nil` = ungated (link all).

    func testOptInLinksOnlyAboutPeople() {
        let people = [
            person("[[Nick Jansen]]", ["Nick"], short: "Nick"),
            person("[[Sam Roe]]", ["Sam"], short: "Sam"),
        ]
        let r = Sanitiser.process(text: "Nick met Sam today.", people: people,
                                  aboutPeople: ["[[Nick Jansen]]"])
        // Only Nick (the about-person) links; Sam stays plain text.
        XCTAssertEqual(r.sanitised, "[[Nick Jansen]] met Sam today.")
        XCTAssertTrue(r.ambiguous.isEmpty)
    }

    func testOptInEmptySetLinksNobody() {
        let people = [
            person("[[Nick Jansen]]", ["Nick"], short: "Nick"),
            person("[[Sam Roe]]", ["Sam"], short: "Sam"),
        ]
        let r = Sanitiser.process(text: "Nick met Sam today.", people: people, aboutPeople: [])
        XCTAssertEqual(r.sanitised, "Nick met Sam today.", "empty aboutPeople → nobody linked")
        XCTAssertTrue(r.ambiguous.isEmpty, "no ambiguity recorded for a note about nobody")
    }

    func testOptInNilGateLinksAll() {
        // nil = ungated (the matching engine's raw behavior) — both people link.
        let people = [
            person("[[Nick Jansen]]", ["Nick"], short: "Nick"),
            person("[[Sam Roe]]", ["Sam"], short: "Sam"),
        ]
        let r = Sanitiser.process(text: "Nick met Sam today.", people: people)
        XCTAssertEqual(r.sanitised, "[[Nick Jansen]] met [[Sam Roe]] today.")
    }

    func testOptInTappingOneOfTwoSameAliasLinksIt() {
        // Two people share the alias "Sam". Marking the note about ONE of them makes that
        // alias unambiguous within the gated set → it links (first→canonical, rest→short).
        let people = [
            person("[[Sam Smith]]", ["Sam"], short: "Sam"),
            person("[[Sam Jones]]", ["Sam"], short: "Sam"),
        ]
        let r = Sanitiser.process(text: "I saw Sam today, then Sam left.", people: people,
                                  aboutPeople: ["[[Sam Smith]]"])
        XCTAssertEqual(r.sanitised, "I saw [[Sam Smith]] today, then Sam left.")
        XCTAssertTrue(r.ambiguous.isEmpty, "unambiguous within the gated set")
    }

    func testOptInTappingBothSameAliasRecordsAmbiguous() {
        // Marking the note about BOTH same-alias people keeps "Sam" ambiguous → plain + recorded.
        let people = [
            person("[[Sam Smith]]", ["Sam"], short: "Sam"),
            person("[[Sam Jones]]", ["Sam"], short: "Sam"),
        ]
        let r = Sanitiser.process(text: "I saw Sam today.", people: people,
                                  aboutPeople: ["[[Sam Smith]]", "[[Sam Jones]]"])
        XCTAssertEqual(r.sanitised, "I saw Sam today.", "ambiguous within the gated set → plain")
        XCTAssertEqual(r.ambiguous.count, 1)
        XCTAssertEqual(r.ambiguous.first?.candidates.count, 2)
    }

    // MARK: Conversation inline — FIRST-ONLY per person + opt-in gating

    func testConversationInlineFirstOnlyForAboutPerson() {
        // A non-speaker the note is about, mentioned twice inline across turns: only the
        // FIRST mention links; the second demotes to the short ("one note, one link").
        let bruno = person("[[Bruno Aragorn]]", ["Bruno"], short: "Bruno")
        let input = "**Speaker 1:** I saw Bruno today\n\n**Speaker 2:** Bruno again?"
        let s = Sanitiser.processConversation(text: input, people: [bruno],
                                              aboutPeople: ["[[Bruno Aragorn]]"]).sanitised
        XCTAssertEqual(s, "**Speaker 1:** I saw [[Bruno Aragorn|Bruno]] today\n\n**Speaker 2:** Bruno again?")
        XCTAssertEqual(s.components(separatedBy: "[[").count - 1, 1, "exactly one inline link")
    }

    func testConversationInlineGatedNonAboutStaysPlainSpeakerAutoLinks() {
        // The matched SPEAKER auto-links in their header regardless of aboutPeople; a
        // non-about person mentioned inline stays plain until tapped.
        let tiuri = person("[[Tiuri Hartog]]", ["Tiuri Hartog", "Tuur"], short: "Tuur")
        let bruno = person("[[Bruno Aragorn]]", ["Bruno"], short: "Bruno")
        let input = "**Tiuri Hartog:** I saw Bruno today\n\n**Speaker 2:** cool"

        // aboutPeople empty: Tiuri (speaker) links in the header; Bruno stays plain.
        let plain = Sanitiser.processConversation(text: input, people: [tiuri, bruno], aboutPeople: []).sanitised
        XCTAssertEqual(plain, "**[[Tiuri Hartog]]:** I saw Bruno today\n\n**Speaker 2:** cool")

        // Tap Bruno: his first inline mention now links too.
        let tapped = Sanitiser.processConversation(text: input, people: [tiuri, bruno],
                                                   aboutPeople: ["[[Bruno Aragorn]]"]).sanitised
        XCTAssertEqual(tapped, "**[[Tiuri Hartog]]:** I saw [[Bruno Aragorn|Bruno]] today\n\n**Speaker 2:** cool")
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
