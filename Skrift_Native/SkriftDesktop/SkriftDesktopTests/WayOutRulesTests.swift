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

    func testWayOutFooterCountSumsMemoTrashAndMacOnlyTail() {
        let deletedMemo1 = memo(significance: 0, deletedDaysAgo: 1)
        let deletedMemo2 = memo(significance: 0.5, deletedDaysAgo: 3)
        let liveMemo = memo(significance: 0)
        let macOnly = pipelineFile(id: UUID().uuidString)   // random id, matches no memo above
        macOnly.deletedAt = now
        let notDeleted = pipelineFile(id: UUID().uuidString)

        let count = WayOutRules.wayOutFooterCount(memos: [deletedMemo1, deletedMemo2, liveMemo],
                                                   trashedFiles: [macOnly, notDeleted])
        XCTAssertEqual(count, 3)   // 2 deleted memos + 1 mac-only trashed file
    }

    func testWayOutFooterCountDoesNotDoubleCountAMemoLinkedTrashedFile() {
        // A trashed PipelineFile whose id happens to match a memo THAT'S ALSO
        // counted on the memo side must not be double-counted via the tail.
        let deletedMemo = memo(significance: 0, deletedDaysAgo: 1)
        let linkedFile = pipelineFile(id: deletedMemo.id.uuidString)
        linkedFile.deletedAt = now

        let count = WayOutRules.wayOutFooterCount(memos: [deletedMemo], trashedFiles: [linkedFile])
        XCTAssertEqual(count, 1)
    }
}
