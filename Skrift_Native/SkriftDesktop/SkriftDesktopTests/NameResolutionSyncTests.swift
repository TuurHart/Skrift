import XCTest
import Foundation

/// Q116 (C81, D20, R37): a note's name decisions (unlink / pick / silence) are ONE shared
/// blob that syncs both ways — a decision made through the Mac adapter lands in the phone's
/// resolution set (`Memo.nameResolutions`, what the phone's tap-to-resolve surface reads),
/// and a phone decision lands on the Mac row the `Sanitiser` links with.
final class NameResolutionSyncTests: XCTestCase {

    private let people: [Person] = [
        Person(canonical: "[[Jack Hutton]]", aliases: ["Jack"], short: nil, lastModifiedAt: "2026-01-01T00:00:00Z"),
        Person(canonical: "[[Jack Tanner]]", aliases: ["Jack"], short: nil, lastModifiedAt: "2026-01-01T00:00:00Z"),
        Person(canonical: "[[Hendri van Niekerk]]", aliases: ["Hendri"], short: "Hendri", lastModifiedAt: "2026-01-01T00:00:00Z"),
    ]

    private func pair(_ transcript: String = "Met Jack and Hendri today.") -> (Memo, PipelineFile) {
        let id = UUID()
        let memo = Memo(id: id, audioFilename: "memo_\(id.uuidString).m4a",
                        transcript: transcript, transcriptStatus: .done, transcriptConfidence: 0.9)
        let pf = PipelineFile(id: id.uuidString, filename: "memo_\(id.uuidString).m4a")
        pf.transcript = transcript
        pf.transcribeStatus = .done
        return (memo, pf)
    }

    // MARK: - Mac → phone

    func testAMacPickAppearsInThePhonesResolutionSet() {
        let (memo, pf) = pair()
        var r = pf.nameResolutions; r.link(alias: "Jack", to: "Jack Tanner"); pf.nameResolutions = r

        XCTAssertTrue(NameResolutionsMirror.push(pf, to: memo))
        XCTAssertEqual(memo.nameResolutions.namePicks, ["jack": "[[Jack Tanner]]"])
        // …and the phone's own tier engine now treats Jack as linked to Tanner.
        let span = Sanitiser.nameSpans(inRaw: memo.transcript ?? "", people: people,
                                       neverLink: Set(memo.nameResolutions.unlinkedNames),
                                       namePicks: memo.nameResolutions.namePicks)
            .first { $0.alias == "Jack" }
        XCTAssertEqual(span?.tier, .linked)
        XCTAssertEqual(span?.canonical, "[[Jack Tanner]]")
        XCTAssertFalse(NameResolutionsMirror.push(pf, to: memo), "converged — no churn")
    }

    func testAMacUnlinkAndSilenceBothReachThePhone() {
        let (memo, pf) = pair()
        var r = pf.nameResolutions
        r.unlinkPerson("[[Hendri van Niekerk]]")
        r.keepPlain(alias: "Jack")
        pf.nameResolutions = r
        NameResolutionsMirror.push(pf, to: memo)

        XCTAssertEqual(memo.nameResolutions.unlinkedNames, ["[[Hendri van Niekerk]]"])
        XCTAssertEqual(memo.nameResolutions.namePicks, ["jack": ""])
        // The legacy views on the row read the same shared blob.
        XCTAssertEqual(pf.unlinkedNames, ["[[Hendri van Niekerk]]"])
        XCTAssertEqual(pf.namePicks, ["jack": ""])
    }

    // MARK: - phone → Mac

    func testAPhoneDecisionLandsOnTheMacRowAndSteersItsLinks() {
        let (memo, pf) = pair("Met Jack today.")
        memo.linkName(alias: "Jack", to: "[[Jack Hutton]]")   // the phone's own gesture

        XCTAssertTrue(NameResolutionsMirror.pull(memo, into: pf))
        XCTAssertEqual(pf.namePicks, ["jack": "[[Jack Hutton]]"])
        let linked = Sanitiser.process(text: pf.transcript ?? "", people: people,
                                       neverLink: Set(pf.unlinkedNames), namePicks: pf.namePicks)
        XCTAssertTrue(linked.sanitised.contains("[[Jack Hutton]]"), linked.sanitised)
        XCTAssertFalse(NameResolutionsMirror.pull(memo, into: pf), "converged — no churn")

        // Undo on the phone clears it on the Mac too.
        memo.clearNameResolution(alias: "Jack")
        XCTAssertTrue(NameResolutionsMirror.pull(memo, into: pf))
        XCTAssertTrue(pf.nameResolutions.isEmpty)
        XCTAssertNil(pf.nameResolutionsData)
    }

