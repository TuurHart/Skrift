import AVFoundation
import UIKit
import XCTest
@testable import SkriftMobile

/// Q94 / C70 / C124 / C12 / C238: the phone dates shared files from their NAMES, like the Mac.
/// The real Signal share of 5 clips + 1 picture: every file's modification date is the share
/// moment (so the old drain saw five equal clip dates), the picture has no EXIF — only its name
/// (`signal-2026-10-01-080349.jpeg`) puts it between clip 3 and clip 4. The share extension now
/// carries each file's original name and selection position; the drain runs the shared
/// `FilenameDate` ladder over them.
final class PhoneFilenameDateShareTests: XCTestCase {

    @MainActor
    private func cleanInbox() throws {
        guard let inbox = CaptureInbox.inboxURL else { throw XCTSkip("no App Group container in this test host") }
        try? FileManager.default.removeItem(at: inbox)
    }

    private func writeClip(seconds: Double) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("q94_\(UUID().uuidString).wav")
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

    private func jpeg() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).jpegData(withCompressionQuality: 0.8) { ctx in
            UIColor.green.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }

    private func local(_ h: Int, _ m: Int, _ s: Int) -> Date {
        var c = DateComponents(); c.year = 2026; c.month = 10; c.day = 1; c.hour = h; c.minute = m; c.second = s
        return Calendar.current.date(from: c)!
    }

    @MainActor
    private func cleanUp(_ memo: Memo?, clips: [URL]) {
        for m in memo?.metadata?.imageManifest ?? [] {
            try? FileManager.default.removeItem(at: AppPaths.recordingsDirectory.appendingPathComponent(m.filename))
        }
        if let f = memo?.audioURL { try? FileManager.default.removeItem(at: f) }
        for c in clips { try? FileManager.default.removeItem(at: c) }
        _ = MemoOpenBridge.shared.consume()
    }

    private let signalClipNames = [
        "signal-2026-10-01-07-44-33-101.m4a", "signal-2026-10-01-07-46-19-202.m4a",
        "signal-2026-10-01-07-56-11-303.m4a", "signal-2026-10-01-08-04-01-404.m4a",
        "signal-2026-10-01-08-06-25-505.m4a",
    ]

    /// The real Signal bundle: every clip's file date is the share moment, the picture has NO EXIF.
    @MainActor
    func testSignalNamedBundleDrainsWithThePictureBetweenClip3And4AndTheNoteDatedToClip1() async throws {
        try cleanInbox()
        let repo = NotesRepository(inMemory: true)
        let id = UUID()
        let clips = try (0..<5).map { _ in try writeClip(seconds: 2) }
        let shareMoment = ISO8601.string(from: Date())
        let entry = CaptureInboxEntry(
            id: id, type: "audio", url: nil, urlTitle: nil, text: nil,
            imageFileName: nil, mimeType: nil, annotationText: nil,
            significance: 0, sharedAt: shareMoment,
            audioFileNames: (0..<5).map { "audio_\(id.uuidString)_\($0).wav" },
            audioRecordedAts: Array(repeating: shareMoment, count: 5),
            imageFileNames: ["pic.jpg"],
            imageRecordedAts: [""],                       // Signal JPEG: no EXIF
            audioOriginalNames: signalClipNames,
            audioSelectionPositions: [0, 1, 2, 4, 5],
            imageOriginalNames: ["signal-2026-10-01-080349.jpeg"],
            imageSelectionPositions: [3])
        XCTAssertTrue(CaptureInbox.write(entry, audioFileURLs: clips, imageDatas: [jpeg()]))

        await CaptureInboxDrainer.drain(into: repo)

        let memos = repo.allMemos()
        XCTAssertEqual(memos.count, 1, "5 clips + 1 picture = ONE note")
        let memo = try XCTUnwrap(memos.first)
        defer { cleanUp(memo, clips: clips) }
        let manifest = try XCTUnwrap(memo.metadata?.imageManifest)
        XCTAssertEqual(manifest.count, 1)
        XCTAssertEqual(manifest[0].offsetSeconds, 6.0, accuracy: 0.3,
                       "by its filename time 08:03:49: after clips 1-3 (3 x 2 s), before clip 4")
        XCTAssertEqual(memo.recordedAt.timeIntervalSince1970, local(7, 44, 33).timeIntervalSince1970, accuracy: 1,
                       "C124: dated to the FIRST message (its filename date), not the share moment")
    }

    /// No dates anywhere (names carry none, no EXIF): the SELECTION position places the picture
    /// between the 3rd and 4th clip instead of pinning it to the top.
    @MainActor
    func testUndatedBundleFollowsSelectionPosition() async throws {
        try cleanInbox()
        let repo = NotesRepository(inMemory: true)
        let id = UUID()
        let clips = try (0..<5).map { _ in try writeClip(seconds: 2) }
        let entry = CaptureInboxEntry(
            id: id, type: "audio", url: nil, urlTitle: nil, text: nil,
            imageFileName: nil, mimeType: nil, annotationText: nil,
            significance: 0, sharedAt: ISO8601.string(from: Date()),
            audioFileNames: (0..<5).map { "audio_\(id.uuidString)_\($0).wav" },
            imageFileNames: ["pic.jpg"],
            audioOriginalNames: Array(repeating: "", count: 5),
            audioSelectionPositions: [0, 1, 2, 4, 5],
            imageOriginalNames: [""],
            imageSelectionPositions: [3])
        XCTAssertTrue(CaptureInbox.write(entry, audioFileURLs: clips, imageDatas: [jpeg()]))
        await CaptureInboxDrainer.drain(into: repo)
        let memo = try XCTUnwrap(repo.allMemos().first)
        defer { cleanUp(memo, clips: clips) }
        XCTAssertEqual(memo.metadata?.imageManifest?.first?.offsetSeconds ?? -1, 6.0, accuracy: 0.3)
    }

    /// An entry written by an older build (no names / positions) still decodes and keeps the old
    /// behaviour: dated by its file dates / EXIF, pictures first when undated.
    func testOldEntryWithoutNamesStillDecodes() throws {
        let json = """
        {"id":"\(UUID().uuidString)","type":"audio","significance":0,"sharedAt":"2026-10-01T08:00:00.000Z",
         "audioFileNames":["a.m4a"],"audioRecordedAts":["2026-10-01T07:00:00.000Z"]}
        """
        let e = try JSONDecoder().decode(CaptureInboxEntry.self, from: Data(json.utf8))
        XCTAssertNil(e.audioOriginalNames)
        XCTAssertNil(e.audioSelectionPositions)
        XCTAssertNil(e.imageOriginalNames)
        XCTAssertNil(e.imageSelectionPositions)
    }

    /// The pure plan: a dated picture lands between the clips, a name-less bundle keeps pictures
    /// first (legacy), and a missing clip file does not shift the aligned name arrays.
    @MainActor
    func testSharePlanDatesByTheLadder() throws {
        let u = (0..<4).map { URL(fileURLWithPath: "/tmp/q94-plan-\($0)") }
        let now = ISO8601.string(from: Date())
        let entry = CaptureInboxEntry(
            id: UUID(), type: "audio", url: nil, urlTitle: nil, text: nil,
            imageFileName: nil, mimeType: nil, annotationText: nil,
            significance: 0, sharedAt: now,
            audioFileNames: ["0", "1", "2"], audioRecordedAts: [now, now, now],
            imageFileNames: ["p"], imageRecordedAts: [""],
            audioOriginalNames: ["signal-2026-10-01-07-44-33-101.m4a", "signal-2026-10-01-07-46-19-202.m4a",
                                 "signal-2026-10-01-08-04-01-404.m4a"],
            imageOriginalNames: ["signal-2026-10-01-080349.jpeg"])
        // clip index 1 is missing on disk
        let plan = CaptureInboxDrainer.sharePlan(
            entry: entry, clips: [(0, u[0]), (2, u[2])], pictures: [(0, u[3])])
        let ordered = MixedBundle.ordered(plan.items)
        XCTAssertEqual(ordered.map(\.url), [u[0], u[3], u[2]], "picture between the clips by its name's time")
        XCTAssertEqual(plan.clipDates[u[2]]?.timeIntervalSince1970 ?? 0, local(8, 4, 1).timeIntervalSince1970, accuracy: 1)

        var bare = entry
        bare.audioOriginalNames = nil; bare.imageOriginalNames = nil
        bare.audioRecordedAts = nil
        let legacy = CaptureInboxDrainer.sharePlan(
            entry: bare, clips: [(0, u[0]), (2, u[2])], pictures: [(0, u[3])])
        XCTAssertEqual(MixedBundle.ordered(legacy.items).map(\.url), [u[3], u[0], u[2]], "undated, no positions: pictures first")
    }
}
