import XCTest
import Foundation

/// `Sanitiser.applyPartialOccurrences` + `plainSlotMap` — the engine behind the
/// instant-apply per-occurrence resolver ("They're different people"): every pick
/// re-renders the body from the pristine snapshot + the choices so far, so a chosen
/// mention transforms immediately, undecided mentions stay verbatim (and
/// highlightable), and first-mention-gets-`[[Canonical]]` follows DOCUMENT order no
/// matter the click order.
final class ResolverInstantApplyTests: XCTestCase {

    // "Met Jack, then Jack again. Later Jack and finally Jack."
    //       occ0(4)    occ1(15)         occ2(33)         occ3(50)
    private let fourJacks = "Met Jack, then Jack again. Later Jack and finally Jack."
    private let hutton = Sanitiser.PartialChoice.person(canonical: "[[Jack Hutton]]", short: "Jack")
    private let timmons = Sanitiser.PartialChoice.person(canonical: "[[Jack Timmons]]", short: "Jack")

    private func sub(_ s: String, _ r: NSRange) -> String { (s as NSString).substring(with: r) }

    // MARK: instant single pick

    func testSinglePickLinksThatMentionOnly() {
        // Assign only the THIRD mention → it links immediately; the rest stay verbatim.
        let r = Sanitiser.applyPartialOccurrences(
            text: fourJacks,
            byAlias: ["Jack": [.undecided, .undecided, hutton, .undecided]])
        XCTAssertEqual(r.text, "Met Jack, then Jack again. Later [[Jack Hutton]] and finally Jack.")
        let ranges = r.ranges["Jack"]!
        XCTAssertEqual(ranges.count, 4)
        XCTAssertEqual(sub(r.text, ranges[0]), "Jack")
        XCTAssertEqual(sub(r.text, ranges[1]), "Jack")
        XCTAssertEqual(sub(r.text, ranges[2]), "[[Jack Hutton]]")
        XCTAssertEqual(sub(r.text, ranges[3]), "Jack")
    }

    // MARK: out-of-document-order assignment + demotion

    func testEarlierAssignmentDemotesLaterMentionInSameRefresh() {
        // Occurrence 2 was assigned Hutton first (and rendered as the link). NOW
        // occurrence 0 is also assigned Hutton: document order makes 0 the canonical
        // link and DEMOTES 2 to the short name — in one recompute.
        let r = Sanitiser.applyPartialOccurrences(
            text: fourJacks,
            byAlias: ["Jack": [hutton, .undecided, hutton, .undecided]])
        XCTAssertEqual(r.text, "Met [[Jack Hutton]], then Jack again. Later Jack and finally Jack.")
        // Exactly ONE link.
        XCTAssertEqual(r.text.components(separatedBy: "[[Jack Hutton]]").count - 1, 1)
        let ranges = r.ranges["Jack"]!
        XCTAssertEqual(sub(r.text, ranges[0]), "[[Jack Hutton]]")
        XCTAssertEqual(sub(r.text, ranges[2]), "Jack")   // demoted to short
    }

    // MARK: position recomputation when earlier text changes length

    func testRangesShiftWhenEarlierReplacementChangesLength() {
        // "[[Jack Hutton]]" (15) replaces "Jack" (4) at occurrence 0 → +11 shift
        // for everything after it. Occurrence 1 sat at 15 in the snapshot.
        let r = Sanitiser.applyPartialOccurrences(
            text: fourJacks,
            byAlias: ["Jack": [hutton, .undecided, .undecided, .undecided]])
        let ranges = r.ranges["Jack"]!
        XCTAssertEqual(ranges[0], NSRange(location: 4, length: 15))
        XCTAssertEqual(ranges[1].location, 15 + 11)
        XCTAssertEqual(sub(r.text, ranges[1]), "Jack")
        XCTAssertEqual(sub(r.text, ranges[2]), "Jack")
        XCTAssertEqual(sub(r.text, ranges[3]), "Jack")
        // And they line up with a fresh plain-occurrence enumeration of the render.
        XCTAssertEqual(Sanitiser.plainOccurrences(of: "Jack", in: r.text), [ranges[1], ranges[2], ranges[3]])
    }

    // MARK: completion parity

    func testAllDecidedMatchesApplyResolvedOccurrences() {
        // Drift guard: a fully-decided partial render must equal what the commit
        // path (`applyResolvedOccurrences`) persists.
        let partial = Sanitiser.applyPartialOccurrences(
            text: fourJacks,
            byAlias: ["Jack": [hutton, hutton, timmons, timmons]])
        let committed = Sanitiser.applyResolvedOccurrences(
            text: fourJacks,
            byAlias: ["Jack": [
                (canonical: "[[Jack Hutton]]", short: "Jack"),
                (canonical: "[[Jack Hutton]]", short: "Jack"),
                (canonical: "[[Jack Timmons]]", short: "Jack"),
                (canonical: "[[Jack Timmons]]", short: "Jack"),
            ]])
        XCTAssertEqual(partial.text, committed)
        XCTAssertEqual(partial.text, "Met [[Jack Hutton]], then Jack again. Later [[Jack Timmons]] and finally Jack.")
    }

