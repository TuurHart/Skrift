import XCTest
@testable import SkriftMobile

/// Q511: the iPad's export v2 input (`ObsidianPublisher.v2Note`), built from the memo the way the
/// Mac builds it from its row: the recording's day (C64), created and duration (D12), whether he
/// typed the title (C130), each picture's OCR (R38). The publisher calls v2 only once
/// `ExportV2.isLive` is on (Q436).
final class ExportV2PhoneInputsTests: XCTestCase {

    private func memo(title: String?) -> Memo {
        let m = Memo(audioFilename: "memo.m4a", duration: 41.6,
                     recordedAt: Date(timeIntervalSince1970: 1_789_000_000),
                     title: title, transcript: "Price board. [[img_001]] Went up.")
        m.createdAt = Date(timeIntervalSince1970: 1_789_000_100)
        var meta = MemoMetadata()
        meta.imageManifest = [ImageManifestEntry(filename: "photo_001.jpg", offsetSeconds: 2, text: "GREY BODY €18")]
        m.metadata = meta
        return m
    }

    func testTheMemoFeedsEveryV2Input() {
        let m = memo(title: "Price board")
        let n = ObsidianPublisher.v2Note(m, people: [], author: "Tiuri", enhancement: nil, linkStems: [:],
                                         title: "Price board")
        XCTAssertTrue(n.heGaveTitle)
        XCTAssertEqual(n.createdAt, m.createdAt)
        XCTAssertEqual(n.duration, 41.6)
        XCTAssertEqual(n.pictureManifest, ["photo_001.jpg"])
        XCTAssertEqual(n.pictureText[1], "GREY BODY €18")
        let md = ExportV2.compile(n, profile: .obsidian, stem: "Price board").markdown
        XCTAssertTrue(md.contains("\ndate: \(MemoExporter.dateString(m.recordedAt))\n"), "one date rule (C64)\n\(md)")
        XCTAssertTrue(md.contains("\nduration: 42\n"), md)
        XCTAssertTrue(md.contains("![[Price board_001.jpg]]"), md)
    }

    func testNoTitleOfHisAndNoRecording() {
        let m = memo(title: nil)
        m.audioFilename = ""
        let n = ObsidianPublisher.v2Note(m, people: [], author: "", enhancement: nil, linkStems: [:], title: "Price board")
        XCTAssertFalse(n.heGaveTitle)
        XCTAssertNil(n.duration, "a typed note has no recording")
        XCTAssertFalse(ExportV2.compile(n, profile: .portfolio, stem: "s").markdown.contains("title:"))
    }

    func testTheSwapSwitchIsOff() {
        XCTAssertFalse(ExportV2.isLive)
    }
}
