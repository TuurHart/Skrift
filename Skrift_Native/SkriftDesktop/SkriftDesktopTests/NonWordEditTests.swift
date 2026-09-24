import XCTest
import SwiftData

/// Q45 (C98, gate+): a non-word touch — audio trim, audio append's non-text part, voice
/// annotation audio, photo add/remove/markup, rating, lock, destination, name-linking — must
/// never stamp the words vector. `ConflictFirstTouchTests` (Q42) found this can't be fixed
/// inside `recordEdit` itself (a pre-Q29 note's first-ever touch has no `editStampHash` to
/// compare against, so it can't tell "no words changed" apart from "this IS the real edit").
/// The fix lives at the CALL SITE instead: every non-word caller now passes
/// `markEdited(stampWords: false)`, so `recordEdit` is never even invoked for that touch.
/// This proves the call-site gate, not `recordEdit`'s internals, is what keeps a pre-Q29 note
/// trimmed on one device — while another device genuinely edits its words — conflict-free.
final class NonWordEditTests: XCTestCase {

    private let phoneDevice = "PHONE-DEVICE", macDevice = "MAC-DEVICE"

    private func store() throws -> ModelContext {
        let c = try ModelContainer(for: Memo.self, MemoAsset.self, MemoEditHead.self,
                                   configurations: ModelConfiguration(isStoredInMemoryOnly: true,
                                                                      cloudKitDatabase: .none))
        return ModelContext(c)
    }

    private func memos(_ ctx: ModelContext) -> [Memo] { (try? ctx.fetch(FetchDescriptor<Memo>())) ?? [] }
    private func memo(_ id: UUID, _ ctx: ModelContext) -> Memo? { memos(ctx).first { $0.id == id } }

    /// A PRE-Q29 note, identical on both devices: never edited, so it carries no
    /// `editStampHash` and no `MemoEditHead` on either side — exactly the shape a note made
    /// the day before conflict detection shipped has today.
    private func seed(_ a: ModelContext, _ b: ModelContext) throws -> UUID {
        let id = UUID()
        let t0 = Date(timeIntervalSince1970: 1_000)
        for ctx in [a, b] {
            let m = Memo(id: id, recordedAt: t0, tags: ["house"], title: "Tiles for the bathroom floor",
                         transcript: "The hexagon ones from the shop.", transcriptStatus: .done,
                         significance: 0.6, createdAt: t0, recordingDeviceID: phoneDevice)
            ctx.insert(m)
            try ctx.save()
        }
        return id
    }

    /// CloudKit, played by hand (mirrors `EditConflictTests.meet`): the `Memo` row merges
    /// newest-`editedAt`-wins per field; `MemoEditHead` rows are copied per (memo, device),
    /// never merged — each device's own head survives the meeting untouched.
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

    /// A pre-Q29 note trimmed on the phone (a non-word touch, `stampWords: false`) while the
    /// Mac genuinely edits its title apart from it → meeting must NOT produce a conflict, and
    /// the Mac's real edit must survive (not be lost to the phone's untouched words).
    func testNonWordTouchOnAPreQ29NoteCausesNoConflictWithAGenuineWordEditElsewhere() throws {
        let phone = try store(), mac = try store()
        let id = try seed(phone, mac)

        // Phone: a non-word touch (stands in for an audio trim / lock / destination /
        // annotation / name-link — every real call site now uses this exact call).
        // No head is created: `stampWords: false` means `recordEdit` is never invoked.
        let p = memo(id, phone)!
        p.markEdited(Date(timeIntervalSince1970: 2_000), stampWords: false)
        try phone.save()

        // Mac: a genuine words edit, apart from the phone — this DOES stamp.
        let m = memo(id, mac)!
        m.title = "Tiles for the ensuite floor"
        m.markEdited(Date(timeIntervalSince1970: 3_000))
        XCTAssertTrue(EditConflicts.recordEdit(m, in: mac, device: macDevice, kind: "Mac",
                                               now: Date(timeIntervalSince1970: 3_000)),
                     "the mac's genuine title edit must stamp")
        try mac.save()

        // The phone's non-word touch left no head at all.
        let phoneHeadsBeforeMeet = (try? phone.fetch(FetchDescriptor<MemoEditHead>())) ?? []
        XCTAssertTrue(phoneHeadsBeforeMeet.filter { $0.deviceID == phoneDevice }.isEmpty,
                     "a stampWords:false touch must never write this device's head")

        try meet(phone, mac)

        XCTAssertNil(EditConflicts.conflict(for: memo(id, phone)!, in: phone, thisDevice: phoneDevice),
                    "no conflict: the phone never stamped its non-word touch")
        XCTAssertNil(EditConflicts.conflict(for: memo(id, mac)!, in: mac, thisDevice: macDevice),
                    "no conflict: the mac never saw a competing head")

        // The mac's real edit is intact on both sides — nothing silently lost.
        XCTAssertEqual(memo(id, phone)!.title, "Tiles for the ensuite floor")
        XCTAssertEqual(memo(id, mac)!.title, "Tiles for the ensuite floor")
    }

    /// The regression this guards against: had the phone's non-word touch stamped anyway
    /// (the pre-Q45 call-site default), the note's nil `baseHash` reads as "changed"
    /// unconditionally (`MemoEditHead.baseHash` doc: "nil = unknown: the first edit after the
    /// upgrade") — so it collides with the mac's real edit as a manufactured conflict.
    func testRegression_stampingTheNonWordTouchWouldFalselyConflict() throws {
        let phone = try store(), mac = try store()
        let id = try seed(phone, mac)

        // Phone: simulate the PRE-FIX call site — a non-word touch that (wrongly) stamps.
        let p = memo(id, phone)!
        p.markEdited(Date(timeIntervalSince1970: 2_000))
        XCTAssertTrue(EditConflicts.recordEdit(p, in: phone, device: phoneDevice, kind: "iPhone",
                                               now: Date(timeIntervalSince1970: 2_000)))
        try phone.save()

        // Mac: a genuine words edit, apart from the phone.
        let m = memo(id, mac)!
        m.title = "Tiles for the ensuite floor"
        m.markEdited(Date(timeIntervalSince1970: 3_000))
        XCTAssertTrue(EditConflicts.recordEdit(m, in: mac, device: macDevice, kind: "Mac",
                                               now: Date(timeIntervalSince1970: 3_000)))
        try mac.save()

        try meet(phone, mac)

        XCTAssertNotNil(EditConflicts.conflict(for: memo(id, phone)!, in: phone, thisDevice: phoneDevice),
                       "demonstrates the bug Q45 exists to prevent: a stamped non-word touch " +
                       "on a never-touched note manufactures a conflict against a real edit")
    }
}
