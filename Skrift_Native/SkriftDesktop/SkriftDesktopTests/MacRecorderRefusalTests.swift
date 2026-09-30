import AVFoundation
import XCTest
import SwiftData

/// The refusal mapping — why a take couldn't start, and whether the user is given a way out.
///
/// Written after the 2026-07-28 regression, where Record "did nothing" for a whole session:
/// `-miccheck` eventually read `DENIED`, meaning the app had been refusing correctly the
/// entire time while offering nothing but a sentence to read. The distinction these tests
/// pin is the one that costs an afternoon when it's wrong: a denial is a DEAD END that macOS
/// will never re-prompt for, so it must carry a button to Settings, whereas an absent
/// microphone is fixed by plugging one in and Settings would be a red herring.
final class MacRecorderRefusalTests: XCTestCase {

    // MARK: - which statuses are a dead end

    func testDeniedIsADeadEndThatOffersSettings() {
        let refusal = MacRecorder.refusal(for: .denied)
        XCTAssertEqual(refusal, .permissionDenied)
        XCTAssertTrue(refusal.fixedInPrivacySettings,
                      "a denial is only clearable in Settings — without the button the user has nowhere to go")
    }

    func testRestrictedIsADeadEndToo() {
        let refusal = MacRecorder.refusal(for: .restricted)
        XCTAssertEqual(refusal, .permissionRestricted)
        XCTAssertTrue(refusal.fixedInPrivacySettings)
    }

    /// Reaching the mapping at all means access was withheld, so `.notDetermined` here is a
    /// declined (or un-presentable) prompt, not a pending one. Reporting it as anything
    /// softer sends the user waiting for a dialog macOS will never show — exactly how a CLI
    /// `-recordcheck` run poisoned this grant in the first place.
    func testNotDeterminedAfterAFailedRequestReadsAsDenied() {
        XCTAssertEqual(MacRecorder.refusal(for: .notDetermined), .permissionDenied)
    }

    // MARK: - what Settings can't fix

    func testHardwareAndEngineFailuresDoNotSendTheUserToSettings() {
        XCTAssertFalse(MacRecorder.Refusal.noInputDevice.fixedInPrivacySettings,
                       "no mic is fixed by plugging one in; Settings would be a wild goose chase")
        XCTAssertFalse(MacRecorder.Refusal.noUsableFormat.fixedInPrivacySettings,
                       "a 0 Hz format is a Sound ▸ Input problem, not a Privacy one")
        XCTAssertFalse(MacRecorder.Refusal.engineFailed("boom").fixedInPrivacySettings)
    }

    // MARK: - every refusal says something, and says it differently

    func testEveryRefusalCarriesADistinctNonEmptyMessage() {
        // The full 7-case set, not just the ones that don't need a device name — the two
        // device-naming cases are exactly where "no mic" and "no permission" got confused.
        let all: [MacRecorder.Refusal] = [
            .noInputDevice, .permissionDenied, .permissionRestricted,
            .noUsableFormat, .engineFailed("the engine said no"),
            .nothingCaptured("Chonky pods"), .recordedSilence("Chonky pods"),
        ]
        for refusal in all {
            XCTAssertFalse(refusal.message.isEmpty, "\(refusal) must explain itself")
        }
        XCTAssertEqual(Set(all.map(\.message)).count, all.count,
                       "two refusals reading the same is how 'no mic' and 'no permission' got confused")
    }

    func testEngineFailureQuotesTheUnderlyingReason() {
        XCTAssertTrue(MacRecorder.Refusal.engineFailed("kAudioUnitErr_TooManyFramesToProcess")
            .message.contains("kAudioUnitErr_TooManyFramesToProcess"),
                      "CoreAudio's own words are the only diagnostic there is here")
    }

    /// The denial message must NOT promise a prompt. macOS won't show one, and telling the
    /// user to "allow it when asked" is the difference between a fixable state and a bug
    /// report.
    func testDenialMessageSaysMacOSWillNotAskAgain() {
        let message = MacRecorder.Refusal.permissionDenied.message
        XCTAssertTrue(message.contains("won't ask again"), "got: \(message)")
        XCTAssertTrue(message.contains("Microphone"), "it has to name the pane: \(message)")
    }

    func testPrivacySettingsDeepLinkIsAUsableURL() {
        let url = URL(string: MacRecorder.Refusal.privacySettingsURL)
        XCTAssertNotNil(url, "an unparseable deep link makes the Open Settings button a no-op")
        XCTAssertEqual(url?.scheme, "x-apple.systempreferences")
    }
}

