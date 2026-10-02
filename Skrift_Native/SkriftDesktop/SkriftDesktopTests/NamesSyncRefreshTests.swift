import XCTest
import Foundation

/// R67: a CloudKit names reconcile that changes the roster posts `.namesDidChangeFromSync`
/// (the Mac Settings list and the phone Names list/person card re-read on it); an unchanged
/// reconcile posts nothing. R79: delete confirms first (pure confirm state, shared with phone).
final class NamesSyncRefreshTests: XCTestCase {

    private func outcome(changed: Bool) -> NamesSyncCore.Outcome {
        .init(merged: NamesData(lastModifiedAt: "", people: []), localChanged: changed)
    }

    func testChangedReconcilePostsOnce() {
        let center = NotificationCenter()
        var posts = 0
        let token = center.addObserver(forName: .namesDidChangeFromSync, object: nil, queue: nil) { _ in posts += 1 }
        defer { center.removeObserver(token) }
        NamesSyncCore.notifyIfChanged(outcome(changed: true), center: center)
        XCTAssertEqual(posts, 1)
    }

    func testUnchangedReconcilePostsNothing() {
        let center = NotificationCenter()
        var posts = 0
        let token = center.addObserver(forName: .namesDidChangeFromSync, object: nil, queue: nil) { _ in posts += 1 }
        defer { center.removeObserver(token) }
        NamesSyncCore.notifyIfChanged(outcome(changed: false), center: center)
        XCTAssertEqual(posts, 0)
    }

    func testDeleteConfirmGate() {
        var s = NameDeleteConfirm()
        s.request("[[Jack Bauer]]")
        XCTAssertTrue(s.isPending)
        s.cancel()
        XCTAssertNil(s.confirm())
        s.request("[[Jack Bauer]]")
        XCTAssertEqual(s.confirm(), "[[Jack Bauer]]")
        XCTAssertFalse(s.isPending)
    }
}
