import XCTest
import CoreGraphics
import ImageIO
@testable import SkriftMobile

/// Q134 / C70 / C74 / R24: ONE date ladder at every door. The Mac twin
/// (`SkriftDesktopTests/ImportDateLadderTests.swift`) runs the SAME file names through the same
/// shared ladder and its own doors, so a Signal file dropped on the Mac and AirDropped to the
/// phone cannot date differently.
///
/// Ladder: embedded date → date in the filename → file date → now. A picture's embedded date is
/// its EXIF (C74). Dates within 2 s of each other are one moment and keep the arrival order.
@MainActor
final class ImportDateLadderTests: XCTestCase {

    // MARK: - fixtures (identical in the Mac twin)

    static let signalAudio = "signal-2026-04-13-18-15-24-552.aac"
    static let whatsAppAudio = "WhatsApp Audio 2025-12-18 at 18.30.44.opus"
    static let undatedAudio = "New Recording 22.m4a"
    static let whatsAppVideo = "WhatsApp Video 2025-12-18 at 18.30.44.mp4"
    static let signalPicture = "signal-2026-10-01-080349.jpeg"
    static let exifPicture = "IMG_0042.jpg"
    static let exifStamp = "2026:07:04 19:21:03"
    /// The undated file's own date on disk.
    static let fileDay = local(2024, 2, 29, 9, 15, 0)

    static func local(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int) -> Date {
        var c = DateComponents(); c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi; c.second = s
        return Calendar.current.date(from: c)!
    }

    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("q134_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    /// A file whose content does not matter (the date comes from its name or its disk date).
    private func file(_ name: String, dated: Date? = nil) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try Data([0, 1, 2, 3]).write(to: url)
        if let dated {
            try FileManager.default.setAttributes([.creationDate: dated, .modificationDate: dated],
                                                  ofItemAtPath: url.path)
        }
        return url
    }

