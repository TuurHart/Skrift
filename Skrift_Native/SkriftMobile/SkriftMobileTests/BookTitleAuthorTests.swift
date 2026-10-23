import AVFoundation
import XCTest
@testable import SkriftMobile

/// Q498 (C297): an imported book's title never repeats its author. "Title — Author" with an
/// author byline becomes title "Title", the author in its own field.
final class BookTitleAuthorTests: XCTestCase {

    // MARK: - Pure rule

    func testDashAuthorSuffixIsDropped() {
        let r = AudiobookMetadataDefaults.resolve(title: "Sapiens \u{2014} Yuval Noah Harari",
                                                  author: "Yuval Noah Harari", filename: "x.m4b")
        XCTAssertEqual(r.title, "Sapiens")
        XCTAssertEqual(r.author, "Yuval Noah Harari")
        XCTAssertFalse(r.needsConfirmation)
    }

    func testEveryUsualSeparatorAndCase() {
        let a = "Ada Writer"
        for t in ["The Fixture \u{2014} Ada Writer", "The Fixture \u{2013} Ada Writer", "The Fixture - ada writer",
                  "The Fixture by Ada Writer", "The Fixture, by Ada Writer", "The Fixture, Ada Writer",
                  "Ada Writer - The Fixture", "Ada Writer: The Fixture", "The Fixture"] {
            XCTAssertEqual(AudiobookMetadataDefaults.titleWithoutAuthor(t, author: a), "The Fixture", t)
        }
    }

    func testTitlesThatOnlyMentionTheAuthorAreKept() {
        XCTAssertEqual(AudiobookMetadataDefaults.titleWithoutAuthor("Ada Writer", author: "Ada Writer"), "Ada Writer",
                       "never strip a title to nothing")
        XCTAssertEqual(AudiobookMetadataDefaults.titleWithoutAuthor("Letters to Ada Writer Fans", author: "Ada Writer"),
                       "Letters to Ada Writer Fans")
        XCTAssertEqual(AudiobookMetadataDefaults.titleWithoutAuthor("Star Wars \u{2014} A New Hope", author: ""),
                       "Star Wars \u{2014} A New Hope")
    }

    func testFilenameWithBylineTagYieldsTitleAndAuthor() {
        let r = AudiobookMetadataDefaults.resolve(title: nil, author: "Ada Writer",
                                                  filename: "The Fixture \u{2014} Ada Writer.m4a")
        XCTAssertEqual(r.title, "The Fixture")
        XCTAssertEqual(r.author, "Ada Writer")
    }

    func testUntaggedDashFilenamePrefillsBothFieldsForConfirmation() {
        let r = AudiobookMetadataDefaults.resolve(title: nil, author: nil,
                                                  filename: "The Fixture \u{2014} Ada Writer.m4a")
        XCTAssertEqual(r.title, "The Fixture")
        XCTAssertEqual(r.author, "Ada Writer")
        XCTAssertTrue(r.needsConfirmation, "a guessed author is shown for checking")
    }

    // MARK: - The real import

    func testImportedFileNamedTitleDashAuthorWithBylineTag() async throws {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("titleauthor_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: work) }
        let src = try await makeTagged(work.appendingPathComponent("The Fixture \u{2014} Ada Writer.m4a"),
                                       artist: "Ada Writer", scratch: work)

        let pending = try await AudiobookImporter.importBook(from: [src],
                                                             libraryDirectory: work.appendingPathComponent("library"))
        XCTAssertEqual(pending.book.title, "The Fixture")
        XCTAssertEqual(pending.book.author, "Ada Writer")
    }

    /// One second of silent AAC in an .m4a carrying only an artist tag.
    private func makeTagged(_ out: URL, artist: String, scratch: URL) async throws -> URL {
        let raw = scratch.appendingPathComponent("raw.m4a")
        do {
            let file = try AVAudioFile(forWriting: raw, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1,
            ])
            let buffer = AVAudioPCMBuffer(pcmFormat: AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!,
                                          frameCapacity: 44_100)!
            buffer.frameLength = 44_100
            try file.write(from: buffer)
        }
        let export = try XCTUnwrap(AVAssetExportSession(asset: AVURLAsset(url: raw),
                                                        presetName: AVAssetExportPresetPassthrough))
        export.outputURL = out
        export.outputFileType = .m4a
        let item = AVMutableMetadataItem()
        item.identifier = .iTunesMetadataArtist
        item.value = artist as NSString
        export.metadata = [item]
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            export.exportAsynchronously { c.resume() }
        }
        XCTAssertEqual(export.status, .completed, "\(String(describing: export.error))")
        return out
    }
}
