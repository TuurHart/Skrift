import XCTest
import SwiftData
import Foundation

/// Q38 (C98 / C242, gate+): on a Mac-polished note the body he edits is the POLISHED text
/// (`MemoEnhancement.copyedit`), and that row is newest-wins too. Two devices editing it apart
/// must yield a conflict record, not a silent overwrite. The Mac's own polish write and the
/// one-time body normalisation are not user edits and must never make one.
///
/// Two in-memory stores stand in for the iPhone and the Mac; `meet` plays CloudKit: the `Memo`
/// row and the enhancement row merge newest-wins (the loss the heads prevent) and each device's
/// `MemoEditHead` is copied as-is.
final class PolishedEditConflictTests: XCTestCase {

    private let phone = "PHONE-DEVICE", mac = "MAC-DEVICE"
    private let seedPolish = "The hexagon tiles from the shop, in grey."

    private func store() throws -> ModelContext {
        let c = try ModelContainer(for: Memo.self, MemoAsset.self, MemoEnhancement.self, MemoEditHead.self,
                                   configurations: ModelConfiguration(isStoredInMemoryOnly: true,
                                                                      cloudKitDatabase: .none))
        return ModelContext(c)
    }

    private func memos(_ ctx: ModelContext) -> [Memo] { (try? ctx.fetch(FetchDescriptor<Memo>())) ?? [] }
    private func memo(_ id: UUID, _ ctx: ModelContext) -> Memo? { memos(ctx).first { $0.id == id } }
    private func enhancements(_ ctx: ModelContext) -> [MemoEnhancement] {
        (try? ctx.fetch(FetchDescriptor<MemoEnhancement>())) ?? []
    }
    private func polish(_ id: UUID, _ ctx: ModelContext) -> String? { EditConflicts.polishedBody(for: id, in: ctx) }
    private func heads(_ ctx: ModelContext) -> [MemoEditHead] { (try? ctx.fetch(FetchDescriptor<MemoEditHead>())) ?? [] }

    /// One polished note, identical on both devices (it synced before they went apart).
    private func seed(_ a: ModelContext, _ b: ModelContext, polished: String? = nil) throws -> UUID {
        let id = UUID()
        let t0 = Date(timeIntervalSince1970: 1_000)
        for ctx in [a, b] {
            let m = Memo(id: id, audioFilename: "memo_\(id.uuidString).m4a", recordedAt: t0, tags: ["house"],
                         title: "Tiles for the bathroom floor",
                         transcript: "uh the hexagon ones from the shop in grey", transcriptStatus: .done,
                         significance: 0.6, createdAt: t0, recordingDeviceID: phone)
            // Its words were stamped once before (a note never stamped counts its first touch
            // as an edit by Q29's design, whatever the polish does).
            m.editStampHash = EditConflicts.hash(m)
            ctx.insert(m)
            ctx.insert(MemoEnhancement(memoID: id, copyedit: polished ?? seedPolish, title: "Bathroom tiles",
                                       summary: "Hexagon tiles.", enhancedByDeviceID: mac, enhancedAt: t0,
                                       processedAt: t0))
            try ctx.save()
        }
        return id
    }

