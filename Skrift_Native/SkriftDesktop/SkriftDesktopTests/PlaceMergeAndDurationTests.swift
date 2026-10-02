import XCTest
import MapKit

/// Q217 (C115, C240): a 2 h 05 note never reads 125:00, and a merged place pin keeps its
/// membership and count as data, so a place called "C+ Cafe" no longer breaks them.
final class PlaceMergeAndDurationTests: XCTestCase {

    func testSevenThousandFiveHundredSecondsIsNotOneTwentyFive() {
        let label = DurationFormat.label(seconds: 7500)
        XCTAssertNotEqual(label, "125:00")
        XCTAssertEqual(label, "2:05:00")
    }

    private func pin(_ id: String, _ lat: Double, _ lon: Double, count: Int = 1) -> PlaceCluster {
        let memos = (0..<count).map { _ in
            Memo(audioFilename: "m.m4a", recordedAt: Date(), transcript: "t", transcriptStatus: .done)
        }
        return PlaceCluster(id: id, name: id, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                            memos: memos)
    }

    func testUnmergedPinIsItsOwnOnlyMember() {
        let p = pin("C+ Cafe", 38.7, -9.1)
        XCTAssertEqual(p.memberIDs, ["C+ Cafe"])
        XCTAssertEqual(p.mergedCount, 1)
        XCTAssertTrue(p.contains(memberID: "C+ Cafe"))
        XCTAssertFalse(p.contains(memberID: "C"))
    }

    func testMergedPinWithPlusInNameKeepsCountTitleAndMembers() {
        let wide = MKCoordinateSpan(latitudeDelta: 20, longitudeDelta: 20)
        let merged = PlaceCluster.merged([pin("C+ Cafe", 38.70, -9.10, count: 3),
                                          pin("Bar", 38.71, -9.11, count: 2),
                                          pin("Park", 38.72, -9.12, count: 1)], span: wide)
        XCTAssertEqual(merged.count, 1)
        let m = merged[0]
        XCTAssertEqual(m.mergedCount, 3)
        XCTAssertEqual(m.memberIDs, ["C+ Cafe", "Bar", "Park"])
        XCTAssertEqual(m.name, "C+ Cafe +2", "base name + (members - 1)")
        XCTAssertTrue(m.contains(memberID: "C+ Cafe"))
        XCTAssertTrue(m.contains(memberID: "Park"))
        XCTAssertFalse(m.contains(memberID: "C"))
        XCTAssertFalse(m.contains(memberID: " Cafe"))
    }

    func testTwoWayMergeLabelIsPlusOne() {
        let wide = MKCoordinateSpan(latitudeDelta: 20, longitudeDelta: 20)
        let merged = PlaceCluster.merged([pin("Estrela", 38.714, -9.161, count: 5),
                                          pin("Alvalade", 38.753, -9.144, count: 2)], span: wide)
        XCTAssertEqual(merged.first?.name, "Estrela +1")
    }
}
