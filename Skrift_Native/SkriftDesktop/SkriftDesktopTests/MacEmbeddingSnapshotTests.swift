import XCTest
import SwiftData
import Foundation

/// Q168 (C87, C110): the Mac's Connections index embeds the SAME text as the phone's — read
/// from the synced `Memo` + newest `MemoEnhancement` through `SemanticSearch.snapshot(memo:…)`
/// — instead of the queue row's own fields (which dropped the user title and the typed
/// annotation). Plus the shared first-keystroke warm-up rule.
@MainActor
final class MacEmbeddingSnapshotTests: XCTestCase {

    private func cloudContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Memo.self, MemoAsset.self, MemoEnhancement.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    /// A rated queue row for memo `id`, carrying Mac-side text that must NOT win.
    private func row(for id: UUID, significance: Double? = 0.5) -> PipelineFile {
        let pf = PipelineFile(id: id.uuidString, filename: "memo_\(id.uuidString).m4a")
        pf.significance = significance
        pf.transcript = "row transcript"
        pf.sanitised = "row sanitised body"
        pf.enhancedTitle = "Row title"
        pf.enhancedSummary = "Row summary"
        return pf
    }

    private func assertSame(_ a: MemoSnapshot?, _ b: MemoSnapshot?, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a?.id, b?.id, file: file, line: line)
        XCTAssertEqual(a?.title, b?.title, file: file, line: line)
        XCTAssertEqual(a?.summary, b?.summary, file: file, line: line)
        XCTAssertEqual(a?.body, b?.body, file: file, line: line)
        XCTAssertEqual(a?.place, b?.place, file: file, line: line)
        XCTAssertEqual(a?.tags, b?.tags, file: file, line: line)
    }

    func testSyncedNoteEmbedsThePhonesText() throws {
        let ctx = try cloudContext()
        let id = UUID()
        let memo = Memo(id: id, audioFilename: "memo_\(id.uuidString).m4a", tags: ["walk"],
                        title: "My own title", transcript: "raw words", significance: 0.5,
                        annotationText: "typed afterthought")
        let polish = MemoEnhancement(memoID: id, copyedit: "Polished words.", title: "Polish title",
                                     summary: "Polish summary")
        ctx.insert(memo); ctx.insert(polish); try ctx.save()

        let snaps = MacEmbeddingSnapshot.snapshots(files: [row(for: id)], cloud: ctx)
        XCTAssertEqual(snaps.count, 1)
        let mac = try XCTUnwrap(snaps.first)
        // Exactly what the phone's JournalIndexService builds for the same note.
        assertSame(mac, SemanticSearch.snapshot(memo: memo, enhancement: polish))
        XCTAssertEqual(mac.title, "My own title", "the user's title wins, as on the phone")
        XCTAssertEqual(mac.body, "Polished words.\ntyped afterthought", "copy-edit + annotation")
        XCTAssertEqual(mac.summary, "Polish summary")
        XCTAssertFalse(mac.body.contains("row sanitised"), "the queue row's text no longer decides")
    }

    func testNewestEnhancementWins() throws {
        let ctx = try cloudContext()
        let id = UUID()
        ctx.insert(Memo(id: id, transcript: "raw", significance: 0.5))
        ctx.insert(MemoEnhancement(memoID: id, copyedit: "Old polish.", enhancedAt: Date(timeIntervalSince1970: 100)))
        ctx.insert(MemoEnhancement(memoID: id, copyedit: "New polish.", enhancedAt: Date(timeIntervalSince1970: 200)))
        try ctx.save()
        let mac = try XCTUnwrap(MacEmbeddingSnapshot.snapshots(files: [row(for: id)], cloud: ctx).first)
        XCTAssertEqual(mac.body, "New polish.")
    }

    func testEmptyPolishFallsBackToTheTranscript() throws {
        let ctx = try cloudContext()
        let id = UUID()
        ctx.insert(Memo(id: id, title: nil, transcript: "raw spoken words", significance: 0.5))
        ctx.insert(MemoEnhancement(memoID: id))
        try ctx.save()
        let mac = try XCTUnwrap(MacEmbeddingSnapshot.snapshots(files: [row(for: id)], cloud: ctx).first)
        XCTAssertEqual(mac.body, "raw spoken words")
        XCTAssertNil(mac.title)
    }

    func testRowIDIsKeptWhenTheMemoResolvesByFilename() throws {
        let ctx = try cloudContext()
        let memoID = UUID(), rowID = UUID()
        ctx.insert(Memo(id: memoID, title: "Synced", transcript: "the synced words", significance: 0.5))
        try ctx.save()
        let pf = PipelineFile(id: rowID.uuidString, filename: "memo_\(memoID.uuidString).m4a")
        pf.significance = 0.5
        pf.transcript = "row words"
        let mac = try XCTUnwrap(MacEmbeddingSnapshot.snapshots(files: [pf], cloud: ctx).first)
        XCTAssertEqual(mac.id, rowID, "hits stay addressable by the queue row the sidebar shows")
        XCTAssertEqual(mac.body, "the synced words")
    }

    func testNoSyncedMemoKeepsTheRowSnapshot() throws {
        let id = UUID()
        let mac = try XCTUnwrap(MacEmbeddingSnapshot.snapshots(files: [row(for: id)], cloud: nil).first)
        XCTAssertEqual(mac.id, id)
        XCTAssertEqual(mac.body, "row sanitised body")
        XCTAssertEqual(mac.title, "Row title")
    }

    func testMembershipStaysLiveAndRated() throws {
        let ctx = try cloudContext()
        let rated = UUID(), unrated = UUID(), trashed = UUID()
        for id in [rated, unrated, trashed] {
            ctx.insert(Memo(id: id, transcript: "words \(id)", significance: 0.5))
        }
        try ctx.save()
        let gone = row(for: trashed); gone.deletedAt = Date()
        let snaps = MacEmbeddingSnapshot.snapshots(
            files: [row(for: rated), row(for: unrated, significance: 0), gone], cloud: ctx)
        XCTAssertEqual(snaps.map(\.id), [rated])
    }

    func testWarmsOnTheFirstNonBlankKeystroke() {
        XCTAssertTrue(SemanticSearch.warmsEngine(forQuery: "c"))
        XCTAssertTrue(SemanticSearch.warmsEngine(forQuery: " cost "))
        XCTAssertFalse(SemanticSearch.warmsEngine(forQuery: ""))
        XCTAssertFalse(SemanticSearch.warmsEngine(forQuery: "   "))
    }
}