    /// CloudKit, played by hand (see `EditConflictTests.meet`), plus the enhancement row.
    private func meet(_ a: ModelContext, _ b: ModelContext) throws {
        for (src, dst) in [(a, b), (b, a)] {
            for m in memos(src) {
                guard let d = memo(m.id, dst) else {
                    let n = Memo(id: m.id, recordedAt: m.recordedAt, tags: m.tags, title: m.title,
                                 transcript: m.transcript, transcriptStatus: m.transcriptStatus,
                                 significance: m.significance, deletedAt: m.deletedAt,
                                 createdAt: m.createdAt, editedAt: m.editedAt)
                    n.editVectorData = m.editVectorData; n.editStampHash = m.editStampHash
                    n.polishStampHash = m.polishStampHash
                    n.replacedAt = m.replacedAt; n.trashSeenAt = m.trashSeenAt
                    dst.insert(n); continue
                }
                if (m.editedAt ?? .distantPast) > (d.editedAt ?? .distantPast) {
                    d.title = m.title; d.transcript = m.transcript; d.tags = m.tags
                    d.editVectorData = m.editVectorData; d.editStampHash = m.editStampHash
                    d.polishStampHash = m.polishStampHash
                    d.editedAt = m.editedAt
                }
            }
            let dstEnh = enhancements(dst)
            for e in enhancements(src) {
                if let d = dstEnh.first(where: { $0.memoID == e.memoID }) {
                    if e.enhancedAt > d.enhancedAt {
                        d.copyedit = e.copyedit; d.title = e.title; d.summary = e.summary
                        d.enhancedByDeviceID = e.enhancedByDeviceID; d.enhancedAt = e.enhancedAt
                        d.processedAt = e.processedAt
                    }
                } else {
                    dst.insert(MemoEnhancement(memoID: e.memoID, copyedit: e.copyedit, title: e.title,
                                               summary: e.summary, enhancedByDeviceID: e.enhancedByDeviceID,
                                               enhancedAt: e.enhancedAt, processedAt: e.processedAt))
                }
            }
            let dstHeads = heads(dst)
            for h in heads(src) {
                if let d = dstHeads.first(where: { $0.memoID == h.memoID && $0.deviceID == h.deviceID }) {
                    if h.editedAt > d.editedAt {
                        d.vectorData = h.vectorData; d.baseHash = h.baseHash; d.title = h.title
                        d.body = h.body; d.tags = h.tags; d.editedAt = h.editedAt; d.deviceKind = h.deviceKind
                        d.polishedBody = h.polishedBody
                    }
                } else {
                    dst.insert(MemoEditHead(memoID: h.memoID, deviceID: h.deviceID, deviceKind: h.deviceKind,
                                            vector: h.vector, baseHash: h.baseHash, title: h.title,
                                            body: h.body, tags: h.tags, editedAt: h.editedAt,
                                            polishedBody: h.polishedBody))
                }
            }
            try src.save(); try dst.save()
        }
    }

    /// He types into the polished body on `device`: what the phone's polished binding and the
    /// Mac's edit write-back do (text + provenance on the enhancement, then the stamp).
    @discardableResult
    private func editPolish(_ id: UUID, _ ctx: ModelContext, device: String, kind: String,
                            at t: TimeInterval, _ text: String) -> Bool {
        let e = enhancements(ctx).first { $0.memoID == id }!
        e.copyedit = text
        e.enhancedByDeviceID = device
        e.enhancedAt = Date(timeIntervalSince1970: t)
        memo(id, ctx)!.editedAt = Date(timeIntervalSince1970: t)
        return EditConflicts.recordPolishedEdit(memo(id, ctx)!, in: ctx, device: device, kind: kind,
                                                now: Date(timeIntervalSince1970: t))
    }

    private func editTitle(_ id: UUID, _ ctx: ModelContext, device: String, kind: String,
                           at t: TimeInterval, _ title: String) {
        let m = memo(id, ctx)!
        m.title = title
        m.editedAt = Date(timeIntervalSince1970: t)
        EditConflicts.recordEdit(m, in: ctx, device: device, kind: kind, now: Date(timeIntervalSince1970: t))
    }

    // MARK: - C98's check on the polished body

    func testDivergingPolishedEditsBecomeAConflictRecordAndNothingIsLost() throws {
        let p = try store(), m = try store()
        let id = try seed(p, m)
        XCTAssertTrue(editPolish(id, p, device: phone, kind: "iPhone", at: 2_000,
                                 "The hexagon tiles, but only the warm grey. Ask about the grout."))
        XCTAssertTrue(editPolish(id, m, device: mac, kind: "Mac", at: 1_500,
                                 "The hexagon tiles in warm grey or sand."))
        try meet(p, m)
        // Without the heads this is the silent overwrite: the phone's newer row won everywhere.
        XCTAssertEqual(polish(id, m), "The hexagon tiles, but only the warm grey. Ask about the grout.")

        for (ctx, here) in [(p, phone), (m, mac)] {
            let c = try XCTUnwrap(EditConflicts.conflict(for: memo(id, ctx)!, in: ctx, thisDevice: here),
                                  "the meeting must yield a conflict record on \(here)")
            XCTAssertEqual(Set([c.local.polished, c.other.polished]),
                           ["The hexagon tiles, but only the warm grey. Ask about the grout.",
                            "The hexagon tiles in warm grey or sand."], "both polished versions survive")
            XCTAssertEqual(c.local.deviceID, here)
            XCTAssertEqual(c.local.shownBody, c.local.polished, "the prompt shows the text he edited")
            XCTAssertEqual(EditConflicts.conflictedIDs(in: ctx, memos: memos(ctx), thisDevice: here), [id])
        }
    }

