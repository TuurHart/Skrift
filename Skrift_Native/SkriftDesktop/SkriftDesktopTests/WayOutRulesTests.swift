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

    func testUnpipelinedExcludesLockedMemos() {
        // m6 (2026-07-22): lock = the explicit keep-don't-polish verb — a
        // resolved note doesn't nag in the quiet list.
        let m = memo(significance: 0)
        m.locked = true
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

    func testUnpipelinedIncludesMemoWhoseOnlyPipelineRowIsAQuietLocalTake() {
        // The unrated-take doctrine (2026-07-28, LANES-2026-07-28/BRIEF_DOCTRINE.md):
        // a Mac recording's pipeline row exists (it holds the transcript) but stays
        // UNRATED — its twin memo must still surface here, exactly like a phone
        // memo with no row at all. See UnratedTakeTests.swift for the focused suite
        // on the new WayOutRules predicates this leans on.
        let m = memo(significance: 0)
        let pf = pipelineFile(id: m.id.uuidString)
        pf.isLocalRecording = true
        XCTAssertEqual(WayOutRules.unpipelined(memos: [m], files: [pf]).map(\.id), [m.id])
    }

    func testUnpipelinedExcludesARatedLocalTake() {
        let m = memo(significance: 0)
        let pf = pipelineFile(id: m.id.uuidString)
        pf.isLocalRecording = true
        pf.significance = 0.3
        XCTAssertTrue(WayOutRules.unpipelined(memos: [m], files: [pf]).isEmpty)
    }

    func testUnpipelinedExcludesAnErroredLocalTake() {
        // Errors stay loud: an errored take keeps its (lit) queue row, so it must
        // NOT also show as a quiet row — one row, not two homes.
        let m = memo(significance: 0)
        let pf = pipelineFile(id: m.id.uuidString)
        pf.isLocalRecording = true
        pf.error = "boom"
        XCTAssertTrue(WayOutRules.unpipelined(memos: [m], files: [pf]).isEmpty)
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
        XCTAssertTrue(WayOut.oneLiner(for: fresh, now: now).hasPrefix("starts fading "),
                      "got: \(WayOut.oneLiner(for: fresh, now: now))")
    }

    func testOneLinerPutsATouchedMemoOnTheClock() {
        // One clock (2026-07-22): a touch restarts the clock instead of
        // parking the note — tags alone hold nothing.
        let m = memo(days: 400, significance: 0)
        m.tags = ["garden"]
        m.keptAt = now.addingTimeInterval(-5 * 86_400)
        XCTAssertTrue(WayOut.oneLiner(for: m, now: now).hasPrefix("starts fading "),
                      "got: \(WayOut.oneLiner(for: m, now: now))")
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

    // MARK: - ④ the conveyor

    func testBringBackSetsKeptAtEvenWhenNotDeleted() {
        // A fading (not yet deleted) note's Bring back: still a touch, still
        // must stamp keptAt, even though there's no deletedAt to clear.
        let m = memo(days: 40, significance: 0)
        WayOut.bringBack(m, now: now)
        XCTAssertEqual(m.keptAt, now)
        XCTAssertNil(m.deletedAt)
    }

    // MARK: - Stranded (rated + rowless — the state with no home in the list)

    /// The floor under the rate→row handoff: a rated memo whose row is missing renders in
    /// NEITHER list section (queue rows are files, quiet rows are the unrated memos), so
    /// it reads as deleted. It must show up here instead.
    func testStrandedIsRatedMemosWithNoRow() {
        let stranded = memo(significance: 0.1)
        let hasRow = memo(significance: 0.5)
        let unrated = memo(significance: 0)
        let trashed = memo(significance: 0.6, deletedDaysAgo: 1)
        let files = [pipelineFile(id: hasRow.id.uuidString)]

        let out = WayOutRules.stranded(memos: [stranded, hasRow, unrated, trashed], files: files)
        XCTAssertEqual(out.map(\.id), [stranded.id],
                       "only the rated, live, rowless one is homeless")
    }

    /// Stranded and quiet are disjoint populations — a note is never in both lists, and
    /// a stranded note must never swell the "N not rated" count.
    func testStrandedAndUnpipelinedNeverOverlap() {
        let rated = memo(significance: 0.1)
        let unrated = memo(significance: 0)
        let memos = [rated, unrated]
        let stranded = WayOutRules.stranded(memos: memos, files: [])
        let quiet = WayOutRules.unpipelined(memos: memos, files: [], now: now)
        XCTAssertEqual(stranded.map(\.id), [rated.id])
        XCTAssertEqual(quiet.map(\.id), [unrated.id])
    }

    /// A LOCKED note still shows: lock means keep-don't-polish (a reason to skip
    /// processing), never a reason to hide the note itself.
    func testStrandedIncludesALockedNote() {
        let locked = memo(significance: 0.4)
        locked.locked = true
        XCTAssertEqual(WayOutRules.stranded(memos: [locked], files: []).map(\.id), [locked.id])
    }

    /// A stranded row must not claim it is queued — it has no row to process WITH.
    func testStrandedLineDoesNotPromiseProcessing() {
        let waiting = memo(significance: 0.5)                       // has an audioFilename
        XCTAssertEqual(WayOutRules.strandedLine(for: waiting), "waiting for its audio")
        let spine = WayOut.oneLiner(for: waiting, now: now)
        XCTAssertEqual(spine, "processes on next run", "…which is the line it must NOT show")
    }
}
