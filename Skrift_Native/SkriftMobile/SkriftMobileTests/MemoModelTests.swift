import XCTest
import SwiftData
@testable import SkriftMobile

final class MemoModelTests: XCTestCase {

    func testMemoMetadataCodableRoundTrip() throws {
        let meta = MemoMetadata(
            capturedAt: "2026-06-06T10:00:00.000Z",
            location: LocationInfo(latitude: 1.5, longitude: -2.5, placeName: "Here"),
            weather: WeatherInfo(conditions: "Clear", temperature: 21, temperatureUnit: "C"),
            pressure: PressureInfo(hPa: 1013, trend: .steady),
            dayPeriod: .afternoon,
            daylight: DaylightInfo(sunrise: "06:30", sunset: "21:15", hoursOfLight: 14.75),
            steps: 4200,
            tags: ["a", "b"],
            photoFilename: nil,
            imageManifest: [ImageManifestEntry(filename: "photo_x_001.jpg", offsetSeconds: 12.5)]
        )
        let decoded = try JSONDecoder().decode(MemoMetadata.self, from: JSONEncoder().encode(meta))
        XCTAssertEqual(meta, decoded)
    }

    func testSharedContentRoundTrip() throws {
        let sc = SharedContent(type: .url, url: "https://example.com", urlTitle: "Example")
        let decoded = try JSONDecoder().decode(SharedContent.self, from: JSONEncoder().encode(sc))
        XCTAssertEqual(sc, decoded)
    }

    func testParseTagInputSplitsCommasTrimsAndDropsBlanks() {
        // Several tags in one entry; commas separate, spaces inside a tag survive.
        XCTAssertEqual(Memo.parseTagInput("work, big idea ,  #todo ,, "), ["work", "big idea", "todo"])
        // A single tag still works (back-compat with the old one-at-a-time alert).
        XCTAssertEqual(Memo.parseTagInput("  #solo "), ["solo"])
        // Empty / whitespace-only input yields nothing.
        XCTAssertEqual(Memo.parseTagInput("   "), [])
        XCTAssertEqual(Memo.parseTagInput(""), [])
    }