    func testPolishedEditAgainstATitleEditIsAConflictToo() throws {
        let p = try store(), m = try store()
        let id = try seed(p, m)
        editPolish(id, p, device: phone, kind: "iPhone", at: 2_000, "Phone polish.")
        editTitle(id, m, device: mac, kind: "Mac", at: 1_500, "Mac title")
        try meet(p, m)
        let c = try XCTUnwrap(EditConflicts.conflict(for: memo(id, p)!, in: p, thisDevice: phone))
        XCTAssertEqual(c.local.polished, "Phone polish.")
        XCTAssertEqual(c.other.title, "Mac title")
        XCTAssertEqual(c.other.polished, seedPolish, "a words head carries the polish its device held")
    }

    func testPolishedEditsThatSawEachOtherNeverConflict() throws {
        let p = try store(), m = try store()
        let id = try seed(p, m)
        editPolish(id, p, device: phone, kind: "iPhone", at: 2_000, "Phone polish.")
        try meet(p, m)
        editPolish(id, m, device: mac, kind: "Mac", at: 3_000, "Mac polish on top.")
        try meet(p, m)
        editPolish(id, p, device: phone, kind: "iPhone", at: 4_000, "Phone again.")
        try meet(p, m)
        XCTAssertNil(EditConflicts.conflict(for: memo(id, p)!, in: p, thisDevice: phone))
        XCTAssertNil(EditConflicts.conflict(for: memo(id, m)!, in: m, thisDevice: mac))
        XCTAssertEqual(polish(id, m), "Phone again.")
    }

    func testAnUnchangedPolishIsNoEdit() throws {
        let p = try store(), m = try store()
        let id = try seed(p, m)
        XCTAssertTrue(editPolish(id, p, device: phone, kind: "iPhone", at: 2_000, "Phone polish."))
        XCTAssertFalse(EditConflicts.recordPolishedEdit(memo(id, p)!, in: p, device: phone),
                       "same polish as the last stamp → no vector bump")
        XCTAssertEqual(memo(id, p)!.editVector, [phone: 1])
    }

    func testPreQ38HeadsKeepTheirHash() {
        XCTAssertEqual(EditConflicts.hash(title: "t", body: "b", tags: ["x"], polished: nil),
                       EditConflicts.hash(title: "t", body: "b", tags: ["x"]))
        XCTAssertNotEqual(EditConflicts.hash(title: "t", body: "b", tags: ["x"], polished: "p"),
                          EditConflicts.hash(title: "t", body: "b", tags: ["x"]))
    }

    // MARK: - Not edits

