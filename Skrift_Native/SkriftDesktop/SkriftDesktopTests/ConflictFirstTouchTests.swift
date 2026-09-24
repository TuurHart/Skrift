import XCTest
import SwiftData

/// Q42 (C98, gate+): a never-stamped (pre-Q29) note's FIRST touch on a device must not count
/// as a words edit when no words actually changed — a first audio trim / annotation must not
/// manufacture a false "2 versions" against a genuine edit made on another device apart.
///
/// BLOCKED (see the Q42 worker report): a "seed the baseline without bumping on first touch"
/// fix inside `recordEdit`/`recordPolishedEdit` was tried and reverted — it broke
/// `EditConflictTests.testDivergingEditsBecomeAConflictRecordAndNothingIsLost` and four
/// `PolishedEditConflictTests` cases, because those protected tests rely on EXACTLY the same
/// never-stamped first call (`seed()` sets no `editStampHash`) to register a REAL conflicting
/// edit. There is no data available inside `recordEdit`/`recordPolishedEdit` at call time to
/// tell "this first touch changed no words" apart from "this first touch IS the genuine word
/// edit" — both look identical (`editStampHash == nil`, current words already mutated or not).
/// Only the Mac `MacCloudEditSync.flush` half of this item shipped; see below.
final class ConflictFirstTouchTests: XCTestCase {

    /// The `flush` fix (Q42): a title-only Mac edit must not register as a polished edit just
    /// because re-`process`ing + un-linking the unchanged body isn't a lossless round trip.
    /// This proves the round trip IS faithful for an ordinary case, so comparing both sides
    /// through it (as `flush` now does) only flags a REAL body change.
    func testUnlinkRoundTripDoesNotFalselyCountATitleOnlyEditAsPolished() throws {
        let people = [Person(canonical: "Nick Jansen", aliases: ["Nick"], lastModifiedAt: "2026-01-01T00:00:00Z")]
        let original = "Nick Jansen said hi, and later Nick said bye."
        let linked = Sanitiser.process(text: original, people: people).sanitised
        let roundTripped = Sanitiser.unlinkToSpoken(linked, people: people)
        XCTAssertEqual(roundTripped, original,
                       "process -> unlinkToSpoken round-trips, so flush's before/after comparison " +
                       "through the same pipeline correctly sees no change on a title-only edit")
    }
}
