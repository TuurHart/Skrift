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

    /// End-to-end of what R3's inline resolver produces: the user clicks each mention
    /// (decisions keyed by body LOCATION, as `InlineResolverModel` stores them); on
    /// Apply we re-enumerate `plainOccurrences` in order to build the per-occurrence
    /// arrays (mirrors `NoteDisplayView.maybeApplyEscalated`). Two
    /// friends named "Jack" must resolve to DIFFERENT people, "Sam" to its own.
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
}