    func testWordTimingsSidecarRoundTrip() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("wt_\(UUID().uuidString)", isDirectory: true)
        let store = WordTimingsStore(directory: dir)
        let id = UUID()
        let timings = [
            WordTiming(word: "hello", start: 0, end: 0.5),
            WordTiming(word: "world", start: 0.5, end: 1.0),
        ]
        store.write(timings, for: id)
        XCTAssertEqual(store.load(for: id), timings)
        store.delete(for: id)
        XCTAssertNil(store.load(for: id))
    }

    @MainActor
    func testRepositoryInsertAndFetchSortedNewestFirst() {
        let repo = NotesRepository(inMemory: true)
        let now = Date()
        repo.insert(Memo(audioFilename: "memo_a.m4a", recordedAt: now.addingTimeInterval(-100)))
        repo.insert(Memo(audioFilename: "memo_b.m4a", recordedAt: now))
        repo.insert(Memo(audioFilename: "memo_c.m4a", recordedAt: now.addingTimeInterval(-200)))
        let memos = repo.allMemos()
        XCTAssertEqual(memos.count, 3)
        XCTAssertEqual(memos.first?.audioFilename, "memo_b.m4a")
        XCTAssertEqual(memos.last?.audioFilename, "memo_c.m4a")
    }

    @MainActor
    func testRepositoryLookupAndDelete() {
        let repo = NotesRepository(inMemory: true)
        let memo = Memo(audioFilename: "memo_x.m4a")
        repo.insert(memo)
        let id = memo.id
        XCTAssertNotNil(repo.memo(id: id))
        repo.delete(memo)
        XCTAssertNil(repo.memo(id: id))
    }

    @MainActor
    func testAudioURLResolution() {
        XCTAssertEqual(Memo(audioFilename: "memo_x.m4a").audioURL?.lastPathComponent, "memo_x.m4a")
        XCTAssertNil(Memo(audioFilename: "").audioURL)
    }

    // MARK: - Display helpers

    func testDisplayTitlePrefersTitleThenTranscript() {
        let titled = Memo(title: "My title", transcript: "first line\nsecond")
        XCTAssertEqual(titled.displayTitle, "My title")

        let untitled = Memo(transcript: "first line\nsecond")
        XCTAssertEqual(untitled.displayTitle, "first line")

        let empty = Memo()
        XCTAssertEqual(empty.displayTitle, "Voice note")

        // A blank/whitespace title falls through to the transcript.
        let blankTitle = Memo(title: "   ", transcript: "hi there")
        XCTAssertEqual(blankTitle.displayTitle, "hi there")
    }

    func testStatusKindNeverShowsSyncPill() {
        // CloudKit-only: there is NO per-memo sync pill regardless of significance
        // or syncStatus — sync is automatic and shown by the global iCloud chip.
        let phoneOnly = Memo(syncStatus: .waiting, transcriptStatus: .done, significance: 0)
        XCTAssertNil(phoneOnly.statusKind)

        let waiting = Memo(syncStatus: .waiting, transcriptStatus: .done, significance: 0.5)
        XCTAssertNil(waiting.statusKind)

        let synced = Memo(syncStatus: .synced, transcriptStatus: .done, significance: 0.5)
        XCTAssertNil(synced.statusKind)
    }

    func testStatusKindAlwaysShowsTranscriptStateRegardlessOfSignificance() {
        // Transcript states are informational and show even for phone-only memos.
        let transcribing = Memo(transcriptStatus: .transcribing, significance: 0)
        XCTAssertEqual(transcribing.statusKind, .transcribing)

        let failed = Memo(transcriptStatus: .failed, significance: 0)
        XCTAssertEqual(failed.statusKind, .error)
    }

    // MARK: - List thumbnail (visible-photo rule)

    private func manifest(_ filenames: String...) -> MemoMetadata {
        MemoMetadata(imageManifest: filenames.map { ImageManifestEntry(filename: $0, offsetSeconds: 0) })
    }

    func testThumbnailFollowsSurvivingMarkerAfterDeletes() {
        // The 2026-07-18 repro: photos in a recording, the first two deleted in
        // the editor — the manifest keeps all entries (markers are indexes into
        // it), so the thumb must follow the marker still in the body.
        let memo = Memo(transcript: "Only the last photo remains [[img_003]]",
                        transcriptStatus: .done, transcriptMarkersInjected: true)
        memo.metadata = manifest("a.jpg", "b.jpg", "c.jpg")
        XCTAssertEqual(memo.thumbnailPhotoFilename, "c.jpg")
    }

    func testThumbnailUsesBodyOrderNotManifestOrder() {
        let memo = Memo(transcript: "Intro [[img_002]] then [[img_001]]",
                        transcriptStatus: .done, transcriptMarkersInjected: true)
        memo.metadata = manifest("a.jpg", "b.jpg")
        XCTAssertEqual(memo.thumbnailPhotoFilename, "b.jpg")
    }

    func testThumbnailGoneWhenEveryMarkerDeleted() {
        let memo = Memo(transcript: "No photos left in this note",
                        transcriptStatus: .done, transcriptMarkersInjected: true)
        memo.metadata = manifest("a.jpg")
        XCTAssertNil(memo.thumbnailPhotoFilename)
    }

    func testThumbnailSkipsUnresolvableMarker() {
        let memo = Memo(transcript: "[[img_009]] junk survives [[img_001]]",
                        transcriptStatus: .done, transcriptMarkersInjected: true)
        memo.metadata = manifest("a.jpg")
        XCTAssertEqual(memo.thumbnailPhotoFilename, "a.jpg")
    }

    func testThumbnailPendingTranscriptionShowsFirstManifestEntry() {
        // Photo taken while recording: the body doesn't exist yet, the thumb
        // must not wait for the markers.
        let memo = Memo(transcriptStatus: .transcribing)
        memo.metadata = manifest("a.jpg", "b.jpg")
        XCTAssertEqual(memo.thumbnailPhotoFilename, "a.jpg")
    }

    func testThumbnailShareCaptureRendersOffManifest() {
        // C3 image captures stack manifest photos without body markers — the
        // marker rules must not strip their thumb.
        let memo = Memo.make(audioFilename: "",
                             sharedContent: SharedContent(type: .image))
        memo.metadata = manifest("shared.jpg")
        XCTAssertEqual(memo.thumbnailPhotoFilename, "shared.jpg")
    }

    func testThumbnailEditorPhotosWorkWithoutInjectedFlag() {
        // Editor-inserted photos never set transcriptMarkersInjected: the body
        // marker still drives the thumb, and a typed body whose photo was
        // deleted shows none.
        let with = Memo(transcript: "Typed note [[img_001]]", transcriptStatus: .done)
        with.metadata = manifest("a.jpg")
        XCTAssertEqual(with.thumbnailPhotoFilename, "a.jpg")

        let without = Memo(transcript: "Typed note, photo deleted", transcriptStatus: .done)
        without.metadata = manifest("a.jpg")
        XCTAssertNil(without.thumbnailPhotoFilename)
    }

    func testThumbnailNilWithoutManifest() {
        XCTAssertNil(Memo(transcript: "hello [[img_001]]").thumbnailPhotoFilename)
        XCTAssertNil(Memo().thumbnailPhotoFilename)
    }
}
