import XCTest

/// `Pipeline/WayOutRules` — the Queue band (②), one-trash footer count (③), and
/// the "On its way out" conveyor (④). Pure logic, no views/ModelContext — the
/// MLX-free `UnitTests` scheme.
final class WayOutRulesTests: XCTestCase {

    private let now = Date()
    private func daysAgo(_ n: Int) -> Date { now.addingTimeInterval(-Double(n) * 86_400) }

    private func memo(id: UUID = UUID(), days: Int = 1, significance: Double = 0,
                      deletedDaysAgo: Int? = nil, title: String? = nil,
                      transcript: String? = "hello there\nsecond line") -> Memo {
        Memo(id: id, audioFilename: "memo_\(id.uuidString).m4a", recordedAt: daysAgo(days),
             title: title, transcript: transcript, transcriptStatus: .done,
             significance: significance, deletedAt: deletedDaysAgo.map { daysAgo($0) })
    }

    private func pipelineFile(id: String) -> PipelineFile {
        PipelineFile(id: id, filename: "x.m4a", sourceType: .audio, uploadedAt: now)
    }

    // MARK: - ② band membership

    func testUnpipelinedIncludesUnratedNotDeletedNotIngestedMemos() {
        let m = memo(significance: 0)
        XCTAssertEqual(WayOutRules.unpipelined(memos: [m], files: []).map(\.id), [m.id])
    }

    func testUnpipelinedExcludesRatedMemos() {
        let m = memo(significance: 0.1)
        XCTAssertTrue(WayOutRules.unpipelined(memos: [m], files: []).isEmpty)
    }

    func testUnpipelinedExcludesDeletedMemos() {
        let m = memo(significance: 0, deletedDaysAgo: 1)
        XCTAssertTrue(WayOutRules.unpipelined(memos: [m], files: []).isEmpty)
    }

    func testUnpipelinedExcludesAlreadyIngestedMemos() {
        let m = memo(significance: 0)
        let pf = pipelineFile(id: m.id.uuidString)
        XCTAssertTrue(WayOutRules.unpipelined(memos: [m], files: [pf]).isEmpty)
    }

    func testUnpipelinedIgnoresNonUUIDPipelineFileIDs() {
        // A legacy/local-upload PipelineFile id ("demo-1"-style) can never
        // collide with a memo's id.uuidString — it must not accidentally
        // exclude an unrelated memo from the band.
        let m = memo(significance: 0)
        let legacy = pipelineFile(id: "demo-1")
        XCTAssertEqual(WayOutRules.unpipelined(memos: [m], files: [legacy]).map(\.id), [m.id])
    }

    func testUnpipelinedDoesNotRequireATranscript() {
        let m = memo(significance: 0, transcript: nil)
        XCTAssertEqual(WayOutRules.unpipelined(memos: [m], files: []).map(\.id), [m.id])
    }

    // MARK: - displayTitle

    func testDisplayTitlePrefersTheSetTitle() {
        let m = memo(title: "My title")
        XCTAssertEqual(WayOutRules.displayTitle(m), "My title")
    }

    func testDisplayTitleFallsBackToTheFirstTranscriptLine() {
        let m = memo(title: nil, transcript: "first line\nsecond line")
        XCTAssertEqual(WayOutRules.displayTitle(m), "first line")
    }

    func testDisplayTitleStripsImageMarkers() {
        let m = memo(title: nil, transcript: "[[img_001]]\nreal text here")
        XCTAssertEqual(WayOutRules.displayTitle(m), "real text here")
    }

    func testDisplayTitleFallsBackToVoiceNote() {
        let m = memo(title: nil, transcript: nil)
        XCTAssertEqual(WayOutRules.displayTitle(m), "Voice note")
    }

    // MARK: - oneLiner (delegates to MemoSpine — spot check, not a re-test of the spine)

    func testOneLinerReflectsTheUntouchedLifecycleTrack() {
        let fresh = memo(days: 5, significance: 0)
        XCTAssertTrue(WayOutRules.oneLiner(for: fresh, now: now).hasPrefix("starts fading "),
                      "got: \(WayOutRules.oneLiner(for: fresh, now: now))")
    }

    func testOneLinerReflectsATouchedMemoAsParked() {
        let m = memo(days: 400, significance: 0)
        m.tags = ["garden"]
        XCTAssertEqual(WayOutRules.oneLiner(for: m, now: now), "kept — tagged")
    }

    // MARK: - ③ the footer count (memo trash + Mac-local tail)

    func testIsMacOnlyTrueForAFileWithNoDerivableIDAtAll() {
        // No memo_/capture_ filename, and the id itself isn't UUID-shaped —
        // MacCloudWriteBack.memoID(for:) can't even produce a candidate.
        let pf = pipelineFile(id: "demo-legacy-1")
        XCTAssertTrue(WayOutRules.isMacOnly(pf, memoIDs: []))
    }

    func testIsMacOnlyTrueForARandomUUIDThatMatchesNoRealMemo() {
        // The important regression case: PipelineFile.init's OWN default also
        // mints a random UUID string for a purely LOCAL upload — a UUID-shaped
        // id alone must NOT read as memo-linked unless it's actually IN the
        // live memo set.
        let pf = pipelineFile(id: UUID().uuidString)
        XCTAssertTrue(WayOutRules.isMacOnly(pf, memoIDs: []))
    }

    func testIsMacOnlyFalseWhenTheIdIsAKnownMemoUUID() {
        // MemoCloudIngest sets id = memo.id.uuidString.
        let memoID = UUID()
        let pf = pipelineFile(id: memoID.uuidString)
        XCTAssertFalse(WayOutRules.isMacOnly(pf, memoIDs: [memoID]))
    }