    func testPlainChoiceMatchesCommitNilDecision() {
        let partial = Sanitiser.applyPartialOccurrences(
            text: "Jack and Jack.",
            byAlias: ["Jack": [hutton, .plain]])
        let committed = Sanitiser.applyResolvedOccurrences(
            text: "Jack and Jack.",
            byAlias: ["Jack": [(canonical: "[[Jack Hutton]]", short: "Jack"), (canonical: nil, short: nil)]])
        XCTAssertEqual(partial.text, committed)
        XCTAssertEqual(partial.text, "[[Jack Hutton]] and Jack.")
    }

    // MARK: possessive + pre-existing links

    func testPossessivePreservedThroughPartialApply() {
        let untouched = Sanitiser.applyPartialOccurrences(
            text: "Jack's car. Jack waved.",
            byAlias: ["Jack": [.undecided, hutton]])
        XCTAssertEqual(untouched.text, "Jack's car. [[Jack Hutton]] waved.")
        let possessiveLinked = Sanitiser.applyPartialOccurrences(
            text: "Jack's car. Jack waved.",
            byAlias: ["Jack": [hutton, hutton]])
        XCTAssertEqual(possessiveLinked.text, "[[Jack Hutton]]'s car. Jack waved.")
        XCTAssertEqual(sub(possessiveLinked.text, possessiveLinked.ranges["Jack"]![0]), "[[Jack Hutton]]'s")
    }

    func testExistingLinkInSnapshotSuppressesNewLink() {
        // A turn header already links the person — the partial render must not mint
        // a second link (same rule as the commit path).
        let r = Sanitiser.applyPartialOccurrences(
            text: "**[[Jack Hutton]]:** hi\n\nMet Jack later.",
            byAlias: ["Jack": [hutton]])
        XCTAssertEqual(r.text, "**[[Jack Hutton]]:** hi\n\nMet Jack later.")
        XCTAssertEqual(sub(r.text, r.ranges["Jack"]![0]), "Jack")   // rendered as short
    }

    // MARK: multiple aliases over one snapshot

    func testTwoAliasesComposeInOneDocumentOrderPass() {
        let r = Sanitiser.applyPartialOccurrences(
            text: "Jack met Sam. Sam met Jack.",
            byAlias: [
                "Jack": [hutton, .undecided],
                "Sam": [.undecided, .person(canonical: "[[Sam Jones]]", short: "Sam")],
            ])
        XCTAssertEqual(r.text, "[[Jack Hutton]] met Sam. [[Sam Jones]] met Jack.")
        XCTAssertEqual(sub(r.text, r.ranges["Jack"]![0]), "[[Jack Hutton]]")
        XCTAssertEqual(sub(r.text, r.ranges["Jack"]![1]), "Jack")
        XCTAssertEqual(sub(r.text, r.ranges["Sam"]![0]), "Sam")
        XCTAssertEqual(sub(r.text, r.ranges["Sam"]![1]), "[[Sam Jones]]")
    }

    func testMissingChoicesTreatedAsUndecided() {
        // The UI passes one entry per occurrence, but a short array must not crash
        // or mis-link — the tail is simply undecided.
        let r = Sanitiser.applyPartialOccurrences(text: "Jack and Jack.", byAlias: ["Jack": [hutton]])
        XCTAssertEqual(r.text, "[[Jack Hutton]] and Jack.")
        XCTAssertEqual(r.ranges["Jack"]!.count, 2)
        XCTAssertEqual(sub(r.text, r.ranges["Jack"]![1]), "Jack")
    }

    // MARK: slot map — render-text plain occurrences back to snapshot indices

    func testSlotMapAttributesDemotedShortToItsSnapshotIndex() {
        // 0 + 2 both Hutton → 0 links, 2 demotes to short "Jack" (reads EXACTLY like
        // an undecided mention). The slot map must still know the k-th plain "Jack"
        // in the render is snapshot occurrence 1 / 2 / 3 — so the calm "decided"
        // tint lands on the right mention and re-clicking it edits the right choice.
        let r = Sanitiser.applyPartialOccurrences(
            text: fourJacks,
            byAlias: ["Jack": [hutton, .undecided, hutton, .undecided]])
        let slots = Sanitiser.plainSlotMap(alias: "Jack", rendered: r.text, occurrenceRanges: r.ranges["Jack"]!)
        XCTAssertEqual(slots, [1, 2, 3])
    }

    func testSlotMapIdentityWhenNothingDecided() {
        let r = Sanitiser.applyPartialOccurrences(
            text: fourJacks,
            byAlias: ["Jack": [.undecided, .undecided, .undecided, .undecided]])
        XCTAssertEqual(r.text, fourJacks)
        let slots = Sanitiser.plainSlotMap(alias: "Jack", rendered: r.text, occurrenceRanges: r.ranges["Jack"]!)
        XCTAssertEqual(slots, [0, 1, 2, 3])
    }
}
