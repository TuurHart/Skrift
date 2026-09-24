import XCTest
import SwiftData

/// C98 / C242 / D139: a same-note edit on two devices that meet after being apart is a
/// CONFLICT record, never a silent overwrite. Two in-memory stores stand in for the iPhone
/// and the Mac; `meet` plays CloudKit: the `Memo` row merges newest-wins (the silent
/// overwrite this feature exists to catch) and each device's `MemoEditHead` is copied as-is.
final class EditConflictTests: XCTestCase {

    private let phone = "PHONE-DEVICE", mac = "MAC-DEVICE"

    private func store() throws -> ModelContext {
        let c = try ModelContainer(for: Memo.self, MemoAsset.self, MemoEditHead.self,
                                   configurations: ModelConfiguration(isStoredInMemoryOnly: true,
                                                                      cloudKitDatabase: .none))
        return ModelContext(c)
    }

    private func memos(_ ctx: ModelContext) -> [Memo] { (try? ctx.fetch(FetchDescriptor<Memo>())) ?? [] }
    private func memo(_ id: UUID, _ ctx: ModelContext) -> Memo? { memos(ctx).first { $0.id == id } }

    /// One note, identical on both devices (it synced before they went apart).
    private func seed(_ a: ModelContext, _ b: ModelContext) throws -> UUID {
        let id = UUID()
        let t0 = Date(timeIntervalSince1970: 1_000)
        for ctx in [a, b] {
            let m = Memo(id: id, recordedAt: t0, tags: ["house"], title: "Tiles for the bathroom floor",
                         transcript: "The hexagon ones from the shop.", transcriptStatus: .done,
                         significance: 0.6, createdAt: t0, recordingDeviceID: phone)
            ctx.insert(m)
            try ctx.save()
        }
        return id
    }

    /// CloudKit, played by hand. `Memo`: newest `editedAt` overwrites the older row's words +
    /// vector (the loss the heads prevent). Heads: copied per (memo, device), never merged.
    private func meet(_ a: ModelContext, _ b: ModelContext) throws {
        for (src, dst) in [(a, b), (b, a)] {
            for m in memos(src) {
                guard let d = memo(m.id, dst) else {
                    let n = Memo(id: m.id, recordedAt: m.recordedAt, tags: m.tags, title: m.title,
                                 transcript: m.transcript, transcriptStatus: m.transcriptStatus,
                                 significance: m.significance, deletedAt: m.deletedAt,
                                 createdAt: m.createdAt, editedAt: m.editedAt)
                    n.editVectorData = m.editVectorData; n.editStampHash = m.editStampHash
                    n.replacedAt = m.replacedAt; n.trashSeenAt = m.trashSeenAt
                    dst.insert(n); continue
                }
                if (m.editedAt ?? .distantPast) > (d.editedAt ?? .distantPast) {
                    d.title = m.title; d.transcript = m.transcript; d.tags = m.tags
                    d.editVectorData = m.editVectorData; d.editStampHash = m.editStampHash
                    d.editedAt = m.editedAt
                }
                if m.significance != d.significance { d.significance = max(m.significance, d.significance) }
            }
            let srcHeads = (try? src.fetch(FetchDescriptor<MemoEditHead>())) ?? []
            let dstHeads = (try? dst.fetch(FetchDescriptor<MemoEditHead>())) ?? []
            for h in srcHeads {
                if let d = dstHeads.first(where: { $0.memoID == h.memoID && $0.deviceID == h.deviceID }) {
                    if h.editedAt > d.editedAt {
                        d.vectorData = h.vectorData; d.baseHash = h.baseHash; d.title = h.title
                        d.body = h.body; d.tags = h.tags; d.editedAt = h.editedAt; d.deviceKind = h.deviceKind
                    }
                } else {
                    dst.insert(MemoEditHead(memoID: h.memoID, deviceID: h.deviceID, deviceKind: h.deviceKind,
                                            vector: h.vector, baseHash: h.baseHash, title: h.title,
                                            body: h.body, tags: h.tags, editedAt: h.editedAt))
                }
            }
            try src.save(); try dst.save()
        }
    }

