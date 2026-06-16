import XCTest
import Foundation

/// Chunk 5 — the roster-collision re-scan (NAMING_MODEL.md build-guard): adding a SECOND
/// same-name person must flag the memos that already auto-linked that name.
final class RosterAuditTests: XCTestCase {

    private func person(_ canonical: String, _ aliases: [String]) -> Person {
        Person(canonical: canonical, aliases: aliases, short: nil, lastModifiedAt: "x")
    }
    private func file(_ id: String, sanitised: String) -> PipelineFile {
        let f = PipelineFile(id: id, filename: "\(id).m4a", sourceType: .audio)
        f.sanitised = sanitised
        return f
    }

    // MARK: newlyAmbiguous

    func testNewlyAmbiguousDetectsAFreshCollision() {
        let old = [person("[[Jack Hutton]]", ["Jack"])]
        let new = old + [person("[[Jack Tanner]]", ["Jack"])]
        XCTAssertEqual(RosterAudit.newlyAmbiguous(old: old, new: new), ["jack"])
    }

    func testNewlyAmbiguousIgnoresAlreadyAmbiguous() {
        // "jack" was already shared → adding a THIRD Jack isn't a NEW collision.
        let old = [person("[[Jack Hutton]]", ["Jack"]), person("[[Jack Tanner]]", ["Jack"])]
        let new = old + [person("[[Jack Doe]]", ["Jack"])]
        XCTAssertTrue(RosterAudit.newlyAmbiguous(old: old, new: new).isEmpty)
    }

    func testNewlyAmbiguousIgnoresADistinctAddition() {
        let old = [person("[[Jack Hutton]]", ["Jack"])]
        let new = old + [person("[[Bruno Aragorn]]", ["Bruno"])]
        XCTAssertTrue(RosterAudit.newlyAmbiguous(old: old, new: new).isEmpty)
    }

    // MARK: affectedFiles

    func testAffectedFilesAreThoseLinkingAColliedPerson() {
        let new = [person("[[Jack Hutton]]", ["Jack"]), person("[[Jack Tanner]]", ["Jack"]),
                   person("[[Bruno Aragorn]]", ["Bruno"])]
        let files = [
            file("a", sanitised: "Met [[Jack Hutton]] today."),        // links a now-ambiguous Jack → affected
            file("b", sanitised: "Saw [[Bruno Aragorn]] earlier."),     // unrelated person → not
            file("c", sanitised: "No links here at all."),              // no links → not
        ]
        let affected = RosterAudit.affectedFiles(files, newlyAmbiguous: ["jack"], people: new)
        XCTAssertEqual(affected.map(\.id), ["a"])
    }

    func testAffectedFilesSkipsDeleted() {
        let new = [person("[[Jack Hutton]]", ["Jack"]), person("[[Jack Tanner]]", ["Jack"])]
        let f = file("a", sanitised: "Met [[Jack Hutton]] today.")
        f.deletedAt = Date()
        XCTAssertTrue(RosterAudit.affectedFiles([f], newlyAmbiguous: ["jack"], people: new).isEmpty)
    }

    func testEmptyCollisionSetMatchesNothing() {
        let f = file("a", sanitised: "Met [[Jack Hutton]] today.")
        XCTAssertTrue(RosterAudit.affectedFiles([f], newlyAmbiguous: [], people: []).isEmpty)
    }
}
