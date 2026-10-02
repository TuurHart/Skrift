import XCTest
import SwiftData
@testable import SkriftMobile

/// C115 area: a store that fails to open must show a "couldn't open your notes" state,
/// not crash, and must never touch (delete / recreate) the real store.
@MainActor
final class StoreStartFailureTests: XCTestCase {
    private struct Boom: Error, CustomStringConvertible {
        var description: String { "Boom: store would not open" }
    }

    func testNoErrorMeansNoFailureState() {
        XCTAssertNil(StoreStartPolicy.decide(nil))
    }

    func testErrorKeepsTextAndGivesHint() throws {
        let f = try XCTUnwrap(StoreStartPolicy.decide(Boom()))
        XCTAssertEqual(f.title, "Skrift couldn't open your notes")
        XCTAssertTrue(f.errorText.contains("Boom: store would not open"))
        XCTAssertTrue(f.hint.localizedCaseInsensitiveContains("iCloud"))
        XCTAssertTrue(f.hint.localizedCaseInsensitiveContains("open it again"))
    }

    func testOutOfSpaceGetsStorageHint() throws {
        let e = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)
        let f = try XCTUnwrap(StoreStartPolicy.decide(e))
        XCTAssertTrue(f.hint.localizedCaseInsensitiveContains("out of storage"))
    }

    func testDecisionIsPure() {
        XCTAssertEqual(StoreStartPolicy.decide(Boom()), StoreStartPolicy.decide(Boom()))
    }

    func testFailingFactoryDoesNotCrashAndReportsFailure() {
        let repo = NotesRepository(inMemory: true, containerFactory: { _, _ in throw Boom() })
        XCTAssertNotNil(repo.startFailure)
        XCTAssertFalse(repo.isUsable)
        XCTAssertTrue(repo.startFailure?.errorText.contains("Boom") ?? false)
        // the placeholder is an empty in-memory store, never the real one
        XCTAssertEqual(repo.allMemos().count, 0)
    }

    func testHealthyStoreHasNoFailure() {
        let repo = NotesRepository(inMemory: true)
        XCTAssertNil(repo.startFailure)
        XCTAssertTrue(repo.isUsable)
    }

    func testDrainRefusesWhenStoreFailed() async {
        let repo = NotesRepository(inMemory: true, containerFactory: { _, _ in throw Boom() })
        await CaptureInboxDrainer.drain(into: repo)   // returns without consuming anything
        XCTAssertEqual(repo.allMemos().count, 0)
    }
}
