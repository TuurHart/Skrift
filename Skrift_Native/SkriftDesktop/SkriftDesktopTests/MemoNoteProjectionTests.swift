import XCTest
import SwiftData
import Foundation

/// `MemoNoteProjection` — an unrated memo rendered as a NORMAL note.
///
/// What's worth testing here isn't the view (that's the `-snapshot-unrated` render);
/// it's the two claims the projection makes: that it maps a memo faithfully into the
/// type the note view reads, and that it stays OUT of the pipeline store — which is
/// what keeps "the rating IS the flag" true.
@MainActor
final class MemoNoteProjectionTests: XCTestCase {

    private func memo(significance: Double = 0,
                      title: String? = nil,
                      transcript: String? = "Walked the long way back.",
                      tags: [String] = []) -> Memo {
        Memo(id: UUID(), audioFilename: "memo_x.m4a", duration: 96,
             recordedAt: Date(timeIntervalSince1970: 1_700_000_000), tags: tags,
             title: title, transcript: transcript, transcriptStatus: .done,
             significance: significance)
    }

    // MARK: - the projection maps a memo into a renderable note

    func testProjectionCarriesTheMemoIdentityAndContent() {
        let m = memo(title: "A real title", transcript: "Body text.", tags: ["export"])
        let pf = MemoNoteProjection.file(for: m)

        // The id IS the memo UUID — the contract spine, and what lets the Mac→phone
        // write-back resolve the memo back out of a projection.
        XCTAssertEqual(pf.id, m.id.uuidString)
        XCTAssertEqual(ReconcileV2.Writers.memoID(for: pf), m.id)
        XCTAssertEqual(pf.enhancedTitle, "A real title")
        XCTAssertEqual(pf.transcript, "Body text.")
        XCTAssertEqual(pf.tags, ["export"])
        XCTAssertEqual(pf.uploadedAt, m.recordedAt)
        XCTAssertEqual(pf.transcribeStatus, .done)
    }

    /// An unrated memo must reach the circles as "nothing picked" — `Memo` says 0,
    /// `PipelineFile` says nil, and rendering 0 as a rating would fill a circle the
    /// user never chose.
    func testUnratedMemoProjectsToNilSignificanceNotZero() {
        XCTAssertNil(MemoNoteProjection.file(for: memo(significance: 0)).significance)
        XCTAssertEqual(MemoNoteProjection.file(for: memo(significance: 0.6)).significance, 0.6)
    }

    /// An untitled memo leaves `enhancedTitle` nil, so the header falls through to its
    /// derived (greyed) placeholder via exactly the same `displayTitle` path any
    /// untitled pipelined note uses — no special case. (`displayTitle` itself lives in
    /// `Features/`, outside this host-less bundle; the identity of the RENDERED title is
    /// proven by `-snapshot-unrated`, which pixel-matched both sides at rgb(207,207,208).)
    func testUntitledMemoLeavesTheTitleToTheDerivedPlaceholder() {
        let pf = MemoNoteProjection.file(for: memo(title: nil, transcript: "First line here.\nSecond."))
        XCTAssertNil(pf.enhancedTitle, "no real title → the header shows its greyed placeholder")
        XCTAssertEqual(pf.transcript, "First line here.\nSecond.", "the line it derives from")
    }

    /// The bare projection has no media path — `materialiseMedia` is what supplies it.
    func testBareProjectionHasNoMediaPathUntilMaterialised() {
        XCTAssertEqual(MemoNoteProjection.file(for: memo()).path, "")
    }

    // MARK: - media: the blobs are synced, only the FILES were missing

