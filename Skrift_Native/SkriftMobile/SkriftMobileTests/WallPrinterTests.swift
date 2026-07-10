import XCTest
import MapKit
@testable import SkriftMobile

final class WallPrinterTests: XCTestCase {

    func testMapClustersCollectWhenZoomedOutAndSplitWhenZoomedIn() {
        func cluster(_ name: String, _ lat: Double, _ lon: Double, count: Int) -> PlaceCluster {
            let memos = (0..<count).map { _ in
                Memo.make(title: name, transcript: "t", transcriptStatus: .done)
            }
            return PlaceCluster(id: name, name: name,
                                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                                memos: memos)
        }
        // Estrela + Alvalade ≈ 4 km apart; Amsterdam far away.
        let base = [cluster("Estrela", 38.714, -9.161, count: 5),
                    cluster("Alvalade", 38.753, -9.144, count: 2),
                    cluster("Amsterdam", 52.370, 4.895, count: 1)]

        // Zoomed OUT (whole Europe): Lisbon collects, Amsterdam stays its own pin.
        let wide = PlaceCluster.merged(base, span: MKCoordinateSpan(latitudeDelta: 20, longitudeDelta: 20))
        XCTAssertEqual(wide.count, 2)
        let lisbon = wide.first { $0.memos.count == 7 }
        XCTAssertNotNil(lisbon)
        XCTAssertTrue(lisbon!.name.hasPrefix("Estrela +"))

        // Zoomed IN (city level): everything pulls apart.
        let tight = PlaceCluster.merged(base, span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))
        XCTAssertEqual(tight.count, 3)
    }

    func testEnqueueGateIsOrangeTierOncePerNote() {
        // Crossing into orange, never printed → fires.
        XCTAssertTrue(WallPrinter.shouldEnqueue(significance: 0.8, alreadyPrinted: false, alreadyQueued: false))
        XCTAssertTrue(WallPrinter.shouldEnqueue(significance: 1.0, alreadyPrinted: false, alreadyQueued: false))
        // Below the tier → never.
        XCTAssertFalse(WallPrinter.shouldEnqueue(significance: 0.7, alreadyPrinted: false, alreadyQueued: false))
        // Printed once = printed forever (re-rating never reprints).
        XCTAssertFalse(WallPrinter.shouldEnqueue(significance: 0.9, alreadyPrinted: true, alreadyQueued: false))
        // Already queued → no double-enqueue.
        XCTAssertFalse(WallPrinter.shouldEnqueue(significance: 0.9, alreadyPrinted: false, alreadyQueued: true))
    }

    func testImportantLatelyIsTierAnchoredRecentAndCapped() {
        let cal = Calendar.current
        let now = cal.date(from: DateComponents(year: 2026, month: 7, day: 7, hour: 12))!
        func memo(daysAgo: Int, sig: Double, title: String) -> Memo {
            Memo.make(recordedAt: cal.date(byAdding: .day, value: -daysAgo, to: now)!,
                      title: title, transcript: "t", transcriptStatus: .done, significance: sig)
        }
        let hot1 = memo(daysAgo: 2, sig: 0.9, title: "hot1")
        let hot2 = memo(daysAgo: 12, sig: 0.8, title: "hot2")   // between lookback anchors!
        let cold = memo(daysAgo: 5, sig: 0.5, title: "cold")
        let old = memo(daysAgo: 45, sig: 1.0, title: "old")     // outside 30d
        let today = memo(daysAgo: 0, sig: 0.9, title: "today")  // included (unlike lookbacks)

        let out = LookbackProvider.importantLately(for: [hot1, hot2, cold, old, today],
                                                   now: now, calendar: cal)
        XCTAssertEqual(out.map(\.id), [today.id, hot1.id, hot2.id])

        let many = (0..<8).map { memo(daysAgo: $0 + 1, sig: 0.9, title: "m\($0)") }
        XCTAssertEqual(LookbackProvider.importantLately(for: many, now: now, calendar: cal).count, 4)
    }
}