    private func edit(_ id: UUID, _ ctx: ModelContext, device: String, kind: String, at t: TimeInterval,
                      body: String? = nil, title: String? = nil, tags: [String]? = nil) {
        let m = memo(id, ctx)!
        if let body { m.transcript = body }
        if let title { m.title = title }
        if let tags { m.tags = tags }
        m.editedAt = Date(timeIntervalSince1970: t)
        EditConflicts.recordEdit(m, in: ctx, device: device, kind: kind, now: Date(timeIntervalSince1970: t))
    }

    // MARK: - C98's check

    func testDivergingEditsBecomeAConflictRecordAndNothingIsLost() throws {
        let p = try store(), m = try store()
        let id = try seed(p, m)
        edit(id, p, device: phone, kind: "iPhone", at: 2_000,
             body: "The hexagon ones, but only in the warm grey. Ask about the grout.")
        edit(id, m, device: mac, kind: "Mac", at: 1_500,
             body: "The hexagon ones in the warm grey or the sand.", tags: ["house", "renovation"])
        try meet(p, m)

        for (ctx, here) in [(p, phone), (m, mac)] {
            let note = memo(id, ctx)!
            let c = try XCTUnwrap(EditConflicts.conflict(for: note, in: ctx, thisDevice: here),
                                  "the meeting must yield a conflict record on \(here)")
            let bodies = Set([c.local.body, c.other.body])
            XCTAssertEqual(bodies, ["The hexagon ones, but only in the warm grey. Ask about the grout.",
                                    "The hexagon ones in the warm grey or the sand."],
                           "both versions survive the newest-wins merge")
            XCTAssertEqual(c.local.deviceID, here, "the prompt leads with this device's version")
            XCTAssertEqual(EditConflicts.conflictedIDs(in: ctx, memos: memos(ctx), thisDevice: here), [id])
        }
        // The Mac's tags travel with its version, not lost to the phone's newer row.
        let onPhone = EditConflicts.conflict(for: memo(id, p)!, in: p, thisDevice: phone)!
        XCTAssertEqual(onPhone.other.tags, ["house", "renovation"])
        XCTAssertEqual(onPhone.other.deviceKind, "Mac")
    }

    func testEditsThatSawEachOtherNeverConflict() throws {
        let p = try store(), m = try store()
        let id = try seed(p, m)
        edit(id, p, device: phone, kind: "iPhone", at: 2_000, body: "First phone edit.")
        try meet(p, m)
        edit(id, m, device: mac, kind: "Mac", at: 3_000, body: "Mac edit on top.")
        try meet(p, m)
        edit(id, p, device: phone, kind: "iPhone", at: 4_000, body: "Phone again.")
        edit(id, p, device: phone, kind: "iPhone", at: 4_100, body: "Phone again, twice.")
        try meet(p, m)
        XCTAssertNil(EditConflicts.conflict(for: memo(id, p)!, in: p, thisDevice: phone))
        XCTAssertNil(EditConflicts.conflict(for: memo(id, m)!, in: m, thisDevice: mac))
        XCTAssertEqual(memo(id, m)?.transcript, "Phone again, twice.")
    }

    func testRatingIsNotAWordsEditAndStaysNewestWins() throws {
        let p = try store(), m = try store()
        let id = try seed(p, m)
        // Rating never calls `markEdited`, so it never stamps; a words edit on the phone first
        // proves an unchanged stamp is a no-op when the rating moves afterwards.
        edit(id, p, device: phone, kind: "iPhone", at: 1_200, body: "The hexagon ones from the shop.")
        memo(id, p)!.significance = 0.9
        XCTAssertFalse(EditConflicts.recordEdit(memo(id, p)!, in: p, device: phone),
                       "no words changed since the last stamp → no vector bump")
        try meet(p, m)
        edit(id, m, device: mac, kind: "Mac", at: 1_500, body: "Mac words.")
        try meet(p, m)
        XCTAssertNil(EditConflicts.conflict(for: memo(id, p)!, in: p, thisDevice: phone))
        XCTAssertEqual(memo(id, p)?.transcript, "Mac words.")
    }

    func testNewNotesNeverConflict() throws {
        let p = try store(), m = try store()
        let a = Memo(transcript: "Phone note", transcriptStatus: .done)
        let b = Memo(transcript: "Mac note", transcriptStatus: .done)
        p.insert(a); m.insert(b); try p.save(); try m.save()
        try meet(p, m)
        XCTAssertEqual(memos(p).count, 2)
        XCTAssertTrue(EditConflicts.conflictedIDs(in: p, memos: memos(p), thisDevice: phone).isEmpty)
    }

