import XCTest

/// Q533: Notes and Review share ONE left-column width (default 292), written by the
/// Notes divider drag and read by both surfaces.
final class MacSidebarWidthTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let name = "MacSidebarWidthTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    func testDefaultIs292ForBothReaders() {
        let d = freshDefaults()
        XCTAssertEqual(MacSidebarWidth.ideal, 292)
        // Notes' idealWidth and Review's rail both resolve through `clamped` / `current`.
        XCTAssertEqual(MacSidebarWidth.current(in: d), 292)
    }

    func testDragWrittenValueIsReadBack() {
        let d = freshDefaults()
        MacSidebarWidth.record(318.5, in: d)
        XCTAssertEqual(MacSidebarWidth.current(in: d), 318.5)
        XCTAssertEqual(d.double(forKey: PrefKey.macSidebarWidth), 318.5)
    }

    func testOutOfRangeMeasurementsAreNotRecorded() {
        let d = freshDefaults()
        MacSidebarWidth.record(100, in: d)    // collapsed / mid-layout
        MacSidebarWidth.record(900, in: d)
        MacSidebarWidth.record(.nan, in: d)
        XCTAssertEqual(MacSidebarWidth.current(in: d), 292)
        XCTAssertEqual(d.double(forKey: PrefKey.macSidebarWidth), 0, "nothing written")
    }

    func testSubHalfPointJitterIsNotRecorded() {
        let d = freshDefaults()
        MacSidebarWidth.record(300, in: d)
        MacSidebarWidth.record(300.2, in: d)
        XCTAssertEqual(d.double(forKey: PrefKey.macSidebarWidth), 300)
    }

    func testStoredGarbageClampsIntoRange() {
        XCTAssertEqual(MacSidebarWidth.clamped(0), 292)
        XCTAssertEqual(MacSidebarWidth.clamped(-5), 292)
        XCTAssertEqual(MacSidebarWidth.clamped(.infinity), 292)
        XCTAssertEqual(MacSidebarWidth.clamped(10), 240)
        XCTAssertEqual(MacSidebarWidth.clamped(999), 360)
    }
}
