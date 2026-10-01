import XCTest
@testable import SkriftMobile

/// Q94 / C70: the ONE filename-date ladder (`Shared/Pipeline/FilenameDate.swift`) — every
/// pattern, run in BOTH test bundles (this file's twin lives in SkriftDesktopTests).
final class FilenameDateTests: XCTestCase {

    private func ymd(_ d: Date?) -> [Int]? {
        guard let d else { return nil }
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: d)
        return [c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!]
    }

    func testEveryPattern() {
        XCTAssertEqual(ymd(FilenameDate.date(from: "WhatsApp Audio 2025-12-18 at 18.30.44.mp3")), [2025, 12, 18, 18, 30, 44])
        XCTAssertEqual(ymd(FilenameDate.date(from: "signal-2026-04-13-18-15-24-552.m4a")), [2026, 4, 13, 18, 15, 24])
        XCTAssertEqual(ymd(FilenameDate.date(from: "AUDIO-2026-03-07-19-30-08.m4a")), [2026, 3, 7, 19, 30, 8])
        XCTAssertEqual(ymd(FilenameDate.date(from: "signal-2026-10-01-080349.jpeg")), [2026, 10, 1, 8, 3, 49], "compact HHMMSS")
        XCTAssertEqual(ymd(FilenameDate.date(from: "signal-2026-10-01-080349")), [2026, 10, 1, 8, 3, 49], "no extension (suggestedName)")
        XCTAssertEqual(ymd(FilenameDate.date(from: "Telegram 2026-02-03 at 09.05.06.ogg")), [2026, 2, 3, 9, 5, 6])
        XCTAssertEqual(ymd(FilenameDate.date(from: "Memo 2024-01-09.m4a")), [2024, 1, 9, 12, 0, 0], "date only → noon")
    }

    func testNoDateFallsThrough() {
        XCTAssertNil(FilenameDate.date(from: "New Recording 22.m4a"))
        XCTAssertNil(FilenameDate.date(from: "Rua 7 de Junho de 1759 3.m4a"), "street number, not a date")
        XCTAssertNil(FilenameDate.date(from: "PTT-20260101-WA0001.opus"), "WhatsApp's compact id is not a dashed date")
        XCTAssertNil(FilenameDate.date(from: "x 2026-13-40.m4a"), "impossible month/day")
        XCTAssertNil(FilenameDate.date(from: ""))
    }

    func testLadderOrder() {
        let embedded = Date(timeIntervalSince1970: 1_000)
        let file = Date(timeIntervalSince1970: 3_000)
        XCTAssertEqual(FilenameDate.ladder(embedded: embedded, filename: "signal-2026-10-01-080349", fileDate: file), embedded)
        XCTAssertEqual(ymd(FilenameDate.ladder(embedded: nil, filename: "signal-2026-10-01-080349", fileDate: file)), [2026, 10, 1, 8, 3, 49])
        XCTAssertEqual(FilenameDate.ladder(embedded: nil, filename: "New Recording 22", fileDate: file), file)
        XCTAssertEqual(FilenameDate.ladder(embedded: nil, filename: nil, fileDate: file), file)
        XCTAssertNil(FilenameDate.ladder(embedded: nil, filename: nil, fileDate: nil))
    }

    func testBestNamePrefersTheOneThatCarriesADate() {
        XCTAssertEqual(FilenameDate.bestName(["shared_ABC.jpeg", "signal-2026-10-01-080349"]), "signal-2026-10-01-080349")
        XCTAssertEqual(FilenameDate.bestName([nil, "IMG_0001.jpg", "Other"]), "IMG_0001.jpg")
        XCTAssertNil(FilenameDate.bestName([nil, ""]))
    }
}
