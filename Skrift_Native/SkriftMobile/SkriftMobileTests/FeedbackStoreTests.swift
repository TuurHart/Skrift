import XCTest
@testable import SkriftMobile

/// Q223: `FeedbackStore` is a plain writer. The on-disk `metadata.json` layout is read over
/// USB by `.claude/skills/pull-phone-feedback`, so its field names and ISO8601 dates are pinned.
final class FeedbackStoreTests: XCTestCase {
    func testSaveWritesTheLayoutThePullSkillReadsAndMarkSentPersists() throws {
        let item = FeedbackStore.save(transcript: "It froze.", note: "on stop", screenshot: nil, durationSeconds: 4.5)
        defer { try? FileManager.default.removeItem(at: item.folder) }

        let url = item.folder.appendingPathComponent("metadata.json")
        func json() throws -> [String: Any] {
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        }
        var obj = try json()
        XCTAssertEqual(obj["transcript"] as? String, "It froze.")
        XCTAssertEqual(obj["note"] as? String, "on stop")
        XCTAssertEqual(obj["hasScreenshot"] as? Bool, false)
        XCTAssertEqual(obj["durationSeconds"] as? Double, 4.5)
        XCTAssertNil(obj["sentAt"], "a draft has no sentAt")
        let created = try XCTUnwrap(obj["createdAt"] as? String)
        XCTAssertNotNil(ISO8601DateFormatter().date(from: created), "createdAt stays internet-date-time: \(created)")

        FeedbackStore.markSent(item)
        obj = try json()
        let sent = try XCTUnwrap(obj["sentAt"] as? String)
        XCTAssertNotNil(ISO8601DateFormatter().date(from: sent))
    }
}
