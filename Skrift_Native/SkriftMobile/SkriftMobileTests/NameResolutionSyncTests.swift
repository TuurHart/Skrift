import XCTest
@testable import SkriftMobile

/// Q116 (C81, D20, R37): the phone side of the shared name-decision blob. The Mac writes
/// `Memo.nameResolutionsData` in the shared `NameResolutions` shape (desktop
/// `NameResolutionSyncTests` drives the Mac adapter); this pins that such a blob — and the
/// Mac's "unlink a person" decision, which the phone has no gesture for — steers the phone's
/// tier engine, and that a phone decision encodes to the same shape the Mac reads.
final class NameResolutionSyncTests: XCTestCase {

    private var people: [Person] {
        [
            Person(canonical: "[[Jack Hutton]]", aliases: ["Jack"], short: nil, lastModifiedAt: "2026-01-01T00:00:00Z"),
            Person(canonical: "[[Jack Tanner]]", aliases: ["Jack"], short: nil, lastModifiedAt: "2026-01-01T00:00:00Z"),
            Person(canonical: "[[Hendri van Niekerk]]", aliases: ["Hendri"], short: "Hendri", lastModifiedAt: "2026-01-01T00:00:00Z"),
        ]
    }

    func testAMacWrittenBlobSteersThePhonesTiers() {
        let m = Memo(transcript: "Met Jack and Hendri today.", transcriptStatus: .done)
        var mac = NameResolutions()
        mac.link(alias: "Jack", to: "Jack Tanner")
        mac.unlinkPerson("[[Hendri van Niekerk]]")
        m.nameResolutionsData = mac.encoded   // what CloudKit delivers from the Mac

        let spans = m.nameSpans(people: people)
        XCTAssertEqual(spans.first { $0.alias == "Jack" }?.tier, .linked)
        XCTAssertEqual(spans.first { $0.alias == "Jack" }?.canonical, "[[Jack Tanner]]")
        XCTAssertNotEqual(spans.first { $0.alias == "Hendri" }?.tier, .linked, "pruned on the Mac → not linked here")
    }

    func testAPhoneDecisionEncodesToTheSharedShape() {
        let m = Memo(transcript: "Met Jack today.", transcriptStatus: .done)
        m.linkName(alias: " Jack ", to: "[[Jack Hutton]]")
        m.keepNamePlain(alias: "Hendri")
        let decoded = NameResolutions.decode(m.nameResolutionsData)
        XCTAssertEqual(decoded.namePicks, ["jack": "[[Jack Hutton]]", "hendri": ""])
        XCTAssertEqual(decoded.encoded, m.nameResolutionsData, "deterministic bytes both ways")
    }

    func testActionLabelsAreTheSharedTable() {
        XCTAssertEqual(NameActionLabel.unlink, "Unlink — just a side-mention")
        XCTAssertEqual(NameActionLabel.changePerson(to: "Jack Tanner"), "Change person → Jack Tanner")
    }
}