    func testIsMacOnlyFalseWhenTheFilenameEmbedsAKnownMemoUUID() {
        let memoID = UUID()
        let pf = PipelineFile(id: "some-random-id", filename: "memo_\(memoID.uuidString).m4a",
                              sourceType: .audio, uploadedAt: now)
        XCTAssertFalse(WayOutRules.isMacOnly(pf, memoIDs: [memoID]))
    }

    func testMacOnlyTrashedRequiresBothDeletedAndMacOnly() {
        let knownMemoID = UUID()
        let notDeleted = pipelineFile(id: UUID().uuidString)
        let deletedMacOnly = pipelineFile(id: UUID().uuidString)
        deletedMacOnly.deletedAt = now
        let deletedAndMemoLinked = pipelineFile(id: knownMemoID.uuidString)
        deletedAndMemoLinked.deletedAt = now

        let result = WayOutRules.macOnlyTrashed([notDeleted, deletedMacOnly, deletedAndMemoLinked],
                                                 memoIDs: [knownMemoID])
        XCTAssertEqual(result.map(\.id), [deletedMacOnly.id])
    }

    func testBandExcludesFadingNotes() {
        // One-home law: a fading unrated note lives on the Review conveyor, so
        // the band must NOT list it too (Tuur's eyeball round, 2026-07-21 —
        // the double home read as "are those the fading ones?").
        let fresh = memo(significance: 0)                       // New → band
        let fading = memo(days: 40, significance: 0)            // Fading → conveyor only
        let out = WayOutRules.unpipelined(memos: [fresh, fading], files: [], now: now)
        XCTAssertEqual(out.map(\.id), [fresh.id])
    }

    func testQuietRowSearchMatchesTitleAndTranscript() {
        let m = memo(significance: 0, title: "Rooftop drip plan",
                     transcript: "the pump needs a finer nozzle")
        XCTAssertTrue(WayOutRules.matchesSearch(m, query: ""))
        XCTAssertTrue(WayOutRules.matchesSearch(m, query: "rooftop"))
        XCTAssertTrue(WayOutRules.matchesSearch(m, query: "NOZZLE"))
        XCTAssertFalse(WayOutRules.matchesSearch(m, query: "airport"))
    }

    // MARK: - quiet-row source glyphs (mirror of PipelineFile.sourceDescriptor)

    func testSourceGlyphAudiobookQuoteBeatsEverything() throws {
        let m = memo(significance: 0)
        m.metadataData = try JSONEncoder().encode(MemoMetadata(bookTitle: "The Trouble with Goats"))
        XCTAssertEqual(WayOutRules.sourceGlyph(for: m), "book.closed.fill")
    }

    func testSourceGlyphVideo() throws {
        let m = memo(significance: 0)
        m.metadataData = try JSONSerialization.data(withJSONObject: ["mediaSource": "video"])
        XCTAssertEqual(WayOutRules.sourceGlyph(for: m), "video.fill")
    }

    func testSourceGlyphCaptureSubtypes() throws {
        let m = memo(significance: 0)
        m.metadataData = try JSONSerialization.data(withJSONObject:
            ["sharedContent": ["type": "url", "url": "https://example.com"]])
        XCTAssertEqual(WayOutRules.sourceGlyph(for: m), "link")
    }

    func testSourceGlyphFallsBackToMicOrNote() {
        XCTAssertEqual(WayOutRules.sourceGlyph(for: memo(significance: 0)), "mic.fill")
        let note = Memo(audioFilename: "", recordedAt: daysAgo(1),
                        transcript: "apple note", transcriptStatus: .done)
        XCTAssertEqual(WayOutRules.sourceGlyph(for: note), "note.text")
    }

    // MARK: - ④ the conveyor

    func testBringBackSetsKeptAtAndClearsDeletedAt() {
        let m = memo(significance: 0, deletedDaysAgo: 5)
        XCTAssertNil(m.keptAt)
        XCTAssertNotNil(m.deletedAt)
        WayOutRules.bringBack(m, now: now)
        XCTAssertEqual(m.keptAt, now)
        XCTAssertNil(m.deletedAt)
    }

    func testBringBackSetsKeptAtEvenWhenNotDeleted() {
        // A fading (not yet deleted) note's Bring back: still a touch, still
        // must stamp keptAt, even though there's no deletedAt to clear.
        let m = memo(days: 40, significance: 0)
        WayOutRules.bringBack(m, now: now)
        XCTAssertEqual(m.keptAt, now)
        XCTAssertNil(m.deletedAt)
    }

    func testFadingOrderedIsSoonestToMoveFirst() {
        let soon = memo(days: 59)     // 1 day from the 60d auto-move
        let later = memo(days: 31)    // 29 days from the 60d auto-move
        XCTAssertEqual(WayOutRules.fadingOrdered([later, soon]).map(\.id), [soon.id, later.id])
    }

    func testDeletedOrderedIsSoonestToPurgeFirst() {
        // Mirrors the mock's worked example: "deleted 7 Jul · ~1d" listed
        // ABOVE "deleted 14 Jul · ~8d" — the OLDER deletedAt purges sooner and
        // sorts first. This is a deliberate reversal of MacTrashColumn's old
        // newest-deleted-first comparator.
        let deletedLongAgo = memo(significance: 0, deletedDaysAgo: 13)   // ~1d left of the 14d retention
        let deletedRecently = memo(significance: 0, deletedDaysAgo: 6)   // ~8d left
        XCTAssertEqual(WayOutRules.deletedOrdered([deletedRecently, deletedLongAgo]).map(\.id),
                       [deletedLongAgo.id, deletedRecently.id])
    }
}
