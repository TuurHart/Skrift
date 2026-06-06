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
}
