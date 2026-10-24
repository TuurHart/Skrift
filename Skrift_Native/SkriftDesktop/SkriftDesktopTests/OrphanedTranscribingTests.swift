import XCTest
import SwiftData
import Foundation

/// Q409 (C264, C154, C97, C263, R75): a memo another device left `.transcribing` is adopted
/// once it has been quiet 30 minutes and its audio is present; a younger one stays untouched,
/// and a user-edited one is never re-transcribed.
@MainActor
final class OrphanedTranscribingTests: XCTestCase {

    private let mac = "MAC-DEVICE"
    private let gonephone = "GONE-PHONE"
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    private struct HelloTranscriber: Transcribing {
        func transcribe(audioURL: URL, imageManifest: [ImageManifestEntry]) async throws -> TranscriptionResult {
            XCTAssertTrue(FileManager.default.fileExists(atPath: audioURL.path), "the synced blob is written to disk first")
            return TranscriptionResult(text: "hello there", confidence: 0.92, durationMs: 1,
                                       wordTimings: [WordTiming(word: "hello", start: 0, end: 0.4),
                                                     WordTiming(word: "there", start: 0.4, end: 0.9)],
                                       markersInjected: false)
        }
    }

    private func cloudContext() throws -> ModelContext {
        let c = try ModelContainer(for: Memo.self, MemoAsset.self, MemoEnhancement.self,
                                   configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(c)
    }

    /// A memo the gone phone left `.transcribing`, quiet for `minutes`.
    @discardableResult
    private func seedOrphan(_ ctx: ModelContext, minutes: Double, userEdited: Bool = false,
                            audio: Bool = true, device: String? = nil) -> Memo {
        let created = now.addingTimeInterval(-minutes * 60)
        let memo = Memo(audioFilename: "memo_\(UUID().uuidString).m4a", recordedAt: created,
                        transcript: userEdited ? "my own words" : nil, transcriptStatus: .transcribing,
                        transcriptUserEdited: userEdited, createdAt: created,
                        recordingDeviceID: device ?? gonephone)
        ctx.insert(memo)
        if audio {
            ctx.insert(MemoAsset(memoID: memo.id, kind: MemoAsset.Kind.audio,
                                 filename: memo.audioFilename, blob: Data("AUDIO".utf8)))
        }
        return memo
    }

    private func plan(_ ctx: ModelContext) throws -> MacOrphanTranscription.Plan {
        let memos = try ctx.fetch(FetchDescriptor<Memo>())
        let assets = ReconcileV2.AssetIndex(ctx)
        return MacOrphanTranscription.plan(memos: memos,
                                           hasAudio: { assets.has($0, MemoAsset.Kind.audio, minBytes: 0) },
                                           thisDevice: mac, now: now)
    }

    // ── the shared rule ──

    func testSharedRuleAgesOnlyAnotherDevicesMemo() {
        let quiet31 = now.addingTimeInterval(-31 * 60), quiet5 = now.addingTimeInterval(-5 * 60)
        XCTAssertTrue(OrphanedTranscribing.mayRecover(recordingDeviceID: gonephone, quietSince: quiet31,
                                                      thisDevice: mac, now: now))
        XCTAssertFalse(OrphanedTranscribing.mayRecover(recordingDeviceID: gonephone, quietSince: quiet5,
                                                       thisDevice: mac, now: now),
                       "C97: another device's memo younger than 30 minutes is still in flight there")
        XCTAssertTrue(OrphanedTranscribing.mayRecover(recordingDeviceID: mac, quietSince: quiet5,
                                                      thisDevice: mac, now: now),
                      "this device's own memo is recoverable at once (no Task survives a relaunch)")
        XCTAssertEqual(OrphanedTranscribing.takeoverAge, 30 * 60, "C154: 30 minutes")
    }

    // ── the Mac sweep ──

    func testThirtyOneMinuteOrphanWithAudioIsAdopted() async throws {
        let ctx = try cloudContext()
        let orphan = seedOrphan(ctx, minutes: 31)
        try ctx.save()

        let p = try plan(ctx)
        XCTAssertEqual(p.rerun, [orphan.id])
        XCTAssertEqual(p.release, [])

        let landed = await MacOrphanTranscription.adopt(p.rerun, in: ctx, transcriber: HelloTranscriber(),
                                                        thisDevice: mac, now: { self.now })
        XCTAssertEqual(landed, 1)
        XCTAssertEqual(orphan.transcriptStatus, .done)
        XCTAssertEqual(orphan.transcript, "hello there")
        XCTAssertEqual(orphan.transcriptConfidence, 0.92)
        XCTAssertFalse(orphan.transcriptUserEdited)
        let id = orphan.id
        let wt = try ctx.fetch(FetchDescriptor<MemoAsset>(predicate: #Predicate { $0.memoID == id }))
            .first { $0.kind == MemoAsset.Kind.wordTimings }
        XCTAssertNotNil(wt, "the word timings ride along like a phone transcript's")
        XCTAssertTrue(MacOrphanTranscription.inFlight.isEmpty)
    }

    func testFiveMinuteOrphanIsNotAdopted() async throws {
        let ctx = try cloudContext()
        let young = seedOrphan(ctx, minutes: 5)
        try ctx.save()

        let p = try plan(ctx)
        XCTAssertEqual(p, MacOrphanTranscription.Plan(), "C97: still the recording device's")
        // Even asked directly, the Mac re-checks the age and leaves it alone.
        let landed = await MacOrphanTranscription.adopt([young.id], in: ctx, transcriber: HelloTranscriber(),
                                                        thisDevice: mac, now: { self.now })
        XCTAssertEqual(landed, 0)
        XCTAssertEqual(young.transcriptStatus, .transcribing)
        XCTAssertNil(young.transcript)
    }

    func testUserEditedOrphanIsNeverRetranscribed() async throws {
        let ctx = try cloudContext()
        let edited = seedOrphan(ctx, minutes: 31, userEdited: true)
        try ctx.save()

        let p = try plan(ctx)
        XCTAssertEqual(p.rerun, [], "C263: never re-transcribed")
        XCTAssertEqual(p.release, [edited.id])
        let landed = await MacOrphanTranscription.adopt([edited.id], in: ctx, transcriber: HelloTranscriber(),
                                                        thisDevice: mac, now: { self.now })
        XCTAssertEqual(landed, 0)
        XCTAssertEqual(edited.transcript, "my own words")

        try MacOrphanTranscription.release(p.release, in: ctx)
        XCTAssertEqual(edited.transcriptStatus, .done, "released from the spinner, words untouched")
        XCTAssertEqual(edited.transcript, "my own words")
    }

    func testOrphanWithoutAudioWaits() throws {
        let ctx = try cloudContext()
        seedOrphan(ctx, minutes: 31, audio: false)
        try ctx.save()
        XCTAssertEqual(try plan(ctx).rerun, [], "C154: only when its audio blob is present")
    }

    func testDoneMemoIsNeverTouched() throws {
        let ctx = try cloudContext()
        let memo = seedOrphan(ctx, minutes: 120)
        memo.transcriptStatus = .done
        memo.transcript = "finished"
        try ctx.save()
        XCTAssertEqual(try plan(ctx), MacOrphanTranscription.Plan())
    }
}
