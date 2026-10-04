import XCTest
@testable import SkriftMobile

/// Q239: `MemoLifecycle.partition(_:backlinked:now:)` is the one live/fading split; the
/// scanning overload and the phone list both go through it (one backlink scan per render).
final class MemoLifecyclePartitionTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func note(days: Int, deleted: Bool = false) -> Memo {
        Memo(audioFilename: "m.m4a", recordedAt: now.addingTimeInterval(-Double(days) * 86_400),
             transcript: "just words", transcriptStatus: .done,
             deletedAt: deleted ? now : nil)
    }

    func testPrecomputedBacklinkSetSplitsLiveFadingAndDropsDeleted() {
        let fresh = note(days: 2), old = note(days: 45), linked = note(days: 45), gone = note(days: 45, deleted: true)
        let split = MemoLifecycle.partition([fresh, old, linked, gone], backlinked: [linked.id], now: now)
        XCTAssertEqual(Set(split.live.map(\.id)), [fresh.id, linked.id], "a backlinked note never fades")
        XCTAssertEqual(split.fading.map(\.id), [old.id])
    }

    func testScanningOverloadAgreesWithThePrecomputedOne() {
        let all = [note(days: 2), note(days: 45), note(days: 70)]
        let a = MemoLifecycle.partition(all, now: now)
        let b = MemoLifecycle.partition(all, backlinked: MemoLifecycle.backlinkedIDs(in: all), now: now)
        XCTAssertEqual(a.live.map(\.id), b.live.map(\.id))
        XCTAssertEqual(a.fading.map(\.id), b.fading.map(\.id))
    }
}