    func testRoundTripMacThenPhoneThenMac() {
        let (memo, pf) = pair()
        var r = pf.nameResolutions; r.keepPlain(alias: "Hendri"); pf.nameResolutions = r
        NameResolutionsMirror.push(pf, to: memo)

        memo.linkName(alias: "Jack", to: "[[Jack Tanner]]")
        NameResolutionsMirror.pull(memo, into: pf)
        XCTAssertEqual(pf.namePicks, ["hendri": "", "jack": "[[Jack Tanner]]"])
        XCTAssertEqual(pf.nameResolutionsData, memo.nameResolutionsData, "one blob, same bytes")
    }

    func testPhoneUpdateReflectsDecisionsThroughMemoCloudUpdate() {
        let (memo, pf) = pair("Met Jack today.")
        pf.syncedSourceEditedAt = memo.lastEditedAt
        memo.linkName(alias: "Jack", to: "[[Jack Tanner]]")
        XCTAssertTrue(MemoCloudUpdate.apply(memo: memo, enhancement: nil, to: pf, people: people,
                                            author: "Tuur", thisDeviceID: "mac-1"))
        XCTAssertEqual(pf.namePicks, ["jack": "[[Jack Tanner]]"])
        XCTAssertTrue(pf.sanitised?.contains("[[Jack Tanner]]") ?? false, pf.sanitised ?? "nil")
    }

    // MARK: - Legacy Mac-only decisions (pre-Q116)

    func testLegacyMacDecisionsSurviveAnEmptyPhoneAndMigrateOut() {
        let (memo, pf) = pair()
        pf.legacyUnlinkedNames = ["Hendri van Niekerk"]
        pf.legacyNamePicksJSON = try? JSONEncoder().encode(["jack": "[[Jack Hutton]]"])
        XCTAssertTrue(pf.hasLegacyNameResolutions)
        XCTAssertEqual(pf.namePicks, ["jack": "[[Jack Hutton]]"], "legacy read through the shared view")

        XCTAssertFalse(NameResolutionsMirror.pull(memo, into: pf), "an empty memo never wipes them")
        XCTAssertEqual(pf.unlinkedNames, ["Hendri van Niekerk"])

        XCTAssertTrue(NameResolutionsMirror.migrateLegacy(pf, to: memo))
        XCTAssertFalse(pf.hasLegacyNameResolutions)
        XCTAssertTrue(pf.legacyUnlinkedNames.isEmpty)
        XCTAssertNil(pf.legacyNamePicksJSON)
        XCTAssertEqual(memo.nameResolutions.unlinkedNames, ["Hendri van Niekerk"])
        XCTAssertEqual(memo.nameResolutions.namePicks, ["jack": "[[Jack Hutton]]"])
        XCTAssertFalse(NameResolutionsMirror.migrateLegacy(pf, to: memo), "once")
    }

    func testMigrationNeverOverwritesAPhoneDecision() {
        let (memo, pf) = pair()
        memo.linkName(alias: "Jack", to: "[[Jack Tanner]]")
        pf.legacyNamePicksJSON = try? JSONEncoder().encode(["jack": "[[Jack Hutton]]"])
        XCTAssertFalse(NameResolutionsMirror.migrateLegacy(pf, to: memo))
        XCTAssertEqual(memo.nameResolutions.namePicks, ["jack": "[[Jack Tanner]]"])
        XCTAssertTrue(NameResolutionsMirror.pull(memo, into: pf), "the synced decision wins")
        XCTAssertEqual(pf.namePicks, ["jack": "[[Jack Tanner]]"])
        XCTAssertFalse(pf.hasLegacyNameResolutions)
    }

    // MARK: - One wording set

    func testActionLabelsComeFromTheSignedOffMocks() {
        XCTAssertEqual(NameActionLabel.unlink, "Unlink — just a side-mention")
        XCTAssertEqual(NameActionLabel.changePerson, "Change person…")
        XCTAssertEqual(NameActionLabel.changePerson(to: "Jack Tanner"), "Change person → Jack Tanner")
        XCTAssertEqual(NameActionLabel.keepPlain, "Keep as plain text")
    }
}