/// The rating floor, from the angle the 2026-07-28 harness run exposed: the CAPTURE path is not
/// the only thing that authors Memos. `MemoCloudReconciler`'s sweep calls `backfill` over every
/// local row that lacks one, on its own schedule. It won that race against a real Mac take and
/// rated it 0.1. D159 (2026-09-30) removed the floor altogether, so nobody can win it.
final class LocalRecordingFloorTests: XCTestCase {

    private func cloudContext() throws -> ModelContext {
        ModelContext(try ModelContainer(for: Memo.self, MemoAsset.self,
                                        configurations: ModelConfiguration(isStoredInMemoryOnly: true,
                                                                           cloudKitDatabase: .none)))
    }

    private func take() -> PipelineFile {
        let pf = PipelineFile(id: UUID().uuidString, filename: "memo_x.m4a",
                              path: tempAudio().path, sourceType: .audio)
        pf.isLocalRecording = true
        return pf
    }

    private func tempAudio() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        try? Data(repeating: 0, count: 512).write(to: url)
        return url
    }

    /// THE regression: the sweep's own entry point, with its own defaults, on a real take.
    func testTheReconcileSweepCannotFloorARecording() throws {
        let cloud = try cloudContext()
        let pf = take()

        XCTAssertEqual(try MacMemoAuthor.backfill(files: [pf], into: cloud), 1)

        let memo = try XCTUnwrap(try cloud.fetch(FetchDescriptor<Memo>()).first)
        XCTAssertEqual(memo.significance, 0,
                       "whoever authors a take first, it stays unrated — the rating is consent")
    }

    /// An import no longer floors either (D159): the sweep authors it unrated like a take.
    func testAnImportIsAuthoredUnratedToo() throws {
        let cloud = try cloudContext()
        let pf = PipelineFile(id: UUID().uuidString, filename: "dropped.m4a",
                              path: tempAudio().path, sourceType: .audio)
        XCTAssertEqual(try MacMemoAuthor.backfill(files: [pf], into: cloud), 1)
        XCTAssertEqual(try cloud.fetch(FetchDescriptor<Memo>()).first?.significance, 0)
    }

    /// A rating the user actually gave survives either way — the flag governs the FLOOR, and
    /// a judged note is judged whatever door it came through.
    func testARatedRecordingKeepsItsRating() throws {
        let cloud = try cloudContext()
        let pf = take()
        pf.significance = 0.8
        let memo = try MacMemoAuthor.author(for: pf, audioURL: nil, into: cloud)
        XCTAssertEqual(memo?.significance, 0.8)
    }

    func testAFreshPipelineFileIsNotARecordingUntilSaidOtherwise() {
        XCTAssertFalse(PipelineFile(id: UUID().uuidString, filename: "a.m4a").isLocalRecording,
                       "the default must be the plain-file behaviour — every other door relies on it")
    }
}

/// Which `Memo` a Mac-recorded file belongs to. The naming convention that works for every
/// PHONE memo is actively wrong here: a take's file is `memo_<uuid>.m4a` too, but that UUID
/// belongs to the audio file (`RecordingCore.filename()`), while the Memo is authored under
/// the row's `id`. Preferring the filename returns a UUID no Memo has, and every Mac→cloud
/// write silently no-ops — found 2026-07-28 when clearing a bad rating on a real take updated
/// the Mac and left the phone's copy at 0.1.
final class RecordingMemoIdentityTests: XCTestCase {

    private func cloudContext() throws -> ModelContext {
        ModelContext(try ModelContainer(for: Memo.self, MemoAsset.self, MemoEnhancement.self,
                                        configurations: ModelConfiguration(isStoredInMemoryOnly: true,
                                                                           cloudKitDatabase: .none)))
    }

    /// The exact shape of a Mac take: two DIFFERENT UUIDs, one in the id and one in the name.
    private func take() -> PipelineFile {
        PipelineFile(id: "11111111-1111-4111-8111-111111111111",
                     filename: "memo_22222222-2222-4222-8222-222222222222.m4a",
                     path: "/tmp/x.m4a", sourceType: .audio)
    }

    func testARecordingIsKeyedByItsRowIdNotItsFilename() {
        let pf = take()
        pf.isLocalRecording = true
        XCTAssertEqual(MacCloudWriteBack.memoID(for: pf), UUID(uuidString: pf.id),
                       "the filename's UUID names the audio file, not the Memo")
    }

    /// Unchanged for everything else: a phone-synced memo IS identified by its filename, and
    /// that path must not move.
    func testAPhoneMemoIsStillKeyedByItsFilename() {
        XCTAssertEqual(MacCloudWriteBack.memoID(for: take()),
                       UUID(uuidString: "22222222-2222-4222-8222-222222222222"))
    }

