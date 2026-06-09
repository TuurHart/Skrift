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
        XCTAssertEqual(empty.displayTitle, "Voice memo")

        // A blank/whitespace title falls through to the transcript.
        let blankTitle = Memo(title: "   ", transcript: "hi there")
        XCTAssertEqual(blankTitle.displayTitle, "hi there")
    }

    func testStatusKindHidesSyncPillWhenInsignificant() {
        // significance 0 → phone-only → NO sync pill (never uploads).
        let phoneOnly = Memo(syncStatus: .waiting, transcriptStatus: .done, significance: 0)
        XCTAssertNil(phoneOnly.statusKind)

        // significance > 0 → flagged to send → Waiting / Synced as before.
        let waiting = Memo(syncStatus: .waiting, transcriptStatus: .done, significance: 0.5)
        XCTAssertEqual(waiting.statusKind, .waiting)

        let synced = Memo(syncStatus: .synced, transcriptStatus: .done, significance: 0.5)
        XCTAssertEqual(synced.statusKind, .synced)
    }

    func testStatusKindAlwaysShowsTranscriptStateRegardlessOfSignificance() {
        // Transcript states are informational and show even for phone-only memos.
        let transcribing = Memo(transcriptStatus: .transcribing, significance: 0)
        XCTAssertEqual(transcribing.statusKind, .transcribing)

        let failed = Memo(transcriptStatus: .failed, significance: 0)
        XCTAssertEqual(failed.statusKind, .error)
    }
}
