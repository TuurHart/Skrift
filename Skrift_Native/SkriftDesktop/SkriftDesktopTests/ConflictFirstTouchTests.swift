import XCTest
import SwiftData

/// Q42 (C98, gate+): a never-stamped (pre-Q29) note's FIRST touch on a device must not count
/// as a words edit when no words actually changed — a first audio trim / annotation must not
/// manufacture a false "2 versions" against a genuine edit made on another device apart.
final class ConflictFirstTouchTests: XCTestCase {

    private let phone = "PHONE-DEVICE", mac = "MAC-DEVICE"

    private func store() throws -> ModelContext {
        let c = try ModelContainer(for: Memo.self, MemoAsset.self, MemoEnhancement.self, MemoEditHead.self,
                                   configurations: ModelConfiguration(isStoredInMemoryOnly: true,
                                                                      cloudKitDatabase: .none))
        return ModelContext(c)
    }

    private func memos(_ ctx: ModelContext) -> [Memo] { (try? ctx.fetch(FetchDescriptor<Memo>())) ?? [] }
    private func memo(_ id: UUID, _ ctx: ModelContext) -> Memo? { memos(ctx).first { $0.id == id } }
    private func heads(_ ctx: ModelContext) -> [MemoEditHead] { (try? ctx.fetch(FetchDescriptor<MemoEditHead>())) ?? [] }

    /// A pre-Q29 note: identical on both devices, `editStampHash` never seeded (as it never was
    /// before this system existed).
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

    // MARK: - C98 / Q42

    /// A's touch is an audio trim (`markEdited`-style: no title/body/tags mutation). B's touch,
    /// apart, is a genuine word edit. A's words-neutral first touch must not manufacture a
    /// conflict against B's real edit.
    func testAudioTrimFirstTouchIsNotAWordsEditAgainstAGenuineEditElsewhere() throws {
        let p = try store(), m = try store()
        let id = try seed(p, m)

        // Phone: an audio trim — no title/body/tags change, but `markEdited` still schedules
        // a stamp (the app calls `recordEdit` unconditionally on every touch).
        XCTAssertFalse(EditConflicts.recordEdit(memo(id, p)!, in: p, device: phone, kind: "iPhone",
                                                now: Date(timeIntervalSince1970: 1_200)),
                       "a words-neutral first touch only seeds the baseline, never bumps")
        XCTAssertTrue(heads(p).isEmpty, "no head from a no-op first touch")

        // Mac: a genuine word edit, made while apart.
        let macMemo = memo(id, m)!
        macMemo.transcript = "The hexagon ones from the shop, warm grey."
        macMemo.editedAt = Date(timeIntervalSince1970: 1_500)
        EditConflicts.recordEdit(macMemo, in: m, device: mac, kind: "Mac", now: Date(timeIntervalSince1970: 1_500))

        try meet(p, m)
        XCTAssertNil(EditConflicts.conflict(for: memo(id, p)!, in: p, thisDevice: phone),
                     "the phone's audio trim never touched words — no conflict against the Mac's real edit")
        XCTAssertNil(EditConflicts.conflict(for: memo(id, m)!, in: m, thisDevice: mac))
        XCTAssertEqual(memo(id, m)?.transcript, "The hexagon ones from the shop, warm grey.",
                      "the Mac's genuine edit is not lost")
    }

    /// The same first-touch seeding applies to the polished body (Q38's carrier).
    func testFirstTouchPolishedSeedDoesNotBump() throws {
        let p = try store()
        let id = try seed(p, p)
        p.insert(MemoEnhancement(memoID: id, copyedit: "The hexagon ones from the shop.", title: "Bathroom tiles",
                                 summary: "Hexagon tiles.", enhancedByDeviceID: mac,
                                 enhancedAt: Date(timeIntervalSince1970: 1_000)))
        try p.save()
        XCTAssertFalse(EditConflicts.recordPolishedEdit(memo(id, p)!, in: p, device: phone),
                       "a never-stamped polish just seeds on first touch, no bump")
        XCTAssertTrue(heads(p).isEmpty)
        XCTAssertEqual(memo(id, p)!.editVector, [:], "no vector slot bumped")
    }

    // MARK: - Mac flush round trip (C98 / Q42)

    func testUnlinkRoundTripDoesNotFalselyCountATitleOnlyEditAsPolished() throws {
        let people = [Person(canonical: "Nick Jansen", aliases: ["Nick"], lastModifiedAt: "2026-01-01T00:00:00Z")]
        let original = "Nick Jansen said hi, and later Nick said bye."
        let linked = Sanitiser.process(text: original, people: people).sanitised
        let roundTripped = Sanitiser.unlinkToSpoken(linked, people: people)
        // The round trip is expected to be faithful for this case (proves the harness matches
        // production's own process→unlink contract); the flush fix compares BOTH sides through
        // this same pipeline so a title-only edit (which never touches the linked body) can
        // never register a spurious diff even where the round trip is lossy.
        XCTAssertEqual(roundTripped, original)
    }
}
