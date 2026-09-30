import XCTest
import SwiftData
@testable import SkriftMobile

/// Q73 (C112, C43, D151): a typed note records place, weather and daypart when it is
/// created (the first keystroke), like a voice recording. The capture runs
/// asynchronously and never blocks the keyboard; an empty discarded note leaves
/// nothing behind.
@MainActor
final class TypedNoteMetadataTests: XCTestCase {

    /// Counts calls; optionally suspends until `release()` so a test can prove the
    /// first keystroke did not wait on the capture.
    @MainActor
    final class GatedProvider: MetadataProviding {
        var calls = 0
        var gated: Bool
        var metadata: MemoMetadata
        private var waiter: CheckedContinuation<Void, Never>?

        init(gated: Bool = false, metadata: MemoMetadata) {
            self.gated = gated
            self.metadata = metadata
        }
        func capture() async -> MemoMetadata {
            calls += 1
            if gated { await withCheckedContinuation { waiter = $0 } }
            return metadata
        }
        func release() { gated = false; waiter?.resume(); waiter = nil }
    }

    private var captured: MemoMetadata {
        MemoMetadata(
            capturedAt: "2026-09-30T10:00:00.000Z",
            location: LocationInfo(latitude: 38.7, longitude: -9.1, placeName: "Lisbon"),
            weather: WeatherInfo(conditions: "Clear", temperature: 22, temperatureUnit: "C"),
            dayPeriod: .morning,
            steps: 800,
            tags: []
        )
    }

    /// The same fields a voice note gets from `MemoSaver.applyMetadata`.
    func testTypedNoteGetsTheMetadataAVoiceNoteGets() async {
        let repo = NotesRepository(inMemory: true)
        let provider = GatedProvider(metadata: captured)
        let draft = QuickNoteDraft(metadataProvider: provider)

        let memo = draft.edited(title: "", body: "T", context: repo.context)
        await draft.captureTask?.value

        XCTAssertEqual(provider.calls, 1)
        XCTAssertEqual(memo?.metadata?.location?.placeName, "Lisbon")
        XCTAssertEqual(memo?.metadata?.weather?.conditions, "Clear")
        XCTAssertEqual(memo?.metadata?.dayPeriod, .morning)
        XCTAssertEqual(memo?.metadata?.steps, 800)
        XCTAssertEqual(SourceKind.of(memo!), .typedNote, "the typed marker must survive the merge")
    }

    func testFirstKeystrokeDoesNotWaitForTheCapture() async {
        let repo = NotesRepository(inMemory: true)
        let provider = GatedProvider(gated: true, metadata: captured)
        let draft = QuickNoteDraft(metadataProvider: provider)

        let memo = draft.edited(title: "", body: "T", context: repo.context)
        XCTAssertNotNil(memo, "the note exists before the capture returns")
        XCTAssertNil(memo?.metadata?.location, "no place yet, the capture is still in flight")

        // Let the capture task start and suspend inside the provider.
        await Task.yield()
        provider.release()
        await draft.captureTask?.value
        XCTAssertEqual(memo?.metadata?.location?.placeName, "Lisbon")
    }

    func testCaptureStartsOncePerNoteNotPerKeystroke() async {
        let repo = NotesRepository(inMemory: true)
        let provider = GatedProvider(metadata: captured)
        let draft = QuickNoteDraft(metadataProvider: provider)
        draft.edited(title: "", body: "a", context: repo.context)
        draft.edited(title: "", body: "ab", context: repo.context)
        draft.edited(title: "T", body: "ab", context: repo.context)
        await draft.captureTask?.value
        XCTAssertEqual(provider.calls, 1)
    }

    func testUntouchedNoteCapturesNothingAndLeavesNoMemo() async {
        let repo = NotesRepository(inMemory: true)
        let provider = GatedProvider(metadata: captured)
        let draft = QuickNoteDraft(metadataProvider: provider)

        draft.edited(title: "", body: "", context: repo.context)
        draft.leave(context: repo.context)
        await Task.yield()

        XCTAssertEqual(provider.calls, 0, "no keystroke, no capture")
        XCTAssertNil(draft.captureTask)
        XCTAssertEqual((try? repo.context.fetch(FetchDescriptor<Memo>()))?.count, 0)
    }

    func testTypedThenEmptiedNoteIsDiscardedAndALateCaptureResurrectsNothing() async {
        let repo = NotesRepository(inMemory: true)
        let provider = GatedProvider(gated: true, metadata: captured)
        let draft = QuickNoteDraft(metadataProvider: provider)

        draft.edited(title: "", body: "x", context: repo.context)
        let task = draft.captureTask
        draft.edited(title: "", body: "", context: repo.context)
        draft.leave(context: repo.context)          // discards the empty note
        provider.release()                          // the capture lands after the discard
        await task?.value
        await Task.yield()

        XCTAssertEqual((try? repo.context.fetch(FetchDescriptor<Memo>()))?.count, 0,
                       "a late capture must not bring a discarded note back")
    }

    func testMergeKeepsTypedMarkerAndPictures() throws {
        let repo = NotesRepository(inMemory: true)
        let memo = try Memo.newTyped(into: repo.context)
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(memo.metadataData)) as? [String: Any])
        raw["imageManifest"] = [["filename": "img_001.jpg", "offsetSeconds": 0]]
        memo.metadataData = try JSONSerialization.data(withJSONObject: raw)

        memo.mergeCapturedMetadata(captured)

        XCTAssertEqual(SourceKind.of(memo), .typedNote)
        XCTAssertEqual(memo.metadata?.location?.placeName, "Lisbon")
        XCTAssertEqual(memo.metadata?.imageManifest?.count, 1)
    }
}
