import XCTest
@testable import SkriftMobile

/// R79 / C266: delete-person goes through a confirm state; nothing is deleted until it is
/// confirmed, and cancel deletes nothing. R67: a changed reconcile posts the refresh note.
final class NamesDeleteConfirmTests: XCTestCase {

    func testRequestParksTheCanonicalWithoutDeleting() {
        var s = NameDeleteConfirm()
        XCTAssertFalse(s.isPending)
        s.request("[[Jack Bauer]]")
        XCTAssertTrue(s.isPending)
        XCTAssertEqual(s.pending, "[[Jack Bauer]]")
    }

    func testConfirmReturnsTheCanonicalOnceAndClears() {
        var s = NameDeleteConfirm()
        s.request("[[Jack Bauer]]")
        XCTAssertEqual(s.confirm(), "[[Jack Bauer]]")
        XCTAssertFalse(s.isPending)
        XCTAssertNil(s.confirm(), "a second confirm must not delete again")
    }

    func testCancelDeletesNothing() {
        var s = NameDeleteConfirm()
        s.request("[[Jack Bauer]]")
        s.cancel()
        XCTAssertFalse(s.isPending)
        XCTAssertNil(s.confirm())
    }

    func testConfirmWithoutRequestIsNil() {
        var s = NameDeleteConfirm()
        XCTAssertNil(s.confirm())
    }

    func testBlankCanonicalIsIgnored() {
        var s = NameDeleteConfirm()
        s.request("   ")
        XCTAssertFalse(s.isPending)
    }

    func testTitleUsesTheBareName() {
        XCTAssertEqual(NameDeleteConfirm.title(for: "[[Jack Bauer]]"), "Delete Jack Bauer?")
    }

    func testSyncRefreshPostsOnlyWhenTheRosterChanged() {
        let center = NotificationCenter()
        var posts = 0
        let token = center.addObserver(forName: .namesDidChangeFromSync, object: nil, queue: nil) { _ in posts += 1 }
        defer { center.removeObserver(token) }
        let data = NamesData(lastModifiedAt: "", people: [])
        NamesSyncCore.notifyIfChanged(.init(merged: data, localChanged: false), center: center)
        XCTAssertEqual(posts, 0)
        NamesSyncCore.notifyIfChanged(.init(merged: data, localChanged: true), center: center)
        XCTAssertEqual(posts, 1)
    }
}