    // MARK: - D139's picks

    func testKeepThisDeviceMovesTheOtherToRecentlyDeletedAsReplaced() throws {
        let p = try store(), m = try store()
        let id = try seed(p, m)
        edit(id, p, device: phone, kind: "iPhone", at: 2_000, body: "Phone words.")
        edit(id, m, device: mac, kind: "Mac", at: 1_500, body: "Mac words.", tags: ["house", "renovation"])
        try meet(p, m)
        let note = memo(id, m)!
        let c = EditConflicts.conflict(for: note, in: m, thisDevice: mac)!
        let copy = try EditConflicts.resolve(c, choice: .keepThis, memo: note, in: m, device: mac, kind: "Mac",
                                             now: Date(timeIntervalSince1970: 5_000))
        XCTAssertEqual(note.transcript, "Mac words.")
        XCTAssertEqual(note.tags, ["house", "renovation"])
        XCTAssertEqual(copy.transcript, "Phone words.", "the unkept version is kept, not lost")
        XCTAssertNotNil(copy.deletedAt, "…in Recently Deleted")
        XCTAssertNotNil(copy.replacedAt, "…as a replaced row")
        XCTAssertEqual(copy.title, "Tiles for the bathroom floor (iPhone copy)")
        XCTAssertEqual(copy.audioFilename, "", "the copy never shares the original's audio file")
        XCTAssertNil(EditConflicts.conflict(for: note, in: m, thisDevice: mac))
        // Picking on one device settles it on both, at the next sync.
        try meet(p, m)
        XCTAssertNil(EditConflicts.conflict(for: memo(id, p)!, in: p, thisDevice: phone))
        XCTAssertEqual(memo(id, p)?.transcript, "Mac words.")
    }

    func testKeepBothMakesTheOtherItsOwnNote() throws {
        let p = try store(), m = try store()
        let id = try seed(p, m)
        edit(id, p, device: phone, kind: "iPhone", at: 2_000, body: "Phone words.")
        edit(id, m, device: mac, kind: "Mac", at: 1_500, body: "Mac words.")
        try meet(p, m)
        let note = memo(id, p)!
        let c = EditConflicts.conflict(for: note, in: p, thisDevice: phone)!
        let copy = try EditConflicts.resolve(c, choice: .keepBoth, memo: note, in: p, device: phone,
                                             kind: "iPhone", now: Date(timeIntervalSince1970: 5_000))
        XCTAssertEqual(note.transcript, "Phone words.")
        XCTAssertEqual(copy.transcript, "Mac words.")
        XCTAssertNil(copy.deletedAt, "keep both = two live notes")
        XCTAssertEqual(copy.significance, note.significance)
        XCTAssertEqual(copy.recordedAt, note.recordedAt, "the copy lands under the original, same day")
        try meet(p, m)
        XCTAssertTrue(EditConflicts.conflictedIDs(in: m, memos: memos(m), thisDevice: mac).isEmpty)
        XCTAssertEqual(memos(m).count, 2)
    }

    func testEditsAreFrozenWhileInConflict() throws {
        let p = try store(), m = try store()
        let id = try seed(p, m)
        edit(id, p, device: phone, kind: "iPhone", at: 2_000, body: "Phone words.")
        edit(id, m, device: mac, kind: "Mac", at: 1_500, body: "Mac words.")
        try meet(p, m)
        let note = memo(id, p)!
        note.transcript = "A third version"
        XCTAssertFalse(EditConflicts.recordEdit(note, in: p, device: phone),
                       "a conflicted note's heads are frozen until he picks")
    }

    func testVectorOrder() {
        XCTAssertEqual(EditVectors.compare(["a": 1], ["a": 1, "b": 1]), .before)
        XCTAssertEqual(EditVectors.compare(["a": 2, "b": 1], ["a": 1, "b": 1]), .after)
        XCTAssertEqual(EditVectors.compare(["a": 2], ["b": 1]), .concurrent)
        XCTAssertEqual(EditVectors.compare([:], [:]), .equal)
    }
}
