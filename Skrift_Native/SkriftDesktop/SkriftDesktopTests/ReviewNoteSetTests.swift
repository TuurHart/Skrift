import XCTest
import Foundation

/// Q166 (recsj-100, -101, -113): every Review surface reads ONE note set,
/// `ReviewNotes.live` — the calendar, the map, the river and Then vs Now never see a
/// fading, trashed or duplicate row — and the map's pinned place clears on a real
/// gesture. Same file in both suites (mobile adds the @testable import).
final class ReviewNoteSetTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func memo(daysAgo: Int, rated: Bool, place: String? = nil, id: UUID = UUID(),
                      deleted: Bool = false) -> Memo {
        var metadata: Data?
        if let place {
            metadata = try? JSONEncoder().encode(
                MemoMetadata(location: LocationInfo(latitude: 38.7, longitude: -9.1, placeName: place)))
        }
        return Memo(id: id, audioFilename: "memo_\(id.uuidString).m4a",
                    recordedAt: now.addingTimeInterval(-Double(daysAgo) * 86_400),
                    transcript: "words", transcriptStatus: .done,
                    significance: rated ? 0.5 : 0,
                    deletedAt: deleted ? now : nil, metadataData: metadata)
    }

    // MARK: the one set

    func testLiveDropsFadingTrashedAndDuplicateRows() {
        let rated = memo(daysAgo: 90, rated: true)
        let fresh = memo(daysAgo: 3, rated: false)
        let fading = memo(daysAgo: 40, rated: false)
        let trashed = memo(daysAgo: 2, rated: true, deleted: true)
        let twin = memo(daysAgo: 90, rated: true, id: rated.id)

        let split = ReviewNotes.split([rated, fresh, fading, trashed, twin], now: now)
        XCTAssertEqual(split.live.map(\.id), [rated.id, fresh.id])
        XCTAssertEqual(split.fading.map(\.id), [fading.id])
        XCTAssertEqual(ReviewNotes.live([rated, fresh, fading, trashed, twin], now: now).map(\.id),
                       split.live.map(\.id))
    }

    func testMapNeverPinsAFadingNote() {
        let kept = memo(daysAgo: 100, rated: true, place: "Lisbon")
        let fading = memo(daysAgo: 45, rated: false, place: "Leiden")
        let fadingSamePlace = memo(daysAgo: 50, rated: false, place: "Lisbon")

        let clusters = PlaceCluster.build(from: ReviewNotes.live([kept, fading, fadingSamePlace], now: now))
        XCTAssertEqual(clusters.map(\.name), ["Lisbon"])
        XCTAssertEqual(clusters.first?.memos.map(\.id), [kept.id], "the pin counts live notes only")
    }

    func testCalendarDayNeverCountsAFadingNote() {
        let kept = memo(daysAgo: 40, rated: true)
        let fading = memo(daysAgo: 40, rated: false)
        let day = kept.recordedAt
        let shown = LookbackProvider.memos(for: ReviewNotes.live([kept, fading], now: now), onDay: day)
        XCTAssertEqual(shown.map(\.id), [kept.id])
    }

    func testThenVsNowOverTheLiveSetNeverPicksAFadingNote() async {
        let fresh = memo(daysAgo: 2, rated: true)
        let oldRated = memo(daysAgo: 300, rated: true)
        let oldFading = memo(daysAgo: 300, rated: false)
        let live = ReviewNotes.live([fresh, oldRated, oldFading], now: now)

        let pair = await ThenVsNow.derive(memos: live, now: now, floor: Float(0.5)) { (id: UUID) -> [(memoID: UUID, score: Float)] in
            id == fresh.id ? [(memoID: oldFading.id, score: Float(0.95)),
                              (memoID: oldRated.id, score: Float(0.7))] : []
        }
        XCTAssertEqual(pair, ThenVsNow.Pair(then: oldRated.id, now: fresh.id),
                       "the higher-scoring fading note is not in the set")
    }

    // MARK: the map's pinned place

    func testCameraEndClearsThePinOnARealGestureOnly() {
        // A dive or a place-row focus: its own landing keeps the pin, and consumes the flag.
        let landing = ReviewNotes.cameraEnded(programmaticMove: true)
        XCTAssertFalse(landing.clearPinnedPlace)
        XCTAssertFalse(landing.programmaticMove)
        // The next end is the user's pan or zoom: the pin clears.
        let gesture = ReviewNotes.cameraEnded(programmaticMove: landing.programmaticMove)
        XCTAssertTrue(gesture.clearPinnedPlace)
        XCTAssertFalse(gesture.programmaticMove)
    }

    func testHeadingCountIsTheRenderedCount() {
        XCTAssertEqual(ReviewNotes.noteCount(1), "1 note")
        XCTAssertEqual(ReviewNotes.noteCount(0), "0 notes")
        XCTAssertEqual(ReviewNotes.noteCount(34), "34 notes")
    }
}