    /// The store-resolved lookup rescues the case no naming rule can: a take recorded BEFORE
    /// `isLocalRecording` existed, whose flag is false but whose Memo is under the row id.
    func testResolveFindsTheMemoOfAPreFlagRecording() throws {
        let ctx = try cloudContext()
        let pf = take()                                   // isLocalRecording == false
        let rowID = try XCTUnwrap(UUID(uuidString: pf.id))
        ctx.insert(Memo(id: rowID, audioFilename: pf.filename))
        try ctx.save()

        XCTAssertEqual(MacCloudWriteBack.resolve(for: pf, in: ctx)?.id, rowID,
                       "asking the store beats guessing from a name")
    }

    func testResolveStillFindsAPhoneMemoByFilename() throws {
        let ctx = try cloudContext()
        let pf = take()
        let fileID = try XCTUnwrap(UUID(uuidString: "22222222-2222-4222-8222-222222222222"))
        ctx.insert(Memo(id: fileID, audioFilename: pf.filename))
        try ctx.save()

        XCTAssertEqual(MacCloudWriteBack.resolve(for: pf, in: ctx)?.id, fileID)
    }

    /// A local-only file has no Memo either way — resolve must not invent one, or a write-back
    /// would orphan itself onto an unrelated note.
    func testResolveReturnsNilWhenNeitherCandidateExists() throws {
        XCTAssertNil(MacCloudWriteBack.resolve(for: take(), in: try cloudContext()))
    }

    /// The end of the chain that actually broke: the enhancement write-back for a Mac take.
    func testTheWriteBackReachesARecordingsMemo() throws {
        let ctx = try cloudContext()
        let pf = take()
        pf.isLocalRecording = true
        let rowID = try XCTUnwrap(UUID(uuidString: pf.id))
        ctx.insert(Memo(id: rowID, audioFilename: pf.filename))
        try ctx.save()
        pf.enhancedCopyedit = "polished on the Mac"

        let written = try MacCloudWriteBack.upsert(for: pf, into: ctx, deviceID: "mac-1")
        XCTAssertEqual(written?.memoID, rowID, "the Mac's polish must reach the take it polished")
    }
}

/// Which input a Mac take listens to — the phone's b119 policy, ported. The phone learned on
/// hardware that a Bluetooth mic is the one input that can be present, selected, and ASLEEP:
/// the dev Mac's default was "Chonky pods" (BT), awake for the first two takes ever recorded
/// and asleep for every click after — a live-looking transport fed by zero buffers.
final class InputPickTests: XCTestCase {

    private let usb = MacRecorder.InputDevice(id: 41, name: "USB PnP Audio Device", isBluetooth: false)
    private let pods = MacRecorder.InputDevice(id: 77, name: "Chonky pods", isBluetooth: true)

    /// THE regression shape: BT is the system default, a wired mic is right there.
    func testABluetoothDefaultIsPassedOverForAWiredMic() {
        XCTAssertEqual(MacRecorder.pickInput(from: [pods, usb], systemDefault: pods.id), usb,
                       "with Bluetooth around, record on the wired mic — b119, same lesson")
    }

    func testAWiredDefaultIsSimplyKept() {
        XCTAssertEqual(MacRecorder.pickInput(from: [pods, usb], systemDefault: usb.id), usb)
    }

    /// A Bluetooth-only Mac still records: a maybe-asleep mic beats no mic, and the
    /// stop-time verdict names it if it sleeps through the take.
    func testBluetoothIsUsedWhenItIsTheOnlyInput() {
        XCTAssertEqual(MacRecorder.pickInput(from: [pods], systemDefault: pods.id), pods)
    }

    /// An unknown/stale default id must not sink the pick — fall back to the first device.
    func testAMissingDefaultFallsBackToTheFirstDevice() {
        XCTAssertEqual(MacRecorder.pickInput(from: [usb, pods], systemDefault: nil), usb)
        XCTAssertEqual(MacRecorder.pickInput(from: [pods, usb], systemDefault: 9999), usb,
                       "first device is BT + a wired one exists → still prefer wired")
    }

    func testNoDevicesMeansNoPick() {
        XCTAssertNil(MacRecorder.pickInput(from: [], systemDefault: nil))
    }

    // ── the stop-time verdict's words ──