    /// An unrated note PLAYS (Tuur, 2026-07-26). Nothing is downloaded — the audio
    /// blob already synced; materialising it is what gives the player a real file.
    func testMaterialiseWritesAudioAndPointsTheProjectionAtIt() throws {
        let m = memo()
        m.audioFilename = "memo_x.m4a"
        let pf = MemoNoteProjection.file(for: m)
        let blob = Data([0x00, 0x01, 0x02, 0x03])
        defer { MemoNoteProjection.discardMedia(for: m.id) }

        MemoNoteProjection.materialiseMedia(for: m, into: pf) {
            [MemoAsset(memoID: m.id, kind: MemoAsset.Kind.audio, filename: "memo_x.m4a", blob: blob)]
        }
        XCTAssertTrue(pf.path.hasSuffix("original.m4a"))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: pf.path)), blob)
        XCTAssertNotNil(pf.workingFolder, "photos resolve relative to this")
    }

    /// Karaoke: word timings are transcription output, not polish, so an unrated note
    /// is entitled to read along.
    func testMaterialiseCarriesWordTimings() {
        let m = memo()
        let pf = MemoNoteProjection.file(for: m)
        let timings = Data("[{\"word\":\"hi\",\"start\":0,\"end\":0.4}]".utf8)
        defer { MemoNoteProjection.discardMedia(for: m.id) }

        MemoNoteProjection.materialiseMedia(for: m, into: pf) {
            [MemoAsset(memoID: m.id, kind: MemoAsset.Kind.wordTimings, filename: "t.json", blob: timings)]
        }
        XCTAssertEqual(pf.wordTimingsJSON, timings)
    }

    /// Blobs are heavy: a second open of the same note must fetch NOTHING (the files
    /// are already on disk) — the `MemoPhotoMaterializer` laziness rule.
    func testSecondOpenFetchesNoBlobs() {
        let m = memo()
        m.audioFilename = "memo_x.m4a"
        defer { MemoNoteProjection.discardMedia(for: m.id) }
        let assets = [MemoAsset(memoID: m.id, kind: MemoAsset.Kind.audio,
                                filename: "memo_x.m4a", blob: Data([0x00]))]

        let first = MemoNoteProjection.file(for: m)
        MemoNoteProjection.materialiseMedia(for: m, into: first) { assets }

        var fetched = false
        let second = MemoNoteProjection.file(for: m)
        MemoNoteProjection.materialiseMedia(for: m, into: second) { fetched = true; return assets }
        XCTAssertFalse(fetched, "already on disk ⇒ no blob fetch")
        XCTAssertEqual(second.path, first.path)
    }

    /// Rating it hands over to the real ingest folder, so the cache copy is dropped.
    func testDiscardMediaRemovesTheCacheFolder() {
        let m = memo()
        m.audioFilename = "memo_x.m4a"
        let pf = MemoNoteProjection.file(for: m)
        MemoNoteProjection.materialiseMedia(for: m, into: pf) {
            [MemoAsset(memoID: m.id, kind: MemoAsset.Kind.audio, filename: "memo_x.m4a", blob: Data([0x00]))]
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: pf.path))
        MemoNoteProjection.discardMedia(for: m.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: pf.path))
    }

    /// The chips row derives from the same metadata blob a real ingest writes, so
    /// place/weather/daypart read identically on both kinds of note.
    func testContextChipsDeriveThroughTheIngestMetadataBlob() {
        let m = memo()
        m.metadataData = try? JSONSerialization.data(withJSONObject: [
            "location": ["placeName": "Cais do Sodré"],
            "weather": ["temperature": 21.0],
            "dayPeriod": "evening",
        ] as [String: Any])
        let chips = MemoNoteProjection.file(for: m).contextChips
        XCTAssertEqual(chips.map(\.text), ["Cais do Sodré", "21°", "Evening"])
    }

    // MARK: - and stays out of the pipeline

    /// The whole reason this is a projection and not an ingest: nothing enters the
    /// pipeline store, so an unrated note can be OPENED without becoming processable.
    @MainActor
    func testProjectionIsNeverInsertedIntoThePipelineStore() throws {
        let container = try ModelContainer(
            for: PipelineFile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let ctx = container.mainContext

        let pf = MemoNoteProjection.file(for: memo())
        XCTAssertNil(pf.modelContext, "a projection belongs to no context — that's what MacCloudEditSync tests")
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<PipelineFile>()), 0,
                       "opening an unrated note must not create a queue row")
    }

    // MARK: - write-back puts edits on the memo

    func testWriteBackMirrorsEditsOntoTheMemo() {
        let m = memo(title: nil, transcript: "Original.", tags: [])
        let pf = MemoNoteProjection.file(for: m)

        pf.enhancedTitle = "  Named by hand  "
        pf.transcript = "Edited body."
        pf.tags = ["ideas"]
        XCTAssertTrue(MemoNoteProjection.writeBack(pf, to: m))

        XCTAssertEqual(m.title, "Named by hand", "trimmed")
        XCTAssertEqual(m.transcript, "Edited body.")
        XCTAssertEqual(m.tags, ["ideas"])
        XCTAssertTrue(m.transcriptUserEdited, "a hand-edit is exactly what the trust flag means")
        XCTAssertNotNil(m.editedAt)
    }

    /// Rating an unrated note through the ordinary circles is what pipelines it.
    func testWriteBackCarriesARatingSoTheRatingStaysTheFlag() {
        let m = memo(significance: 0)
        let pf = MemoNoteProjection.file(for: m)
        pf.significance = 0.4
        XCTAssertTrue(MemoNoteProjection.writeBack(pf, to: m))
        XCTAssertEqual(m.significance, 0.4)
    }

    /// …and UN-rating has to travel too. Re-tapping the lit circle sets the binding
    /// to nil; that used to be skipped by an `if let`, so a rating could be given but
    /// never taken back (Tuur, 2026-07-26: "when i removed it it did not go grey
    /// again"). `Memo.significance` is non-optional, so cleared is 0.
    func testWriteBackCarriesAClearedRating() {
        let m = memo(significance: 0.4)
        let pf = MemoNoteProjection.file(for: m)
        XCTAssertEqual(pf.significance, 0.4)
        pf.significance = nil                      // re-tap the lit circle
        XCTAssertTrue(MemoNoteProjection.writeBack(pf, to: m))
        XCTAssertEqual(m.significance, 0, "un-rating must reach the memo, not just the view")
    }

    /// Idempotent: re-committing an untouched projection must not churn `editedAt`
    /// (which would look like an edit to the reconciler and bounce over CloudKit).
    func testWriteBackReportsNoChangeWhenNothingWasEdited() {
        let m = memo(title: "Stable", transcript: "Body.", tags: ["a"])
        let pf = MemoNoteProjection.file(for: m)
        XCTAssertFalse(MemoNoteProjection.writeBack(pf, to: m))
        XCTAssertNil(m.editedAt)
    }

    /// Clearing the title field returns the note to its derived (greyed) title rather
    /// than persisting an empty string.
    func testClearingTheTitleRestoresTheDerivedOne() {
        let m = memo(title: "Had one")
        let pf = MemoNoteProjection.file(for: m)
        pf.enhancedTitle = "   "
        XCTAssertTrue(MemoNoteProjection.writeBack(pf, to: m))
        XCTAssertNil(m.title)
    }

    // MARK: - the one-clock touch (typed notes made this load-bearing)

    /// Typing into a completely EMPTY note (a typed note's first words) writes back —
    /// and a content edit is a TOUCH: `keptAt` bumps, so a note you are actively
    /// writing never quietly fades. (`writeBack` used to stamp `editedAt` alone;
    /// `MemoLifecycle.clockStart` never reads that.)
    func testTypingIntoAnEmptyNoteWritesBackAndRestartsTheFadeClock() {
        let m = memo(title: nil, transcript: nil, tags: [])
        XCTAssertNil(m.keptAt)
        let pf = MemoNoteProjection.file(for: m)

        pf.transcript = "First words of a typed note."
        XCTAssertTrue(MemoNoteProjection.writeBack(pf, to: m))

        XCTAssertEqual(m.transcript, "First words of a typed note.")
        XCTAssertTrue(m.transcriptUserEdited)
        XCTAssertNotNil(m.keptAt, "a content edit is a touch — the fade clock restarts")
    }

    /// A rating alone is a JUDGMENT, not an investment — it must not touch the clock
    /// (markEdited's own contract: never from significance changes). The rated note
    /// leaves the clock anyway; what matters is that UN-rating later doesn't find a
    /// phantom touch extending the fade.
    func testARatingOnlyWriteBackDoesNotTouchTheClock() {
        let m = memo(significance: 0)
        XCTAssertNil(m.keptAt)
        let pf = MemoNoteProjection.file(for: m)

        pf.significance = 0.4
        XCTAssertTrue(MemoNoteProjection.writeBack(pf, to: m))

        XCTAssertEqual(m.significance, 0.4)
        XCTAssertNil(m.keptAt, "rating is not a touch")
        XCTAssertNil(m.editedAt, "…and not an edit either")
    }
}
