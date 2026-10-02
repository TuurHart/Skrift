import XCTest
@testable import SkriftMobile

/// BookTileState: the label/fraction rules the Books row and the iPad shelf tile share (P49).
final class BookTileStateTests: XCTestCase {
    func testTransferLabelShowsPercentOrDropsItBeforeFirstByte() {
        XCTAssertEqual(BookTileState.transferLabel(uploading: true, fraction: 0.38), "Uploading audio · 38%")
        XCTAssertEqual(BookTileState.transferLabel(uploading: false, fraction: 0.61), "Downloading · 61%")
        XCTAssertEqual(BookTileState.transferLabel(uploading: true, fraction: nil), "Uploading audio…")
        XCTAssertEqual(BookTileState.transferLabel(uploading: false, fraction: nil), "Downloading…")
    }

    func testPercentClamps() {
        XCTAssertEqual(BookTileState.percent(-0.2), 0)
        XCTAssertEqual(BookTileState.percent(1.4), 100)
    }

    func testRealignLine() {
        XCTAssertNil(BookTileState.realignLine(active: false, stage: "Reading the text…"))
        XCTAssertEqual(BookTileState.realignLine(active: true, stage: "Matching the text…"), "Matching the text…")
        XCTAssertEqual(BookTileState.realignLine(active: true, stage: nil), BookTileState.realignFallback)
    }

    func testAccessibilityLabelCarriesAuthorSyncStateAndTransfer() {
        XCTAssertEqual(
            BookTileState.accessibilityLabel(title: "Dune", author: "Frank Herbert", timeLeft: "3h 10m",
                                             syncState: .uploading, transferFraction: 0.38, realign: nil),
            "Dune by Frank Herbert, 3h 10m left, uploading 38 percent")
        XCTAssertEqual(
            BookTileState.accessibilityLabel(title: "Dune", author: "", timeLeft: "3h 10m",
                                             syncState: .downloadAvailable, transferFraction: nil, realign: nil),
            "Dune, 3h 10m left, synced, download to this device")
        XCTAssertEqual(
            BookTileState.accessibilityLabel(title: "Dune", author: "Frank Herbert", timeLeft: "3h 10m",
                                             syncState: nil, transferFraction: nil, realign: "Matching the text…"),
            "Dune by Frank Herbert, 3h 10m left, Matching the text…")
    }

    func testDeleteCopyNeverSaysIPhone() {
        XCTAssertFalse(BookTileState.removeThisDeviceTitle.contains("iPhone"))
        XCTAssertTrue(BookTileState.removeThisDeviceTitle.contains("this device"))
        for synced in [true, false] {
            XCTAssertFalse(BookTileState.deleteMessage(synced: synced).contains("iPhone"))
        }
        XCTAssertTrue(BookTileState.deleteMessage(synced: false).contains("this device"))
    }
}
