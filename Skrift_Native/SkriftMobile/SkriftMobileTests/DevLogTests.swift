import XCTest
@testable import SkriftMobile

/// The pure parts of the dev file logger: the ring-buffer trim (cap → keep,
/// aligned to a line boundary so the file never reopens mid-line) and a smoke
/// test of the DEBUG append path (timestamped line lands in
/// `Documents/devlog.txt`).
final class DevLogTests: XCTestCase {

    private func lines(_ count: Int, width: Int = 10) -> Data {
        // "line 000007…\n" rows of a fixed width, so byte math is predictable.
        var out = Data()
        for i in 0..<count {
            let body = String(format: "line %0\(width)d", i)
            out.append(Data((body + "\n").utf8))
        }
        return out
    }

    // MARK: - Ring-buffer trim (pure)

    func testUnderCapIsUntouched() {
        let data = lines(10)
        XCTAssertEqual(DevLog.trimmed(data, cap: data.count, keep: data.count / 2), data,
                       "at/under the cap nothing is trimmed")
    }

    func testOverCapTrimsToKeepNewestLines() {
        let data = lines(100)            // 100 × 16 bytes = 1600
        let trimmed = DevLog.trimmed(data, cap: 800, keep: 400)
        XCTAssertLessThanOrEqual(trimmed.count, 400)
        // The newest lines survive: the trimmed data is a strict suffix.
        XCTAssertEqual(trimmed, data.suffix(trimmed.count))
        let text = String(decoding: trimmed, as: UTF8.self)
        XCTAssertTrue(text.hasSuffix("line 0000000099\n"), "the last line must survive a trim")
    }

    func testTrimAlignsToLineBoundary() {
        let data = lines(100)
        // keep = 401 cuts mid-line (lines are 16 bytes) — the partial first
        // line must be dropped.
        let trimmed = DevLog.trimmed(data, cap: 800, keep: 401)
        let text = String(decoding: trimmed, as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("line "), "trimmed file must start at a full line")
        XCTAssertFalse(text.isEmpty)
        // Every kept row is intact.
        for row in text.split(separator: "\n") {
            XCTAssertEqual(row.count, 15, "no partial rows after the trim: \(row)")
        }
    }

    func testTrimWithoutAnyNewlineKeepsRawTail() {
        // One giant line (pathological) — better a partial line than nothing.
        let data = Data(String(repeating: "x", count: 1000).utf8)
        let trimmed = DevLog.trimmed(data, cap: 500, keep: 200)
        XCTAssertEqual(trimmed, data.suffix(200))
    }

    func testCapAndKeepConstantsAreSane() {
        XCTAssertEqual(DevLog.capBytes, 512 * 1024)
        XCTAssertLessThan(DevLog.keepBytes, DevLog.capBytes,
                          "a trim must land below the cap or it would thrash")
        XCTAssertGreaterThan(DevLog.keepBytes, 0)
    }

    // MARK: - DEBUG append path (smoke)

    func testLogAppendsTimestampedLineToFile() throws {
        let marker = "devlog-test-\(UUID().uuidString)"
        DevLog.log(marker)
        DevLog.drain()
        let text = String(decoding: try Data(contentsOf: DevLog.fileURL), as: UTF8.self)
        let line = try XCTUnwrap(text.split(separator: "\n").last(where: { $0.contains(marker) }))
        // "yyyy-MM-dd HH:mm:ss.SSS  <message>"
        XCTAssertNotNil(line.range(of: #"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3}  "#,
                                   options: .regularExpression),
                        "line must carry the timestamp prefix: \(line)")
    }
}