    func testMigrationWriteIsNotAnEdit() throws {
        // The Q40 fixture: a v1-shaped polish that the one-time normalisation rewrites.
        let golden = try String(contentsOf: BodyGoldenTests.goldenDir.appendingPathComponent("conv-with-picture.txt"),
                                encoding: .utf8)
        let p = try store(), m = try store()
        let id = try seed(p, m, polished: golden)
        let pf = PipelineFile(id: id.uuidString, filename: "memo_\(id.uuidString).m4a", path: "/tmp/q38", size: 0,
                              sourceType: .audio)
        pf.audioMetadataJSON = try JSONSerialization.data(withJSONObject: [
            "imageManifest": [["filename": "p.jpg", "offsetSeconds": 1.7]], "recordedAt": "2026-07-19T13:00:00Z"])
        pf.enhancedCopyedit = golden
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("q38-ledger-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }

        // The phone edits the polished text while apart; the Mac only migrates it.
        editPolish(id, p, device: phone, kind: "iPhone", at: 2_000, "Phone polish.")
        XCTAssertEqual(pf.normalisePolishOnce(ledger: BodyNormaliseMigration.Ledger(directory: dir), cloud: m),
                       .rewritten)
        XCTAssertNotEqual(polish(id, m), golden, "the migration rewrote the synced polish")
        XCTAssertTrue(heads(m).isEmpty, "the migration wrote no head")
        XCTAssertNil(memo(id, m)!.editVectorData, "…and moved no vector")
        // A later words-neutral touch on the Mac (an audio trim's `markEdited`) is still no edit.
        XCTAssertFalse(EditConflicts.recordEdit(memo(id, m)!, in: m, device: mac))

        try meet(p, m)
        XCTAssertNil(EditConflicts.conflict(for: memo(id, p)!, in: p, thisDevice: phone))
        XCTAssertNil(EditConflicts.conflict(for: memo(id, m)!, in: m, thisDevice: mac))
        XCTAssertEqual(polish(id, m), "Phone polish.", "his edit wins over the migration, no prompt")
    }

    func testMacRePolishIsNotAnEdit() throws {
        let p = try store(), m = try store()
        let id = try seed(p, m)
        editPolish(id, p, device: phone, kind: "iPhone", at: 2_000, "Phone polish.")

        // The Mac runs a polish pass while apart: `MacCloudWriteBack.upsert` after the pass.
        let pf = PipelineFile(id: id.uuidString, filename: "memo_\(id.uuidString).m4a")
        pf.enhancedCopyedit = "A fresh Mac polish."
        pf.enhancedTitle = "Bathroom tiles"
        pf.enhancedSummary = "Hexagon tiles."
        pf.enhanceStatus = .done
        try MacCloudWriteBack.upsert(for: pf, into: m, deviceID: mac, now: Date(timeIntervalSince1970: 1_800),
                                     passRan: true)
        XCTAssertEqual(polish(id, m), "A fresh Mac polish.")
        XCTAssertTrue(heads(m).isEmpty, "the Mac's polish write is its output, not a user edit")
        XCTAssertFalse(EditConflicts.recordEdit(memo(id, m)!, in: m, device: mac),
                       "a words-neutral touch after the re-polish is still no edit")

        try meet(p, m)
        XCTAssertNil(EditConflicts.conflict(for: memo(id, p)!, in: p, thisDevice: phone))
        XCTAssertNil(EditConflicts.conflict(for: memo(id, m)!, in: m, thisDevice: mac))
    }

    // MARK: - D139's picks on the polished body

    func testKeepBothCopiesThePolishedText() throws {
        let p = try store(), m = try store()
        let id = try seed(p, m)
        editPolish(id, p, device: phone, kind: "iPhone", at: 2_000, "Phone polish.")
        editPolish(id, m, device: mac, kind: "Mac", at: 1_500, "Mac polish.")
        try meet(p, m)
        let note = memo(id, p)!
        let c = try XCTUnwrap(EditConflicts.conflict(for: note, in: p, thisDevice: phone))
        let copy = try EditConflicts.resolve(c, choice: .keepBoth, memo: note, in: p, device: phone,
                                             kind: "iPhone", now: Date(timeIntervalSince1970: 5_000))
        XCTAssertEqual(polish(id, p), "Phone polish.")
        XCTAssertEqual(polish(copy.id, p), "Mac polish.", "the copy carries the other polished text")
        let copyRow = try XCTUnwrap(enhancements(p).first { $0.memoID == copy.id })
        XCTAssertTrue(copyRow.isProcessed, "the copy is not re-polished over his text")
        XCTAssertNil(copy.deletedAt)
        try meet(p, m)
        XCTAssertTrue(EditConflicts.conflictedIDs(in: m, memos: memos(m), thisDevice: mac).isEmpty)
        XCTAssertEqual(polish(id, m), "Phone polish.")
        XCTAssertEqual(polish(copy.id, m), "Mac polish.")
    }

    func testKeepThisPutsTheKeptPolishOnTheNoteAndTheOtherInRecentlyDeleted() throws {
        let p = try store(), m = try store()
        let id = try seed(p, m)
        editPolish(id, p, device: phone, kind: "iPhone", at: 2_000, "Phone polish.")
        editPolish(id, m, device: mac, kind: "Mac", at: 1_500, "Mac polish.")
        try meet(p, m)
        XCTAssertEqual(polish(id, m), "Phone polish.", "newest-wins put the phone's text on the Mac")
        let note = memo(id, m)!
        let c = try XCTUnwrap(EditConflicts.conflict(for: note, in: m, thisDevice: mac))
        let copy = try EditConflicts.resolve(c, choice: .keepThis, memo: note, in: m, device: mac, kind: "Mac",
                                             now: Date(timeIntervalSince1970: 5_000))
        XCTAssertEqual(polish(id, m), "Mac polish.", "the kept polish is back on the note")
        XCTAssertEqual(polish(copy.id, m), "Phone polish.", "the unkept polish is recoverable")
        XCTAssertNotNil(copy.replacedAt)
        XCTAssertNil(EditConflicts.conflict(for: note, in: m, thisDevice: mac))
        try meet(p, m)
        XCTAssertNil(EditConflicts.conflict(for: memo(id, p)!, in: p, thisDevice: phone))
        XCTAssertEqual(polish(id, p), "Mac polish.", "the pick reaches the other device")
    }
}
