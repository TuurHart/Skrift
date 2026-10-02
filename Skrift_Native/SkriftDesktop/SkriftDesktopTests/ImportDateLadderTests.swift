import XCTest
import CoreGraphics
import ImageIO
import SwiftData

/// Q134 / C70 / C74 / R24: ONE date ladder at every door. The phone twin
/// (`SkriftMobileTests/ImportDateLadderTests.swift`) runs the SAME file names through the same
/// shared ladder and its own doors, so a Signal file dropped on the Mac and AirDropped to the
/// phone cannot date differently.
///
/// Ladder: embedded date → date in the filename → file date → now. A picture's embedded date is
/// its EXIF (C74). Dates within 2 s of each other are one moment and keep the arrival order.
@MainActor
final class ImportDateLadderTests: XCTestCase {

    // MARK: - fixtures (identical in the phone twin)

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

    // MARK: - the shared ladder (identical in the phone twin)

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

    // MARK: - the Mac doors

    private func makeContext() throws -> ModelContext {
        ModelContext(try ModelContainer(for: PipelineFile.self,
                                        configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    /// A drop of single files: each audio file is dated by its name, else its file date — the
    /// phone's Files / AirDrop door now gives the same answers (the twin's `importAudio` test).
    func testMacSingleAudioAndVideoDropsDateLikeThePhone() async throws {
        let urls = [try file(Self.signalAudio), try file(Self.whatsAppAudio),
                    try file(Self.undatedAudio, dated: Self.fileDay), try file(Self.whatsAppVideo)]
        let created = try await IngestService(outputDir: dir.appendingPathComponent("out"))
            .ingest(localURLs: urls, into: try makeContext())
        XCTAssertEqual(created.map(\.uploadedAt), [Self.local(2026, 4, 13, 18, 15, 24),
                                                   Self.local(2025, 12, 18, 18, 30, 44),
                                                   Self.fileDay,
                                                   Self.local(2025, 12, 18, 18, 30, 44)])
    }

    /// C74 on the Mac: a picture note reads EXIF, and is dated to the EARLIEST picture.
    func testMacPictureNoteReadsExif() async throws {
        let signal = try jpeg(Self.signalPicture, exif: nil)
        let exif = try jpeg(Self.exifPicture, exif: Self.exifStamp)
        let created = try await IngestService(outputDir: dir.appendingPathComponent("out"))
            .ingest(localURLs: [signal, exif], into: try makeContext())
        let pf = try XCTUnwrap(created.first)
        XCTAssertEqual(created.count, 1)
        XCTAssertEqual(pf.uploadedAt, Self.local(2026, 7, 4, 19, 21, 3), "EXIF date, the earliest of the two")
        XCTAssertEqual(IngestService.importDate(of: exif, kind: .picture), Self.local(2026, 7, 4, 19, 21, 3))
        XCTAssertEqual(IngestService.importDate(of: signal, kind: .picture), Self.local(2026, 10, 1, 8, 3, 49))
    }
}
