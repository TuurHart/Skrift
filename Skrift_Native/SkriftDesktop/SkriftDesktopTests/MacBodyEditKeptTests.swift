import XCTest
import SwiftData

/// Q489 hold (orchestrator, 2026-10-23): a body edit made on the Mac lives in `sanitised` (the
/// review editor writes there), while every re-derivation rebuilt from the copy-edit, so a roster
/// change re-linked his edit away, re-exported the old words, and a later polish write-back could
/// push them to the phone. The edit must survive a roster re-link everywhere: in `sanitised`, in
/// the compiled note and in the cloud copy. One rule for `RosterRelink` and `OpenNoteRosterRefresh`
/// (`RosterRelink.rederive`), and the write-back now also keeps the copy-edit in step.
@MainActor
final class MacBodyEditKeptTests: XCTestCase {

    private let bruno = Person(canonical: "[[Bruno Costa]]", aliases: ["Bruno"], short: "Bruno",
                               lastModifiedAt: "2026-09-25T09:00:00Z")
    private let renamed = Person(canonical: "[[Bruno Almeida]]", aliases: ["Bruno"], short: "Bruno",
                                 lastModifiedAt: "2026-09-26T09:00:00Z")
    private let lotte = Person(canonical: "[[Lotte Vos]]", aliases: ["Lotte"], short: "Lotte",
                               lastModifiedAt: "2026-09-01T09:00:00Z")

    private let polish = "Bruno and I talked about the studio rent."
    private let edited = "Bruno and I talked about the studio rent and the kiln."

    /// A processed row, linked under `[bruno]`.
    private func processedRow() -> PipelineFile {
        let pf = PipelineFile(id: UUID().uuidString, filename: "memo.m4a", sourceType: .audio)
        pf.transcript = "so um Bruno and me talked about the studio rent"
        pf.enhancedCopyedit = polish
        pf.enhancedTitle = "Studio rent"
        pf.enhanceStatus = .done
        MemoCloudUpdate.resanitiseAndCompile(pf, people: [bruno], author: "Tuur")
        return pf
    }

    /// What the review editor's body binding does (`NoteBody.bodyBinding`): the edit lands in
    /// `sanitised`, the linked body he sees.
    private func typeOnTheMac(_ pf: PipelineFile, people: [Person]) {
        let linked = Sanitiser.process(text: edited, people: people).sanitised
        XCTAssertNotNil(pf.sanitised)
        pf.sanitised = linked
    }

    /// What `MacCloudEditSync.flush` does after the typing pause, minus the main-actor hop.
    private func writeBack(_ pf: PipelineFile, people: [Person], cloud: ModelContext) throws {
        let trip = MacEditRoundTrip.compute(body: pf.bestBodyText, before: polish, people: people,
                                            neverLink: Set(pf.unlinkedNames), namePicks: pf.namePicks)
        MacEditRoundTrip.adopt(trip, into: pf)
        try MacCloudWriteBack.upsert(for: pf, into: cloud, deviceID: "mac-test", bodyOverride: trip.raw)
    }

