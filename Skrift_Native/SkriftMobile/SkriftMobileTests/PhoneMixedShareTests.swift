import AVFoundation
import UIKit
import XCTest
@testable import SkriftMobile

/// Q93 / C68 / C12 / C238: the phone-side twin of Q92. A share of voice clips + a picture is ONE
/// note; the picture sits between the clips by its time (`MixedBundle`, shared with the Mac), not
/// pinned at the top. Input = the ingress P3 shape: 5 Signal-style clips (2 s each) + 1 picture
/// whose time falls between clip 3 and clip 4.
final class PhoneMixedShareTests: XCTestCase {

    @MainActor
    private func cleanInbox() throws {
        guard let inbox = CaptureInbox.inboxURL else { throw XCTSkip("no App Group container in this test host") }
        try? FileManager.default.removeItem(at: inbox)
    }

    /// A real PCM `.wav`: `seconds` of tone, so the drain can measure the clip.
    private func writeClip(seconds: Double) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("p3_\(UUID().uuidString).wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let frames = AVAudioFrameCount(16_000 * seconds)
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buf.frameLength = frames
        let p = buf.floatChannelData![0]
        for i in 0..<Int(frames) { p[i] = 0.3 * sinf(2 * .pi * 440 * Float(i) / 16_000) }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buf)
        return url
    }

    private func at(_ h: Int, _ m: Int, _ s: Int) -> String {
        var c = DateComponents(); c.year = 2026; c.month = 10; c.day = 1; c.hour = h; c.minute = m; c.second = s
        return ISO8601.string(from: Calendar.current.date(from: c)!)
    }

    private func jpeg() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).jpegData(withCompressionQuality: 0.8) { ctx in
            UIColor.green.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }

    private func cleanUp(_ memo: Memo?, clips: [URL]) {
        for m in memo?.metadata?.imageManifest ?? [] {
            try? FileManager.default.removeItem(at: AppPaths.recordingsDirectory.appendingPathComponent(m.filename))
        }
        if let f = memo?.audioURL { try? FileManager.default.removeItem(at: f) }
        for c in clips { try? FileManager.default.removeItem(at: c) }
        _ = MemoOpenBridge.shared.consume()
    }

    /// P3: clips 07:44, 07:46, 07:56, 08:04, 08:06; the picture 08:03:49 → between clip 3 and 4.
    @MainActor
    func testP3ShareDrainsToOneNoteWithThePictureBetweenClip3And4() async throws {
        try cleanInbox()
        let repo = NotesRepository(inMemory: true)
        let id = UUID()
        let clips = try (0..<5).map { _ in try writeClip(seconds: 2) }
        let entry = CaptureInboxEntry(
            id: id, type: "audio", url: nil, urlTitle: nil, text: nil,
            imageFileName: nil, mimeType: nil, annotationText: nil,
            significance: 0, sharedAt: ISO8601.string(from: Date()),
            audioFileNames: (0..<5).map { "audio_\(id.uuidString)_\($0).wav" },
            audioRecordedAts: [at(7, 44, 33), at(7, 46, 19), at(7, 56, 11), at(8, 4, 1), at(8, 6, 25)],
            imageFileNames: ["pic.jpg"],
            imageRecordedAts: [at(8, 3, 49)])
        XCTAssertTrue(CaptureInbox.write(entry, audioFileURLs: clips, imageDatas: [jpeg()]))

        await CaptureInboxDrainer.drain(into: repo)

        let memos = repo.allMemos()
        XCTAssertEqual(memos.count, 1, "5 clips + 1 picture = ONE note")
        let memo = try XCTUnwrap(memos.first)
        defer { cleanUp(memo, clips: clips) }
        let manifest = try XCTUnwrap(memo.metadata?.imageManifest)
        XCTAssertEqual(manifest.count, 1)
        XCTAssertEqual(manifest[0].offsetSeconds, 6.0, accuracy: 0.3,
                       "after clips 1-3 (3 x 2 s), before clip 4 — not the top")

        // What the transcript pass then writes: one sentence per clip → the picture is its own
        // paragraph between sentence 3 and 4 (C12).
        let sentences = ["Alpha one.", "Bravo two.", "Charlie three.", "Delta four.", "Echo five."]
        var words: [WordTiming] = []
        for (i, s) in sentences.enumerated() {
            let t = Double(i) * 2 + 0.3
            for (j, w) in s.split(separator: " ").map(String.init).enumerated() {
                words.append(WordTiming(word: w, start: t + Double(j) * 0.5, end: t + Double(j) * 0.5 + 0.4))
            }
        }
        let body = BodyV2.committed(BodyV2.Input(text: sentences.joined(separator: " "), words: words,
                                                 manifest: manifest, source: .speech))
        let marker = try XCTUnwrap(body.range(of: "[[img_001]]"), "marker missing: \(body)")
        XCTAssertLessThan(try XCTUnwrap(body.range(of: "Charlie")).lowerBound, marker.lowerBound, body)
        XCTAssertLessThan(marker.lowerBound, try XCTUnwrap(body.range(of: "Delta")).lowerBound, body)
    }

    /// A picture dated BEFORE every clip stays at the top.
    @MainActor
    func testPictureDatedBeforeAllClipsStaysAtTheTop() async throws {
        try cleanInbox()
        let repo = NotesRepository(inMemory: true)
        let id = UUID()
        let clips = try (0..<2).map { _ in try writeClip(seconds: 2) }
        let entry = CaptureInboxEntry(
            id: id, type: "audio", url: nil, urlTitle: nil, text: nil,
            imageFileName: nil, mimeType: nil, annotationText: nil,
            significance: 0, sharedAt: ISO8601.string(from: Date()),
            audioFileNames: (0..<2).map { "audio_\(id.uuidString)_\($0).wav" },
            audioRecordedAts: [at(9, 0, 0), at(9, 5, 0)],
            imageFileNames: ["pic.jpg"], imageRecordedAts: [at(8, 0, 0)])
        XCTAssertTrue(CaptureInbox.write(entry, audioFileURLs: clips, imageDatas: [jpeg()]))
        await CaptureInboxDrainer.drain(into: repo)
        let memo = try XCTUnwrap(repo.allMemos().first)
        defer { cleanUp(memo, clips: clips) }
        XCTAssertEqual(memo.metadata?.imageManifest?.first?.offsetSeconds ?? -1, 0, accuracy: 0.01)
    }

    /// Two pictures (selection order: later first) land in TIME order with their own offsets, and
    /// the photo files are numbered in that order.
    @MainActor
    func testTwoPicturesGetTheirOwnOffsetsInTimeOrder() async throws {
        try cleanInbox()
        let repo = NotesRepository(inMemory: true)
        let id = UUID()
        let clips = try [2.0, 3.0].map { try writeClip(seconds: $0) }
        let entry = CaptureInboxEntry(
            id: id, type: "audio", url: nil, urlTitle: nil, text: nil,
            imageFileName: nil, mimeType: nil, annotationText: nil,
            significance: 0, sharedAt: ISO8601.string(from: Date()),
            audioFileNames: (0..<2).map { "audio_\(id.uuidString)_\($0).wav" },
            audioRecordedAts: [at(9, 0, 0), at(9, 10, 0)],
            imageFileNames: ["late.jpg", "mid.jpg"],
            imageRecordedAts: [at(9, 20, 0), at(9, 5, 0)])
        XCTAssertTrue(CaptureInbox.write(entry, audioFileURLs: clips, imageDatas: [jpeg(), jpeg()]))
        await CaptureInboxDrainer.drain(into: repo)
        let memo = try XCTUnwrap(repo.allMemos().first)
        defer { cleanUp(memo, clips: clips) }
        let m = try XCTUnwrap(memo.metadata?.imageManifest)
        XCTAssertEqual(m.map { ($0.offsetSeconds * 10).rounded() / 10 }, [2.0, 5.0],
                       "one after clip 1, one after clip 2")
        XCTAssertEqual(m.first?.filename, "photo_\(memo.id.uuidString)_001.jpg")
    }
}
