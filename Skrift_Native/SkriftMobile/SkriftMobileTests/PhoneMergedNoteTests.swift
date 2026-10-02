import AVFoundation
import UIKit
import XCTest
@testable import SkriftMobile

/// Q96 / C124 / C70 / D35, phone side: a shared multi-clip note is dated to its FIRST clip's
/// filename time, keeps each clip's start + own time in its metadata manifest, and the
/// transcript breaks a paragraph at every clip start, mid-sentence or not.
final class PhoneMergedNoteTests: XCTestCase {

    private func writeClip(seconds: Double) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("q96_\(UUID().uuidString).wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let frames = AVAudioFrameCount(16_000 * seconds)
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buf.frameLength = frames
        let p = buf.floatChannelData![0]
        for i in 0..<Int(frames) { p[i] = 0.3 * sinf(2 * .pi * 440 * Float(i) / 16_000) }
        try AVAudioFile(forWriting: url, settings: format.settings).write(from: buf)
        return url
    }

    private func local(_ h: Int, _ m: Int, _ s: Int) -> Date {
        var c = DateComponents(); c.year = 2026; c.month = 10; c.day = 1; c.hour = h; c.minute = m; c.second = s
        return Calendar.current.date(from: c)!
    }

    /// Three 2 s clips; the seeded transcript runs on with NO full stop and no pause (0.3 s a
    /// word), so only the manifest can break it: at 2.0 s (word 8) and 4.0 s (word 14).
    @MainActor
    func testMergedClipsKeepTheirManifestAndBreakAParagraphAtEachClip() async throws {
        let repo = NotesRepository(inMemory: true)
        let words = (1...20).map { "w\($0)" }.joined(separator: " ")
        let saver = MemoSaver(
            repository: repo,
            transcriber: SeededTranscriber(text: words),
            wordTimings: WordTimingsStore(directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("wt_\(UUID().uuidString)", isDirectory: true)),
            metadataProvider: MockMetadataService())
        let clips = try (0..<3).map { _ in try writeClip(seconds: 2) }
        let id = UUID()
        repo.insert(Memo(id: id, audioFilename: "memo_\(id.uuidString).m4a",
                         duration: 0, syncStatus: .waiting, transcriptStatus: .transcribing))
        let dates = [local(7, 44, 33), local(7, 46, 19), local(7, 56, 11)]

        let ok = await saver.importAudioClipsAsync(id: id, sources: clips, clipDates: dates)

        XCTAssertTrue(ok)
        let memo = try XCTUnwrap(repo.memo(id: id))
        defer { if let f = memo.audioURL { try? FileManager.default.removeItem(at: f) } }
        let manifest = try XCTUnwrap(memo.metadata?.clipManifest)
        XCTAssertEqual(manifest.count, 3)
        assertClose(manifest.map(\.startSeconds), [0, 2, 4], accuracy: 0.05)
        XCTAssertEqual(manifest.compactMap(\.recordedAt).count, 3, "each clip's own time is kept")
        let first = try XCTUnwrap(ISO8601.date(from: try XCTUnwrap(manifest[0].recordedAt)))
        XCTAssertEqual(first.timeIntervalSince1970, dates[0].timeIntervalSince1970, accuracy: 1)

        let body = try XCTUnwrap(memo.transcript)
        XCTAssertEqual(body.components(separatedBy: "\n\n").count, 3, "one paragraph per clip: \(body)")
        XCTAssertFalse(body.contains("07:4"), "no per-message time in the body (D35)")
    }

    /// The Signal share end to end: the drain dates the note to clip 1 AND hands the manifest on.
    @MainActor
    func testSignalShareKeepsFirstClipDateAndFiveClipManifest() async throws {
        guard let inbox = CaptureInbox.inboxURL else { throw XCTSkip("no App Group container in this test host") }
        try? FileManager.default.removeItem(at: inbox)
        let repo = NotesRepository(inMemory: true)
        let id = UUID()
        let clips = try (0..<5).map { _ in try writeClip(seconds: 2) }
        let shareMoment = ISO8601.string(from: Date())
        let names = ["signal-2026-10-01-07-44-33-101.m4a", "signal-2026-10-01-07-46-19-202.m4a",
                     "signal-2026-10-01-07-56-11-303.m4a", "signal-2026-10-01-08-04-01-404.m4a",
                     "signal-2026-10-01-08-06-25-505.m4a"]
        let entry = CaptureInboxEntry(
            id: id, type: "audio", url: nil, urlTitle: nil, text: nil,
            imageFileName: nil, mimeType: nil, annotationText: nil,
            significance: 0, sharedAt: shareMoment,
            audioFileNames: (0..<5).map { "audio_\(id.uuidString)_\($0).wav" },
            audioRecordedAts: Array(repeating: shareMoment, count: 5),
            audioOriginalNames: names, audioSelectionPositions: [0, 1, 2, 3, 4])
        XCTAssertTrue(CaptureInbox.write(entry, audioFileURLs: clips, imageDatas: []))

        await CaptureInboxDrainer.drain(into: repo)

        let memo = try XCTUnwrap(repo.allMemos().first)
        defer {
            if let f = memo.audioURL { try? FileManager.default.removeItem(at: f) }
            for c in clips { try? FileManager.default.removeItem(at: c) }
            _ = MemoOpenBridge.shared.consume()
        }
        XCTAssertEqual(repo.allMemos().count, 1)
        // The merge runs in a Task the drain does not await.
        for _ in 0..<100 where memo.metadata?.clipManifest == nil { try await Task.sleep(nanoseconds: 100_000_000) }
        let manifest = try XCTUnwrap(memo.metadata?.clipManifest, "the merged note carries its clip manifest")
        XCTAssertEqual(manifest.count, 5)
        XCTAssertEqual(manifest.map(\.filename).count, 5)
        XCTAssertEqual(MixedBundle.breakStarts(manifest).count, 4)
        let firstTime = try XCTUnwrap(ISO8601.date(from: try XCTUnwrap(manifest[0].recordedAt)))
        XCTAssertEqual(firstTime.timeIntervalSince1970, local(7, 44, 33).timeIntervalSince1970, accuracy: 1,
                       "each clip's own filename time, in the manifest")
        XCTAssertEqual(memo.recordedAt.timeIntervalSince1970, local(7, 44, 33).timeIntervalSince1970, accuracy: 1,
                       "C124: the note is dated to the FIRST message, not the share moment")
    }
}

private func assertClose(_ a: [Double], _ b: [Double], accuracy: Double,
                            file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(a.count, b.count, file: file, line: line)
    for (x, y) in zip(a, b) { XCTAssertEqual(x, y, accuracy: accuracy, file: file, line: line) }
}
