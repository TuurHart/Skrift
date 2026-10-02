import XCTest
import SwiftData
import AVFoundation
import CoreMedia
import CoreVideo

/// Q137 / C199 / C202 / C77: what an import skipped or failed is REPORTED, with the reason,
/// on the Mac. The phone twin (`SkriftMobileTests/ImportReportTests.swift`) carries the same
/// pure-report table against `ImportReport` and the `AppURLHandler` door.
final class ImportReportTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: PipelineFile.self, configurations: config)
        return ModelContext(container)
    }

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - The shared report (identical on both apps)

    func testHeadlineAndLines() {
        var r = ImportReport(created: 2)
        XCTAssertFalse(r.hasProblems)
        XCTAssertNil(r.banner, "a clean import shows nothing: the new notes are the confirmation")
        XCTAssertEqual(r.headline, "Imported 2 notes")
        r.addSkipped("a.zip", "Skrift does not take .zip files")
        r.addFailed("v.mov", ImportReport.noAudioTrack)
        XCTAssertEqual(r.headline, "Imported 2 notes · skipped 1 · failed 1")
        XCTAssertEqual(r.bannerLines(), ["v.mov: Video had no audio track",
                                         "a.zip: Skrift does not take .zip files"], "failures first")
        XCTAssertNotNil(r.banner)
    }

    func testBannerLinesAreCapped() {
        var r = ImportReport()
        for i in 0..<7 { r.addSkipped("f\(i).zip", "no") }
        XCTAssertEqual(r.bannerLines(limit: 4).count, 5)
        XCTAssertEqual(r.bannerLines(limit: 4).last, "and 3 more")
        XCTAssertEqual(ImportReport().headline, "Nothing imported")
    }

    func testSkipReasonFollowsTheKind() {
        XCTAssertEqual(ImportReport.skipReason(forName: "x.zip", onMac: true), "Skrift does not take .zip files")
        XCTAssertEqual(ImportReport.skipReason(forName: "x", onMac: true),
                       "Skrift does not take files without an extension")
        XCTAssertEqual(ImportReport.skipReason(forName: "x.epub", onMac: true), ImportReport.book)
        XCTAssertEqual(ImportReport.skipReason(forName: "x.pdf", onMac: true), ImportReport.pdfNotOnMac)
    }

    func testMergeAddsEverything() {
        var a = ImportReport(created: 1)
        var b = ImportReport(created: 2)
        b.addSkipped("s", "r")
        a.merge(b)
        XCTAssertEqual(a.created, 3)
        XCTAssertEqual(a.skipped.count, 1)
    }

    // MARK: - Mac ingest

    /// C202: a video with no audio track makes a visible FAILED note named "Video had no audio
    /// track" (the phone's wording), and the report lists it as failed, not as made.
    func testSilentVideoBecomesAFailedNote() async throws {
        let work = try tempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let video = work.appendingPathComponent("silent.mov")
        try makeSilentVideo(at: video)

        let report = try await IngestService(outputDir: work.appendingPathComponent("out"))
            .ingestReport(localURLs: [video], into: try makeContext())

        XCTAssertEqual(report.created.count, 1, "a row exists (it used to throw and create none)")
        let pf = try XCTUnwrap(report.created.first)
        XCTAssertEqual(pf.transcribeStatus, .error)
        XCTAssertEqual(pf.enhancedTitle, "Video had no audio track")
        XCTAssertEqual(pf.mediaSource, "video", "still a video: keeps the video glyph")
        XCTAssertTrue(IngestService.isFailedImport(pf))

        let shown = report.importReport
        XCTAssertEqual(shown.created, 0, "a failed note is not a made note")
        XCTAssertEqual(shown.failed, [.init(name: "silent.mov", reason: "Video had no audio track")])
        XCTAssertTrue(shown.skipped.isEmpty)
    }

    /// C77 / D19: a file the Mac refuses is named with its reason; a vanished one says so.
    func testSkippedFilesCarryReasons() async throws {
        let work = try tempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let zip = work.appendingPathComponent("archive.zip")
        try Data([0, 1]).write(to: zip)
        let pdf = work.appendingPathComponent("contract.pdf")
        try Data("%PDF-1.4".utf8).write(to: pdf)
        let gone = work.appendingPathComponent("vanished.m4a")

        let report = try await IngestService(outputDir: work.appendingPathComponent("out"))
            .ingestReport(localURLs: [zip, pdf, gone], into: try makeContext())
        let shown = report.importReport
        XCTAssertEqual(shown.skipped.map(\.name), ["archive.zip", "contract.pdf", "vanished.m4a"])
        XCTAssertEqual(shown.skipped.map(\.reason), ["Skrift does not take .zip files",
                                                     ImportReport.pdfNotOnMac, ImportReport.vanished])
    }

    /// A dropped folder: the pictures (and a stray .txt) inside it are REPORTED, the notes and
    /// clips inside it are made. Subfolders (an Apple Notes `Attachments/`) stay quiet.
    func testFolderOfPicturesIsReportedNotIgnored() async throws {
        let work = try tempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let folder = work.appendingPathComponent("export", isDirectory: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Attachments"),
                                                withIntermediateDirectories: true)
        try Data("# Hello\nbody".utf8).write(to: folder.appendingPathComponent("note.md"))
        try Data("clutter".utf8).write(to: folder.appendingPathComponent("stray.txt"))
        try Data([1, 2, 3]).write(to: folder.appendingPathComponent("photo1.jpg"))
        try Data([1, 2, 3]).write(to: folder.appendingPathComponent("photo2.png"))
        try Data("%PDF".utf8).write(to: folder.appendingPathComponent("scan.pdf"))
        try Data([9]).write(to: folder.appendingPathComponent(".DS_Store"))

        let report = try await IngestService(outputDir: work.appendingPathComponent("out"))
            .ingestReport(localURLs: [folder], into: try makeContext())

        XCTAssertEqual(report.created.count, 1, "the .md note is made")
        let shown = report.importReport
        XCTAssertEqual(shown.created, 1)
        XCTAssertEqual(Set(shown.skipped.map(\.name)), ["photo1.jpg", "photo2.png", "scan.pdf", "stray.txt"])
        XCTAssertEqual(shown.skipped.first { $0.name == "photo1.jpg" }?.reason, ImportReport.pictureInFolder)
        XCTAssertEqual(shown.skipped.first { $0.name == "scan.pdf" }?.reason, ImportReport.pdfNotOnMac)
        XCTAssertEqual(shown.skipped.first { $0.name == "stray.txt" }?.reason, ImportReport.textInFolder)
    }

    /// The arrival path hands the same report to the list banner.
    @MainActor
    func testArrivalPathDeliversTheReport() async throws {
        let work = try tempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let zip = work.appendingPathComponent("archive.zip")
        try Data([0, 1]).write(to: zip)
        var got: ImportReport?
        _ = try await ArrivalPath.run(
            urls: [zip], asRecording: false, into: try makeContext(), cloudContext: nil,
            hooks: .inert,
            service: IngestService(outputDir: work.appendingPathComponent("out")),
            onReport: { got = $0 })
        XCTAssertEqual(got?.skipped.map(\.name), ["archive.zip"])
        XCTAssertNotNil(got?.banner)
    }

    // MARK: - A video with a picture track and no audio

    private func makeSilentVideo(at url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64])
        input.expectsMediaDataInRealTime = false
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
            kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 64]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attrs)
        XCTAssertTrue(writer.canAdd(input)); writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32ARGB, attrs as CFDictionary, &pb)
        if let pb {
            CVPixelBufferLockBaseAddress(pb, [])
            if let base = CVPixelBufferGetBaseAddress(pb) {
                memset(base, 0x7F, CVPixelBufferGetBytesPerRow(pb) * CVPixelBufferGetHeight(pb))
            }
            CVPixelBufferUnlockBaseAddress(pb, [])
            for i in 0..<30 {
                while !input.isReadyForMoreMediaData { usleep(1_000) }
                adaptor.append(pb, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: 30))
            }
        }
        input.markAsFinished()
        let done = expectation(description: "writer finish")
        writer.finishWriting { done.fulfill() }
        wait(for: [done], timeout: 10)
        XCTAssertEqual(writer.status, .completed, "video writer failed: \(String(describing: writer.error))")
    }
}