    /// A dead take must NAME its device — "check your settings" with no noun is what made
    /// two different failures read as the same dead button.
    func testDeadTakeRefusalsNameTheDeviceAndAreDistinct() {
        let nothing = MacRecorder.Refusal.nothingCaptured("Chonky pods")
        let silence = MacRecorder.Refusal.recordedSilence("Chonky pods")
        XCTAssertTrue(nothing.message.contains("Chonky pods"))
        XCTAssertTrue(silence.message.contains("Chonky pods"))
        XCTAssertNotEqual(nothing.message, silence.message)
        XCTAssertFalse(nothing.fixedInPrivacySettings, "a sleeping mic is not a Privacy problem")
        XCTAssertFalse(silence.fixedInPrivacySettings)
    }
}

/// The fail-fast rule (2026-07-28 AVCaptureSession rebuild, `LANES-2026-07-28/BRIEF_CAPTURE.md`
/// §6): a take must not sit there looking live while nothing arrives — 1.5s with no buffer at
/// all trips it. Expressed as a pure function of (elapsed, has a buffer arrived), so the rule
/// is provable without a running session, a Timer, or a real clock.
final class FailFastDecisionTests: XCTestCase {

    func testNoBufferAtOrPastTheDeadlineTrips() {
        XCTAssertTrue(MacRecorder.shouldFailFast(elapsedSinceStart: 1.5, hasReceivedBuffer: false))
        XCTAssertTrue(MacRecorder.shouldFailFast(elapsedSinceStart: 3.0, hasReceivedBuffer: false))
    }

    func testBeforeTheDeadlineDoesNotTripEvenWithoutABuffer() {
        XCTAssertFalse(MacRecorder.shouldFailFast(elapsedSinceStart: 1.0, hasReceivedBuffer: false),
                       "a device can legitimately take a moment to hand over its first buffer")
    }

    /// The other half of the rule: once ANY buffer has arrived, fail-fast never fires again —
    /// a take that goes quiet AFTER starting is `recordedSilence`/`nothingCaptured`-at-stop
    /// territory, not this timer's job.
    func testBuffersThenQuietDoesNotTripFailFast() {
        XCTAssertFalse(MacRecorder.shouldFailFast(elapsedSinceStart: 5.0, hasReceivedBuffer: true))
        XCTAssertFalse(MacRecorder.shouldFailFast(elapsedSinceStart: 1.5, hasReceivedBuffer: true))
    }
}

/// The first-buffer-opens-the-file rule (BRIEF_CAPTURE §2): the `AVAudioFile` a take writes to
/// is opened from the format the FIRST delivered buffer actually reports — never a value read
/// before the session started running. These tests exercise the exact mechanism `SampleSink`
/// uses (`RecordingCore.encoderSettings` + `AVAudioFile(forWriting:settings:commonFormat:
/// interleaved:)`), proving a buffer in that format is always accepted — the class of bug this
/// rule exists to make unrepresentable (a file opened for one format, fed another) can't occur
/// because the file is never opened until a real buffer's format is in hand.
final class FirstBufferFileRuleTests: XCTestCase {

    func testEncoderSettingsPreserveTheBuffersRateAndChannelCount() throws {
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000,
                                                 channels: 2, interleaved: false))
        let settings = RecordingCore.encoderSettings(for: format)
        XCTAssertEqual(settings[AVSampleRateKey] as? Double, 48000)
        XCTAssertEqual(settings[AVNumberOfChannelsKey] as? AVAudioChannelCount, 2)
    }

    /// The file must accept a buffer in EXACTLY the format it was opened with — proving the
    /// `commonFormat`/`interleaved` sourced from the first buffer, not a default, is what makes
    /// `write(from:)` succeed regardless of what shape the device happens to deliver.
    func testAnAudioFileOpenedFromABuffersFormatAcceptsThatSameFormat() throws {
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100,
                                                 channels: 1, interleaved: false))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: url) }

        let file = try AVAudioFile(forWriting: url, settings: RecordingCore.encoderSettings(for: format),
                                  commonFormat: format.commonFormat, interleaved: format.isInterleaved)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024))
        buffer.frameLength = 1024
        buffer.floatChannelData?[0].update(repeating: 0, count: 1024)   // deterministic silence, not uninitialized memory

        XCTAssertNoThrow(try file.write(from: buffer),
                         "a buffer in the file's own opening format must always be writable")
    }

    /// The mono case too — the common shape for a built-in or single-capsule USB mic, and the
    /// one where interleaved-vs-not is a non-issue, so it must be the simplest possible pass.
    func testMonoRoundTripAlsoPreservesRate() throws {
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000,
                                                 channels: 1, interleaved: false))
        let settings = RecordingCore.encoderSettings(for: format)
        XCTAssertEqual(settings[AVSampleRateKey] as? Double, 16000)
        XCTAssertEqual(settings[AVNumberOfChannelsKey] as? AVAudioChannelCount, 1)
    }
}
