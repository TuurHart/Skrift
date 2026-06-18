import XCTest
@testable import SkriftMobile

/// The epoch guard on per-book audiobook transfer progress (`CloudSyncMonitor`).
/// CloudKit's progress callbacks fire off-main + out of order and are dispatched as
/// unstructured MainActor Tasks, so a LATE one could otherwise re-populate
/// `bookTransfers` after the transfer was cleared → a row stuck mid-bar forever. The
/// token makes the end authoritative: only writes bearing the current epoch apply.
/// (The in-memory transport calls `progress(1)` synchronously, so this can't be
/// exercised through the sync tests — hence a direct monitor test.)
@MainActor
final class CloudSyncMonitorTransferTests: XCTestCase {

    func testStaleProgressAfterEndIsDropped() {
        let monitor = CloudSyncMonitor.shared
        let id = UUID()   // unique per test → no interference with the shared singleton

        let epoch = monitor.beginBookTransfer(id, direction: .up)
        monitor.updateBookTransfer(id, epoch: epoch, fraction: 0.5)
        XCTAssertEqual(monitor.bookTransfers[id]?.fraction, 0.5)
        XCTAssertEqual(monitor.bookTransfers[id]?.direction, .up)

        monitor.endBookTransfer(id, epoch: epoch)
        XCTAssertNil(monitor.bookTransfers[id])

        // A straggler callback from the finished transfer must NOT resurrect the row.
        monitor.updateBookTransfer(id, epoch: epoch, fraction: 0.9)
        XCTAssertNil(monitor.bookTransfers[id], "stale progress after end is ignored")
    }

    func testSupersedingTransferDropsOldEpochWrites() {
        let monitor = CloudSyncMonitor.shared
        let id = UUID()

        let old = monitor.beginBookTransfer(id, direction: .up)
        let new = monitor.beginBookTransfer(id, direction: .down)   // supersedes

        monitor.updateBookTransfer(id, epoch: old, fraction: 0.7)   // stale → dropped
        XCTAssertEqual(monitor.bookTransfers[id]?.fraction, 0)
        XCTAssertEqual(monitor.bookTransfers[id]?.direction, .down)

        monitor.updateBookTransfer(id, epoch: new, fraction: 0.3)
        XCTAssertEqual(monitor.bookTransfers[id]?.fraction, 0.3)

        monitor.cancelBookTransfer(id)
        XCTAssertNil(monitor.bookTransfers[id])
        // After cancel, the in-flight epoch's late callbacks are also dropped.
        monitor.updateBookTransfer(id, epoch: new, fraction: 0.8)
        XCTAssertNil(monitor.bookTransfers[id])
    }
}