    private func cloud(for pf: PipelineFile) throws -> ModelContext {
        let c = try ModelContainer(for: Memo.self, MemoAsset.self, MemoEnhancement.self, MemoEditHead.self,
                                   configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = ModelContext(c)
        let id = try XCTUnwrap(UUID(uuidString: pf.id))
        ctx.insert(Memo(id: id, audioFilename: pf.filename, recordedAt: Date(), transcript: pf.transcript,
                        transcriptStatus: .done, transcriptConfidence: 0.9, significance: 0.6))
        try ctx.save()
        return ctx
    }

    private func cloudCopy(_ pf: PipelineFile, _ ctx: ModelContext) throws -> String? {
        let id = try XCTUnwrap(UUID(uuidString: pf.id))
        return try ctx.fetch(FetchDescriptor<MemoEnhancement>(predicate: #Predicate { $0.memoID == id })).first?.copyedit
    }

    private func assertKept(_ pf: PipelineFile, linkedTo canonical: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(pf.sanitised?.contains("and the kiln") == true, "sanitised: \(pf.sanitised ?? "nil")", file: file, line: line)
        XCTAssertTrue(pf.compiledText?.contains("and the kiln") == true, "compiled", file: file, line: line)
        XCTAssertTrue(pf.sanitised?.contains(canonical) == true, "re-linked to \(canonical): \(pf.sanitised ?? "")", file: file, line: line)
    }

    // MARK: - the binding path, written back, then a roster change

    func testAWrittenBackMacEditSurvivesARosterChange() throws {
        let pf = processedRow()
        let ctx = try cloud(for: pf)
        typeOnTheMac(pf, people: [bruno])
        try writeBack(pf, people: [bruno], cloud: ctx)
        XCTAssertEqual(pf.enhancedCopyedit, edited, "the write-back keeps the copy-edit in step with the edit")

        RosterRelink.relink([pf], linkedWith: [bruno], people: [bruno, lotte], author: "Tuur")

        assertKept(pf, linkedTo: "[[Bruno Costa")
        XCTAssertEqual(try cloudCopy(pf, ctx), edited, "the cloud copy is his edit")
        // A later polish write-back (Redo title, post-process) sends the copy-edit: still his words.
        try MacCloudWriteBack.upsert(for: pf, into: ctx, deviceID: "mac-test")
        XCTAssertEqual(try cloudCopy(pf, ctx), edited)
    }

    func testAnEditStillInTheTypingPauseSurvivesARename() throws {
        // No write-back yet (the 1.5 s debounce): the edit is only in `sanitised`.
        let pf = processedRow()
        typeOnTheMac(pf, people: [bruno])

        RosterRelink.relink([pf], linkedWith: [bruno], people: [renamed], author: "Tuur")

        assertKept(pf, linkedTo: "[[Bruno Almeida")
        XCTAssertFalse(pf.sanitised?.contains("Bruno Costa") == true, "the old name is gone")
        XCTAssertEqual(pf.enhancedCopyedit, edited, "adopted de-linked, under the roster it was typed with")
    }

    func testAnEditFromBeforeThisFixIsHealedOnTheNextRelink() throws {
        // Rows edited on an older build: `sanitised` holds the edit, the copy-edit the old polish.
        let pf = processedRow()
        typeOnTheMac(pf, people: [bruno])
        XCTAssertEqual(pf.enhancedCopyedit, polish)

        let changed = RosterRelink.relink([pf], linkedWith: [bruno], people: [bruno, lotte], author: "Tuur")

        XCTAssertTrue(changed.isEmpty || changed == [pf.id])
        assertKept(pf, linkedTo: "[[Bruno Costa")
    }

    func testAnUneditedRowKeepsItsPolishByteForByte() {
        let pf = processedRow()
        RosterRelink.relink([pf], linkedWith: [bruno], people: [renamed], author: "Tuur")
        XCTAssertEqual(pf.enhancedCopyedit, polish, "no edit, so the polish is not rewritten")
        XCTAssertTrue(pf.sanitised?.contains("[[Bruno Almeida") == true)
    }

    // MARK: - a phone edit's recompile (same rule)

    /// The memo as the phone holds it, with a tag he just added there.
    private func phoneMemoWithNewTag(_ pf: PipelineFile) throws -> Memo {
        let m = Memo(id: try XCTUnwrap(UUID(uuidString: pf.id)), audioFilename: pf.filename, recordedAt: Date(),
                     transcript: pf.transcript, transcriptStatus: .done, transcriptConfidence: 0.9,
                     significance: 0.6)
        m.tags = ["studio"]
        return m
    }

    func testAPhoneTagEditKeepsAMacEditStillInThePause() throws {
        let pf = processedRow()
        typeOnTheMac(pf, people: [bruno])

        XCTAssertTrue(MemoCloudUpdate.apply(memo: try phoneMemoWithNewTag(pf), enhancement: nil, to: pf,
                                            people: [bruno], author: "Tuur", thisDeviceID: "mac-test"))

        XCTAssertEqual(pf.tags, ["studio"], "the phone's tag landed")
        assertKept(pf, linkedTo: "[[Bruno Costa")
        XCTAssertEqual(pf.enhancedCopyedit, edited)
    }

    func testAPhoneTagEditKeepsAWrittenBackMacEdit() throws {
        let pf = processedRow()
        let ctx = try cloud(for: pf)
        typeOnTheMac(pf, people: [bruno])
        try writeBack(pf, people: [bruno], cloud: ctx)
        let id = try XCTUnwrap(UUID(uuidString: pf.id))
        let own = try XCTUnwrap(try ctx.fetch(FetchDescriptor<MemoEnhancement>(predicate: #Predicate { $0.memoID == id })).first)

        MemoCloudUpdate.apply(memo: try phoneMemoWithNewTag(pf), enhancement: own, to: pf,
                              people: [bruno], author: "Tuur", thisDeviceID: "mac-test")

        assertKept(pf, linkedTo: "[[Bruno Costa")
    }

    // MARK: - the Redo write-back (same rule)

    func testARedoWriteBackSendsHisWordsNotTheOldPolish() throws {
        // `ProcessingCoordinator.writeBackEnhancement`: settle, then upsert the copy-edit.
        let pf = processedRow()
        let ctx = try cloud(for: pf)
        typeOnTheMac(pf, people: [bruno])
        pf.enhancedTitle = "Rent and kiln"   // the Redo title

        MacEditRoundTrip.settle(pf, linkedWith: [bruno])
        try MacCloudWriteBack.upsert(for: pf, into: ctx, deviceID: "mac-test", passRan: true)

        XCTAssertEqual(try cloudCopy(pf, ctx), edited, "the phone gets his edit, not the polish it replaced")
    }

    func testSettleLeavesAFreshPolishAlone() throws {
        // After a pass or a Redo copy-edit the body is derived from the new copy-edit: no edit.
        let pf = processedRow()
        MacEditRoundTrip.settle(pf, linkedWith: [bruno])
        XCTAssertEqual(pf.enhancedCopyedit, polish)
    }

    // MARK: - the open note (same rule)

    func testTheOpenNoteKeepsAnEditOnASyncedRosterChange() {
        let center = NotificationCenter()
        var roster = [bruno]
        let refresh = OpenNoteRosterRefresh(center: center, people: { roster }, author: { "Tuur" })
        let pf = processedRow()
        refresh.open(pf)
        typeOnTheMac(pf, people: [bruno])

        roster = [renamed]
        center.post(name: .namesDidChangeFromSync, object: nil)

        XCTAssertEqual(refresh.refreshCount, 1)
        assertKept(pf, linkedTo: "[[Bruno Almeida")
    }
}
