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

    // MARK: plainOccurrences (drives the unlink popover's mention count)

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

    func testPlainOccurrencesPossessiveRangeIncludesApostropheS() {
        let text = "Jack's car."
        let ns = text as NSString
        let occ = Sanitiser.plainOccurrences(of: "Jack", in: text)
        XCTAssertEqual(occ.count, 1)
        XCTAssertEqual(ns.substring(with: occ[0]), "Jack's")
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

    func testExistingPipedLinkSuppressesSecondLink() {
        // Hardening (Q1): a body that already carries the ALIAS-DISPLAY `[[Canonical|short]]`
        // form (not just bare) is recognized too, so `process` never adds a 2nd link past it.
        let people = [person("[[Nick Jansen]]", ["Nick", "Nicky"], short: "Nick")]
        let r = Sanitiser.process(text: "[[Nick Jansen|Nick]] is here. Nicky waves.", people: people)
        XCTAssertEqual(r.sanitised, "[[Nick Jansen|Nick]] is here. Nick waves.")
        XCTAssertEqual(r.sanitised.components(separatedBy: "[[Nick Jansen").count - 1, 1, "still exactly one link")
    }

    func testRepeatedNonPersonLinksUntouched() {
        // Repeated links that aren't people (image markers, place links) never demote.
        let people = [person("[[Nick Jansen]]", ["Nicky"], short: "Nick")]
        let text = "[[img_001]] then [[img_001]] at [[Hotel Du Vin]] and [[Hotel Du Vin]]."
        XCTAssertEqual(Sanitiser.process(text: text, people: people).sanitised, text)
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

    // MARK: namePicks (chunk 4) — the review popover's per-note "which person?" overrides:
    // a canonical FORCE-LINKS the alias (bypassing FP-prone + ambiguity + a prune); "" SILENCES.

    func testNamePickForceLinksAmbiguous() {
        // "which Jack?" → Hutton: the picked alias links Hutton, later mentions short, no ambiguity.
        let people = [
            person("[[Jack Hutton]]", ["Jack"], short: "Jack"),
            person("[[Jack Timmons]]", ["Jack"], short: "Jack"),
        ]
        let r = Sanitiser.process(text: "Met Jack, then Jack again.", people: people,
                                  namePicks: ["jack": "[[Jack Hutton]]"])
        XCTAssertEqual(r.sanitised, "Met [[Jack Hutton]], then Jack again.")
        XCTAssertTrue(r.ambiguous.isEmpty, "the pick resolved the ambiguity")
    }

    func testNamePickForceLinksCommonWord() {
        // Confirming a common-word suggestion ("Will" → Will Smith) force-links it.
        let people = [person("[[Will Smith]]", ["Will"], short: "Will")]
        let r = Sanitiser.process(text: "Will called me back.", people: people,
                                  namePicks: ["will": "[[Will Smith]]"])
        XCTAssertEqual(r.sanitised, "[[Will Smith]] called me back.")
        XCTAssertTrue(r.ambiguous.isEmpty)
    }

    func testNamePickEmptyCanonicalSilences() {
        // "Leave as plain text": the alias renders plain — neither linked nor suggested.
        let people = [person("[[Will Smith]]", ["Will"], short: "Will")]
        let r = Sanitiser.process(text: "Will called me back.", people: people,
                                  namePicks: ["will": ""])
        XCTAssertEqual(r.sanitised, "Will called me back.")
        XCTAssertTrue(r.ambiguous.isEmpty, "silenced → not even suggested")
    }

    func testPrunedDistinctiveNameStaysSuggestion() {
        // Unlink (prune) a distinctive auto-linked name → it stays a dotted suggestion.
        let people = [person("[[Hendri van Niekerk]]", ["Hendri"], short: "Hendri")]
        let r = Sanitiser.process(text: "I met Hendri today.", people: people, neverLink: ["Hendri van Niekerk"])
        XCTAssertEqual(r.sanitised, "I met Hendri today.", "not auto-linked")
        XCTAssertEqual(r.ambiguous.count, 1, "kept as a dotted suggestion (re-promotable)")
        XCTAssertEqual(r.ambiguous.first?.candidates.map(\.canonical), ["[[Hendri van Niekerk]]"])
    }

    func testNamePickToPersonWhoDoesNotOwnTheAlias() {
        // "Change person": force-link the spoken "Hendri" to Will Smith, whose OWN aliases
        // don't include "Hendri". The mention must link to Will Smith — not fall through to
        // plain text (the chunk-4 bug: a forced alias the target didn't declare was dropped).
        let people = [
            person("[[Hendri van Niekerk]]", ["Hendri"], short: "Hendri"),
            person("[[Will Smith]]", ["Will"], short: "Will"),
        ]
        let r = Sanitiser.process(text: "Hendri showed up early.", people: people,
                                  namePicks: ["hendri": "[[Will Smith]]"])
        XCTAssertEqual(r.sanitised, "[[Will Smith]] showed up early.")
        XCTAssertTrue(r.ambiguous.isEmpty)
    }

    func testNamePickOverridesPrune() {
        // Re-promote a pruned name by picking it — the pick wins over the prune.
        let people = [person("[[Hendri van Niekerk]]", ["Hendri"], short: "Hendri")]
        let r = Sanitiser.process(text: "I met Hendri today.", people: people,
                                  neverLink: ["Hendri van Niekerk"],
                                  namePicks: ["hendri": "[[Hendri van Niekerk]]"])
        XCTAssertEqual(r.sanitised, "I met [[Hendri van Niekerk]] today.")
        XCTAssertTrue(r.ambiguous.isEmpty)
    }
}