    private func jpeg(_ name: String, exif: String?) throws -> URL {
        let url = dir.appendingPathComponent(name)
        let ctx = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.3, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let sink = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil)!
        let props: [CFString: Any] = exif.map {
            [kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: $0]]
        } ?? [:]
        CGImageDestinationAddImage(sink, ctx.makeImage()!, props as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(sink))
        return url
    }

    // MARK: - the shared ladder (identical in the Mac twin)

    func testFilenameRungDatesMessagingFiles() throws {
        XCTAssertEqual(FilenameDate.ladder(embedded: nil, fileAt: try file(Self.signalAudio)),
                       Self.local(2026, 4, 13, 18, 15, 24))
        XCTAssertEqual(FilenameDate.ladder(embedded: nil, fileAt: try file(Self.whatsAppAudio)),
                       Self.local(2025, 12, 18, 18, 30, 44))
    }

    func testUndatedNameFallsToTheFileDate() throws {
        let url = try file(Self.undatedAudio, dated: Self.fileDay)
        XCTAssertEqual(FilenameDate.ladder(embedded: nil, fileAt: url), Self.fileDay)
    }

    func testFileDateIsTheEarlierOfCreationAndModification() throws {
        let url = try file(Self.undatedAudio)
        let older = Self.fileDay, newer = Self.local(2025, 1, 1, 12, 0, 0)
        try FileManager.default.setAttributes([.creationDate: newer, .modificationDate: older], ofItemAtPath: url.path)
        XCTAssertEqual(FilenameDate.fileDate(of: url), older)
    }

    func testEmbeddedBeatsTheFilename() throws {
        let embedded = Self.local(2026, 1, 2, 3, 4, 5)
        XCTAssertEqual(FilenameDate.ladder(embedded: embedded, fileAt: try file(Self.signalAudio)), embedded)
    }

    func testARenamedCopyDatesFromItsOriginalName() throws {
        let temp = try file("shared_\(UUID().uuidString).aac", dated: Self.fileDay)
        XCTAssertEqual(FilenameDate.ladder(embedded: nil, fileAt: temp, name: Self.signalAudio),
                       Self.local(2026, 4, 13, 18, 15, 24))
    }

    func testPictureLadderIsExifThenNameThenFileDate() throws {
        let exif = try jpeg(Self.exifPicture, exif: Self.exifStamp)
        XCTAssertEqual(ImageDates.exifDate(at: exif), Self.local(2026, 7, 4, 19, 21, 3))
        XCTAssertEqual(ImageDates.ladderDate(at: exif), Self.local(2026, 7, 4, 19, 21, 3))
        XCTAssertEqual(ImageDates.exifDate(from: try Data(contentsOf: exif)), Self.local(2026, 7, 4, 19, 21, 3),
                       "the bytes read and the file read agree")

        let signal = try jpeg(Self.signalPicture, exif: nil)
        XCTAssertNil(ImageDates.exifDate(at: signal), "a Signal JPEG carries no EXIF")
        XCTAssertEqual(ImageDates.ladderDate(at: signal), Self.local(2026, 10, 1, 8, 3, 49))

        let both = try jpeg("signal-2026-10-01-080412.jpeg", exif: Self.exifStamp)
        XCTAssertEqual(ImageDates.ladderDate(at: both), Self.local(2026, 7, 4, 19, 21, 3), "EXIF beats the name")

        let bare = try jpeg("IMG_0043.jpg", exif: nil)
        try FileManager.default.setAttributes([.creationDate: Self.fileDay, .modificationDate: Self.fileDay],
                                              ofItemAtPath: bare.path)
        XCTAssertEqual(ImageDates.ladderDate(at: bare), Self.fileDay)
    }

    func testDatesWithinTwoSecondsKeepTheArrivalOrder() {
        let t = Self.local(2026, 10, 1, 8, 0, 0)
        let a = URL(fileURLWithPath: "/tmp/a.m4a"), b = URL(fileURLWithPath: "/tmp/b.m4a"),
            c = URL(fileURLWithPath: "/tmp/c.jpeg")
        // WhatsApp stamps every temp copy at the share instant: 0.4 s / 1.5 s apart, out of order.
        let oneMoment: [MixedBundle.Item] = [.init(url: a, kind: .clip, date: t.addingTimeInterval(1.5)),
                                             .init(url: b, kind: .clip, date: t),
                                             .init(url: c, kind: .picture, date: t.addingTimeInterval(0.4))]
        XCTAssertEqual(MixedBundle.ordered(oneMoment).map(\.url), [a, b, c], "one moment → arrival order")
        XCTAssertEqual(FilenameDate.chronologicalOrder(oneMoment.map(\.date)), [0, 1, 2])

        let spread: [MixedBundle.Item] = [.init(url: a, kind: .clip, date: t.addingTimeInterval(60)),
                                          .init(url: b, kind: .clip, date: t),
                                          .init(url: c, kind: .picture, date: t.addingTimeInterval(30))]
        XCTAssertEqual(MixedBundle.ordered(spread).map(\.url), [b, c, a], "real times → time order")

        let undated: [MixedBundle.Item] = [.init(url: a, kind: .clip, date: t.addingTimeInterval(60)),
                                           .init(url: b, kind: .clip, date: nil)]
        XCTAssertEqual(MixedBundle.ordered(undated).map(\.url), [a, b], "one undated item → arrival order")
    }

    // MARK: - the phone doors

    private var imported: [URL] = []

    override func tearDown() {
        for u in imported { try? FileManager.default.removeItem(at: u) }
        imported = []
        super.tearDown()
    }

    private func saver(_ repo: NotesRepository) -> MemoSaver {
        MemoSaver(repository: repo, transcriber: SeededTranscriber(text: "unused"),
                  wordTimings: WordTimingsStore(directory: dir.appendingPathComponent("wt", isDirectory: true)),
                  metadataProvider: MockMetadataService())
    }

    /// R24 / capture-import-28: a Signal / WhatsApp file picked in Files or AirDropped (the
    /// `AppURLHandler` door passes no date) is dated from its NAME, else its file date — the
    /// Mac twin's `testMacSingleAudioAndVideoDropsDateLikeThePhone` gives the same answers.
    func testFilesAndAirDropAudioDateFromTheFilename() throws {
        let repo = NotesRepository(inMemory: true)
        let expected: [(String, Date?, Date)] = [
            (Self.signalAudio, nil, Self.local(2026, 4, 13, 18, 15, 24)),
            (Self.whatsAppAudio, nil, Self.local(2025, 12, 18, 18, 30, 44)),
            (Self.undatedAudio, Self.fileDay, Self.fileDay),
        ]
        for (name, onDisk, want) in expected {
            let id = try XCTUnwrap(saver(repo).importAudio(from: try file(name, dated: onDisk)))
            if let m = repo.memo(id: id) {
                imported.append(AppPaths.recordingsDirectory.appendingPathComponent(m.audioFilename))
            }
            XCTAssertEqual(repo.memo(id: id)?.recordedAt, want, name)
        }
    }

    /// capture-import-22: phone video reads the filename and file date too (embedded → library
    /// date → name → file date → now). A junk container fails extraction but keeps the date.
    func testVideoDatesFromTheFilename() async throws {
        let repo = NotesRepository(inMemory: true)
        let id = UUID()
        repo.insert(Memo(id: id, audioFilename: "memo_\(id.uuidString).m4a",
                         recordedAt: Date(), transcriptStatus: .transcribing))
        let ok = await saver(repo).processVideo(id: id, source: try file(Self.whatsAppVideo), fallbackDate: nil)
        XCTAssertFalse(ok, "junk bytes are no video")
        XCTAssertEqual(repo.memo(id: id)?.recordedAt, Self.local(2025, 12, 18, 18, 30, 44))
    }

    /// A supplied date (the PHAsset date / a share's ladder answer) still outranks the name.
    func testVideoLibraryDateOutranksTheName() async throws {
        let repo = NotesRepository(inMemory: true)
        let id = UUID()
        repo.insert(Memo(id: id, audioFilename: "memo_\(id.uuidString).m4a",
                         recordedAt: Date(), transcriptStatus: .transcribing))
        let library = Self.local(2023, 5, 6, 7, 8, 9)
        _ = await saver(repo).processVideo(id: id, source: try file(Self.whatsAppVideo), fallbackDate: library)
        XCTAssertEqual(repo.memo(id: id)?.recordedAt, library)
    }

    /// The share extension's clip order is the SAME shared rule as the Mac's `MixedBundle`.
    func testShareClipOrderIsTheSharedRule() {
        let t = Self.local(2026, 10, 1, 8, 0, 0)
        for dates in [[t.addingTimeInterval(1.5), t, t.addingTimeInterval(0.4)],
                      [t.addingTimeInterval(60), t, t.addingTimeInterval(30)],
                      [t, nil, t.addingTimeInterval(-60)]] as [[Date?]] {
            XCTAssertEqual(CaptureInbox.stableClipOrder(dates: dates), FilenameDate.chronologicalOrder(dates))
        }
    }
}
