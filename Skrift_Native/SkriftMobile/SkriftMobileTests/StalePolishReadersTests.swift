import XCTest
@testable import SkriftMobile

/// Q506 (C153, C261): every reader of the Mac's polish skips one older than his last raw edit
/// and uses his raw words instead, as the note page does: the vault exporter, the wall printer
/// and the list cache all go through `MemoEnhancement.current(_:for:)`.
@MainActor
final class StalePolishReadersTests: XCTestCase {

    private let polishedAt = Date(timeIntervalSince1970: 1_790_000_000)
    private var sandbox: URL!

    override func setUpWithError() throws {
        sandbox = FileManager.default.temporaryDirectory.appendingPathComponent("stale-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sandbox.appendingPathComponent("vault"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: sandbox) }

    /// A rated memo with a Mac polish; `editedAfter` stamps a raw edit after the polish.
    private func note(editedAfter: Bool) -> (Memo, MemoEnhancement) {
        let m = Memo(audioFilename: "memo.m4a", recordedAt: polishedAt.addingTimeInterval(-3600),
                     transcript: "His new raw words about the green glaze.", significance: 0.5)
        m.transcriptEditedAt = editedAfter ? polishedAt.addingTimeInterval(60) : polishedAt.addingTimeInterval(-60)
        let e = MemoEnhancement(memoID: m.id, copyedit: "The old polished words about the blue glaze.",
                                title: "Blue glaze notes", summary: "About the blue glaze.",
                                enhancedAt: polishedAt, processedAt: polishedAt)
        return (m, e)
    }

    // MARK: - the one accessor

    func testTheAccessorDropsAStalePolishOnly() {
        let (fresh, e1) = note(editedAfter: false)
        XCTAssertTrue(MemoEnhancement.current(e1, for: fresh) === e1)
        let (stale, e2) = note(editedAfter: true)
        XCTAssertNil(MemoEnhancement.current(e2, for: stale))
        XCTAssertNil(MemoEnhancement.current(nil, for: stale))
        let unstamped = Memo(transcript: "x")
        XCTAssertNotNil(MemoEnhancement.current(MemoEnhancement(memoID: unstamped.id, copyedit: "y"), for: unstamped),
                        "a note with no raw-edit stamp is never stale")
    }

    // MARK: - the vault exporter

    private func publishedText(_ memo: Memo, _ e: MemoEnhancement) throws -> String {
        let publisher = ObsidianPublisher(vaultProvider: { self.sandbox.appendingPathComponent("vault") },
                                          manageScope: false, author: "T", peopleProvider: { [] },
                                          enhancementProvider: { $0 == memo.id ? e : nil },
                                          ledgerOverride: ExportLedger(fileURL: sandbox.appendingPathComponent("l.json")))
        _ = try publisher.publish(memo)
        let files = FileManager.default.enumerator(at: sandbox.appendingPathComponent("vault"), includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "md" } ?? []
        XCTAssertEqual(files.count, 1)
        return try String(contentsOf: try XCTUnwrap(files.first), encoding: .utf8)
    }

    func testTheExporterWritesHisRawWordsWhenThePolishIsStale() throws {
        let (memo, e) = note(editedAfter: true)
        let text = try publishedText(memo, e)
        XCTAssertTrue(text.contains("His new raw words about the green glaze."), text)
        XCTAssertFalse(text.contains("blue glaze"), "neither the stale body, title nor summary is exported\n\(text)")
    }

    func testTheExporterStillWritesACurrentPolish() throws {
        let (memo, e) = note(editedAfter: false)
        let text = try publishedText(memo, e)
        XCTAssertTrue(text.contains("The old polished words about the blue glaze."), text)
    }

    // MARK: - the wall printer

    func testTheWallCardPrintsHisRawWordsWhenThePolishIsStale() {
        let (stale, e1) = note(editedAfter: true)
        XCTAssertEqual(WallCardView.printedBody(stale, enhancement: e1), "His new raw words about the green glaze.")
        let (fresh, e2) = note(editedAfter: false)
        XCTAssertEqual(WallCardView.printedBody(fresh, enhancement: e2), "The old polished words about the blue glaze.")
    }

    // MARK: - the list cache

    func testTheListTakesNoTitleOrSummaryFromAStalePolish() {
        let (stale, e1) = note(editedAfter: true)
        let (fresh, e2) = note(editedAfter: false)
        let base = ListDerivedCache.buildBase(rawMemos: [stale, fresh], enhancements: [e1, e2],
                                              now: polishedAt.addingTimeInterval(120), generation: 1)
        XCTAssertNil(base.enhancedTitleByMemoID[stale.id])
        XCTAssertNil(base.polish[stale.id] as (title: String, summary: String)?)
        XCTAssertEqual(base.enhancedTitleByMemoID[fresh.id], "Blue glaze notes")
        XCTAssertEqual(base.polish[fresh.id]?.summary, "About the blue glaze.")
        XCTAssertTrue(base.enhanced.contains(stale.id), "it was processed; only its words are out of date")
    }
}
