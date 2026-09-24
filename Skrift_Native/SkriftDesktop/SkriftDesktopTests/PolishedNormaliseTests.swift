import XCTest
import SwiftData
import Foundation

/// Q40 (gate+): the one-time body normalisation (C10, D4) also covers the POLISHED text — the
/// Mac's local `enhancedCopyedit` and the synced `MemoEnhancement.copyedit` — under its own
/// once-flag; and v2 commit (C19) drops the leading run v1's wrap left after a picture
/// paragraph (`one.\n\n[[img_001]]\n\n That`). The synced row's rewrite writes the text only:
/// `enhancedAt`, the author id and `processedAt` stay, and no edit vector / head moves.
final class PolishedNormaliseTests: XCTestCase {

    // MARK: fixtures

    private func tempLedger() -> BodyNormaliseMigration.Ledger {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("q40-ledger-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return BodyNormaliseMigration.Ledger(directory: dir)
    }

    private func cloudContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Memo.self, MemoAsset.self, MemoEnhancement.self, MemoEditHead.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    private func manifest(_ n: Int) -> [ImageManifestEntry] {
        (0..<n).map { _ in ImageManifestEntry(filename: "", offsetSeconds: 0) }
    }

    private func file(id: UUID, manifestCount: Int) throws -> PipelineFile {
        let pf = PipelineFile(id: id.uuidString, filename: "memo_\(id.uuidString).m4a", path: "/tmp/q40", size: 0, sourceType: .audio)
        pf.audioMetadataJSON = try JSONSerialization.data(withJSONObject: [
            "imageManifest": (0..<manifestCount).map { _ in ["filename": "p.jpg", "offsetSeconds": 1.7] },
            "recordedAt": "2026-07-19T13:00:00Z"])
        return pf
    }

    /// The conv-with-picture corpus note: the v1 golden (the wrap with its leading run) and
    /// the stored inline-marker transcript, as polished text.
    private func convWithPicture() throws -> (golden: String, stored: String, count: Int) {
        let golden = try String(contentsOf: BodyGoldenTests.goldenDir.appendingPathComponent("conv-with-picture.txt"), encoding: .utf8)
        let noteURL = BodyGoldenTests.corpusRoot.appendingPathComponent("notes/089-conv-with-picture/note.json")
        let n = try JSONDecoder().decode(CorpusSeed.Note.self, from: Data(contentsOf: noteURL))
        let meta = try XCTUnwrap(n.metadata.data.flatMap { try? JSONDecoder().decode(MemoMetadata.self, from: $0) })
        return (golden, try XCTUnwrap(n.transcript), meta.imageManifest?.count ?? 0)
    }

    private func assertV2(_ out: String, from old: String, count: Int, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(BodyNormaliseMigration.needsNormalise(out, manifestCount: count), "still breaks C10:\n\(out)", file: file, line: line)
        XCTAssertTrue(BodyNormaliseMigration.preserves(old, out), "words or markers changed:\n\(out)", file: file, line: line)
        XCTAssertNil(out.range(of: #"\]\]\n\n[ \t]"#, options: .regularExpression), "leading run after a picture:\n\(out)", file: file, line: line)
    }

    // MARK: (2) v2 commit drops v1's leading run

    func testCommitStripsTheLeadingRunAfterAPictureParagraph() {
        let out = BodyV2.committed(.init(text: "one.\n\n[[img_001]]\n\n That", manifest: manifest(1), source: .typed))
        XCTAssertEqual(out, "one.\n\n[[img_001]]\n\nThat")
        let two = BodyV2.committed(.init(text: "one.\n\n[[img_001]]\n\n\t  That", manifest: manifest(1), source: .typed))
        XCTAssertEqual(two, "one.\n\n[[img_001]]\n\nThat")
    }

    func testCommitKeepsAListItemsIndentAfterAPicture() {
        XCTAssertEqual(BodyV2Text.normalised("x\n\n[[img_001]]\n\n   - nested"), "x\n\n[[img_001]]\n\n   - nested")
    }

    func testCommitLeavesOtherLeadingRunsAsBefore() {
        // Only the paragraph after a picture changes; C19's other lines are Q23's contract.
        XCTAssertEqual(BodyV2Text.normalised("Line one\n\n\tIndented"), "Line one\n\n Indented")
    }

    func testMachineRewriteNeedsNoMarkerMoveFallback() {
        // The migration's machine path is v2 commit alone now.
        let body = "one.\n\n[[img_001]]\n\n That was it."
        let committed = BodyV2.committed(.init(text: body, manifest: manifest(1), source: .typed))
        XCTAssertEqual(BodyNormaliseMigration.rewrite(body, manifestCount: 1, machineText: true), committed)
        XCTAssertEqual(committed, "one.\n\n[[img_001]]\n\nThat was it.")
    }

    // MARK: conv-with-picture

    func testConvWithPicturePolishComesOutV2BothWays() throws {
        let c = try convWithPicture()
        XCTAssertEqual(c.count, 1)
        for body in [c.golden, c.stored] {
            XCTAssertTrue(BodyNormaliseMigration.needsNormalise(body, manifestCount: c.count), "fixture is not v1-shaped:\n\(body)")
            for machine in [true, false] {
                let out = try XCTUnwrap(BodyNormaliseMigration.rewrite(body, manifestCount: c.count, machineText: machine),
                                        "machine=\(machine) left unnormalised")
                assertV2(out, from: body, count: c.count)
                XCTAssertTrue(out.contains("Look at the edge on this one.\n\n[[img_001]]\n\nThat is the green again."),
                              "picture after the sentence, inside the turn (C169):\n\(out)")
                XCTAssertEqual(out.components(separatedBy: "**Lotte Vos:**").count - 1, 2, "speaker turns kept")
                XCTAssertNil(BodyNormaliseMigration.rewrite(out, manifestCount: c.count, machineText: machine), "second run rewrote")
            }
        }
    }

    // MARK: (1) the Mac: local copy-edit + the synced row

    func testMacPolishLocalAndSyncedRowRewrittenOnceTextOnly() throws {
        let c = try convWithPicture()
        let ledger = tempLedger()
        let ctx = try cloudContext()
        let id = UUID()
        let memo = Memo(id: id, audioFilename: "memo_\(id.uuidString).m4a")
        ctx.insert(memo)
        let stamp = Date(timeIntervalSince1970: 1_784_000_000)
        let row = MemoEnhancement(memoID: id, copyedit: c.golden, title: "Green", summary: "Iron.",
                                  enhancedByDeviceID: "other-mac", enhancedAt: stamp, processedAt: stamp)
        ctx.insert(row)
        try ctx.save()
        let vectorBefore = memo.editVectorData
        let editedBefore = memo.editedAt

        let pf = try file(id: id, manifestCount: c.count)
        pf.transcript = "Look at the edge on this one. That is the green again."   // no marker: body pass is clean
        pf.enhancedCopyedit = c.golden
        pf.sanitised = c.golden

        pf.normaliseBodyOnce(ledger: ledger, cloud: ctx)
        let local = try XCTUnwrap(pf.enhancedCopyedit)
        assertV2(local, from: c.golden, count: c.count)
        XCTAssertEqual(row.copyedit, local, "the synced row gets the identical rewrite")
        assertV2(try XCTUnwrap(pf.sanitised), from: c.golden, count: c.count)

        // Text only: LWW key, author, pass stamp, edit vector, heads, editedAt all untouched.
        XCTAssertEqual(row.enhancedAt, stamp)
        XCTAssertEqual(row.enhancedByDeviceID, "other-mac")
        XCTAssertEqual(row.processedAt, stamp)
        XCTAssertEqual(memo.editVectorData, vectorBefore)
        XCTAssertEqual(memo.editedAt, editedBefore)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<MemoEditHead>()).count, 0)

        // Recoverable: the ledger holds both originals.
        let record = try XCTUnwrap(ledger.record(for: BodyNormaliseMigration.polishedKey(pf.id)))
        XCTAssertEqual(record.outcome, .rewritten)
        XCTAssertEqual(record.fields["enhancedCopyedit"]?.original, c.golden)
        XCTAssertEqual(record.fields["cloudCopyedit"]?.original, c.golden)

        // Once: a v1 polish that arrives afterwards is left alone.
        row.copyedit = c.golden
        XCTAssertNil(pf.normalisePolishOnce(ledger: ledger, cloud: ctx))
        XCTAssertEqual(row.copyedit, c.golden)
    }

    func testPolishArrivingAfterFirstOpenStillGetsItsPass() throws {
        let c = try convWithPicture()
        let ledger = tempLedger()
        let pf = try file(id: UUID(), manifestCount: c.count)
        pf.transcript = c.stored
        XCTAssertEqual(pf.normaliseBodyOnce(ledger: ledger), .rewritten)
        XCTAssertFalse(ledger.hasRun(BodyNormaliseMigration.polishedKey(pf.id)), "no polish yet must not burn the flag")

        pf.enhancedCopyedit = c.golden
        XCTAssertNil(pf.normaliseBodyOnce(ledger: ledger), "the body pass already ran")
        let out = try XCTUnwrap(pf.enhancedCopyedit)
        XCTAssertNotEqual(out, c.golden)
        assertV2(out, from: c.golden, count: c.count)
    }

    func testUndoPutsBackBothPolishedCopies() throws {
        let c = try convWithPicture()
        let ledger = tempLedger()
        let ctx = try cloudContext()
        let id = UUID()
        ctx.insert(Memo(id: id, audioFilename: "memo_\(id.uuidString).m4a"))
        let row = MemoEnhancement(memoID: id, copyedit: c.golden, enhancedByDeviceID: "mac")
        ctx.insert(row)
        try ctx.save()
        let pf = try file(id: id, manifestCount: c.count)
        pf.enhancedCopyedit = c.golden

        XCTAssertEqual(pf.normalisePolishOnce(ledger: ledger, cloud: ctx), .rewritten)
        XCTAssertTrue(pf.undoBodyNormalise(ledger: ledger, cloud: ctx))
        XCTAssertEqual(pf.enhancedCopyedit, c.golden)
        XCTAssertEqual(row.copyedit, c.golden)
        XCTAssertNil(pf.normalisePolishOnce(ledger: ledger, cloud: ctx), "an undone polish is never migrated again")
        XCTAssertEqual(ledger.record(for: BodyNormaliseMigration.polishedKey(pf.id))?.outcome, .undone)
    }

    func testEditAfterMigrationWinsOverUndo() throws {
        let c = try convWithPicture()
        let ledger = tempLedger()
        let pf = try file(id: UUID(), manifestCount: c.count)
        pf.enhancedCopyedit = c.golden
        pf.normalisePolishOnce(ledger: ledger)
        pf.enhancedCopyedit = "He rewrote it.\n\n[[img_001]]"
        XCTAssertFalse(pf.undoBodyNormalise(ledger: ledger))
        XCTAssertEqual(pf.enhancedCopyedit, "He rewrote it.\n\n[[img_001]]")
    }

    // MARK: (1) the phone's shape: the shared pass over a MemoEnhancement row

    func testSharedPolishedPassOverAnEnhancementRow() throws {
        let c = try convWithPicture()
        let ledger = tempLedger()
        let stamp = Date(timeIntervalSince1970: 1_784_000_000)
        let e = MemoEnhancement(memoID: UUID(), copyedit: c.stored, enhancedByDeviceID: "mac", enhancedAt: stamp)
        let body = BodyNormaliseMigration.Body(name: "copyedit", get: { e.copyedit }, set: { e.copyedit = $0 })
        let key = e.memoID.uuidString

        XCTAssertEqual(BodyNormaliseMigration.runPolished(id: key, bodies: [body], manifestCount: c.count,
                                                          legacyShape: false, ledger: ledger), .rewritten)
        assertV2(e.copyedit, from: c.stored, count: c.count)
        XCTAssertEqual(e.enhancedAt, stamp)
        XCTAssertEqual(e.enhancedByDeviceID, "mac")
        XCTAssertNil(BodyNormaliseMigration.runPolished(id: key, bodies: [body], manifestCount: c.count,
                                                        legacyShape: false, ledger: ledger))
        XCTAssertFalse(ledger.hasRun(key), "the body's own flag is separate")

        // The phone's and the Mac's rewrite of the same synced text are identical.
        let mac = BodyNormaliseMigration.rewrite(c.stored, manifestCount: c.count, machineText: false)
        XCTAssertEqual(e.copyedit, mac)
    }

    func testEmptyPolishIsNotFlaggedAndLegacyShapeIsLeftAlone() {
        let ledger = tempLedger()
        var text = ""
        let body = BodyNormaliseMigration.Body(name: "copyedit", get: { text }, set: { text = $0 })
        XCTAssertNil(BodyNormaliseMigration.runPolished(id: "n", bodies: [body], manifestCount: 1, legacyShape: false, ledger: ledger))
        XCTAssertFalse(ledger.hasRun(BodyNormaliseMigration.polishedKey("n")))

        text = "We sat\n\n[[img_001]]\n\n down."
        XCTAssertEqual(BodyNormaliseMigration.runPolished(id: "n", bodies: [body], manifestCount: 1, legacyShape: true, ledger: ledger), .legacyShape)
        XCTAssertEqual(text, "We sat\n\n[[img_001]]\n\n down.")
    }
}
