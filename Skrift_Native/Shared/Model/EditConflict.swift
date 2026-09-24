import Foundation
import SwiftData
import CryptoKit
import Observation

/// `[deviceID: edits made on that device]` — a version vector over a note's WORDS.
typealias EditVector = [String: Int]

enum EditVectors {
    enum Order: Equatable { case equal, before, after, concurrent }

    static func encode(_ v: EditVector) -> Data? {
        v.isEmpty ? nil : try? JSONEncoder().encode(v)
    }
    static func decode(_ d: Data?) -> EditVector {
        guard let d, let v = try? JSONDecoder().decode(EditVector.self, from: d) else { return [:] }
        return v
    }
    /// `a` vs `b`: `.before` = `a` is an ancestor of `b` (b saw every edit a carries).
    static func compare(_ a: EditVector, _ b: EditVector) -> Order {
        var aBigger = false, bBigger = false
        for k in Set(a.keys).union(b.keys) {
            let x = a[k] ?? 0, y = b[k] ?? 0
            if x > y { aBigger = true }
            if y > x { bBigger = true }
        }
        switch (aBigger, bBigger) {
        case (false, false): return .equal
        case (false, true):  return .before
        case (true, false):  return .after
        case (true, true):   return .concurrent
        }
    }
    static func merged(_ vs: [EditVector]) -> EditVector {
        var out: EditVector = [:]
        for v in vs { for (k, n) in v { out[k] = max(out[k] ?? 0, n) } }
        return out
    }
}

/// One version of a note's words, as one device holds them.
struct NoteWords: Equatable {
    var deviceID: String
    var deviceKind: String
    var title: String?
    var body: String?
    var tags: [String]
    var editedAt: Date
    /// The polished body (`MemoEnhancement.copyedit`) this version carries; nil = none (Q38).
    var polished: String? = nil

    /// The body he reads and edits: the polish when there is one, else the raw transcript.
    var shownBody: String? { polished ?? body }
}

/// THE conflict record (C98): one note, two versions of its words that neither device saw
/// the other make. `local` is this device's (or, on a device that edited neither, the
/// newer one); `other` is the version it would lose to a silent overwrite.
struct EditConflict: Equatable {
    var memoID: UUID
    var local: NoteWords
    var other: NoteWords
}

/// Edit-conflict detection + resolution (C98 / C242 / D139, mock `Q4-edit-conflict.html`).
///
/// **How detection works.** Every WORDS edit (title, body, tags) bumps this device's slot
/// in the note's edit vector (`Memo.editVectorData`) and upserts this device's
/// `MemoEditHead` — a per-(note, device) synced row holding the words + the vector they
/// were written at. Two devices that edit while apart each write their OWN head, so both
/// versions survive whatever newest-wins the `Memo` row gets. When the heads meet on any
/// device, two heads whose vectors are CONCURRENT (neither saw the other's edit) and whose
/// words differ = a conflict. A device that saw the other's edit before typing carries a
/// vector that dominates it, so ordinary back-and-forth editing never conflicts.
///
/// **The polished body counts as words (Q38).** On a Mac-polished note the body he edits is
/// `MemoEnhancement.copyedit`, not `Memo.transcript`, and the enhancement row is newest-wins
/// too. A USER edit of it (`recordPolishedEdit`: the phone's polished editor, the Mac's
/// review-screen edit write-back) bumps the vector and writes the head with the polished text
/// in `polishedBody`; every words head carries the polish the device held. The Mac's own
/// polish write (`MacCloudWriteBack.upsert` after a pass) and the one-time body normalisation
/// never call either recorder, so they never count as edits.
///
/// Only words conflict: rating, lock, reminder and destination never touch the vector and
/// stay newest-wins. New notes never conflict: a note has no heads until it is edited, and
/// two devices never create the same note id.
enum EditConflicts {

    /// "iPhone" / "iPad" / "Mac".
    static var thisDeviceKind: String {
        #if os(macOS)
        return "Mac"
        #else
        return ProcessInfo.processInfo.isiOSAppOnMac ? "Mac" : (isPad ? "iPad" : "iPhone")
        #endif
    }
    #if !os(macOS)
    private static var isPad: Bool {
        var sys = utsname(); uname(&sys)
        let machine = withUnsafePointer(to: &sys.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        return machine.hasPrefix("iPad")
    }
    #endif

    // MARK: - Hash

    static func hash(title: String?, body: String?, tags: [String]) -> String {
        let s = [title ?? "\u{0}", body ?? "\u{0}", tags.joined(separator: "\u{1}")].joined(separator: "\u{2}")
        return SHA256.hash(data: Data(s.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }
    static func hash(_ memo: Memo) -> String { hash(title: memo.title, body: memo.transcript, tags: memo.tags) }

    /// Hash of a polished body alone (`Memo.polishStampHash`).
    static func polishHash(_ polished: String?) -> String? {
        polished.map { SHA256.hash(data: Data($0.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined() }
    }

    /// Words hash with the polished body folded in. nil polish = exactly the three-part hash,
    /// so heads written before Q38 keep their hash.
    static func combine(_ words: String?, _ polish: String?) -> String? {
        guard let polish else { return words }
        let s = (words ?? "\u{0}") + "\u{3}" + polish
        return SHA256.hash(data: Data(s.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    static func hash(title: String?, body: String?, tags: [String], polished: String?) -> String {
        combine(hash(title: title, body: body, tags: tags), polishHash(polished))!
    }

    // MARK: - The polished body

    static func canHoldPolish(in ctx: ModelContext) -> Bool {
        ctx.container.schema.entities.contains { $0.name == "MemoEnhancement" }
    }

    /// The note's polished body as this device holds it: the newest enhancement's copy-edit,
    /// nil when there is none (or it is blank).
    static func polishedBody(for memoID: UUID, in ctx: ModelContext) -> String? {
        guard let e = enhancement(for: memoID, in: ctx) else { return nil }
        return e.copyedit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : e.copyedit
    }

    private static func enhancement(for memoID: UUID, in ctx: ModelContext) -> MemoEnhancement? {
        guard canHoldPolish(in: ctx) else { return nil }
        var d = FetchDescriptor<MemoEnhancement>(predicate: #Predicate { $0.memoID == memoID },
                                                 sortBy: [SortDescriptor(\.enhancedAt, order: .reverse)])
        d.fetchLimit = 1
        return (try? ctx.fetch(d))?.first
    }

    // MARK: - Recording a local edit

    /// True when `ctx`'s container can hold heads (a test container built from a partial
    /// schema cannot — inserting there would trap).
    static func canRecord(in ctx: ModelContext) -> Bool {
        ctx.container.schema.entities.contains { $0.name == "MemoEditHead" }
    }

    /// Stamp a WORDS edit this device just made to `memo`: bump this device's vector slot and
    /// upsert its head with the current words. A no-op when the words equal what was last
    /// stamped (a reminder or audio edit calls `markEdited` too — it is not a words edit), and
    /// while the note is in conflict (its heads are frozen until he picks). Returns true when
    /// it stamped.
    @discardableResult
    static func recordEdit(_ memo: Memo, in ctx: ModelContext, device: String = DeviceID.current(),
                           kind: String = EditConflicts.thisDeviceKind, now: Date = Date()) -> Bool {
        guard canRecord(in: ctx) else { return false }
        if memo.editStampHash == hash(memo) { return false }
        return stamp(memo, in: ctx, device: device, kind: kind, now: now)
    }

    /// Stamp a USER edit of the POLISHED body (Q38). Call it only where he typed into the
    /// polished text (the phone's polished editor, the Mac's edit write-back), never after a
    /// polish pass or a migration. A no-op when the polish equals what was last stamped and
    /// while the note is in conflict. Returns true when it stamped.
    @discardableResult
    static func recordPolishedEdit(_ memo: Memo, in ctx: ModelContext, device: String = DeviceID.current(),
                                   kind: String = EditConflicts.thisDeviceKind, now: Date = Date()) -> Bool {
        guard canRecord(in: ctx), canHoldPolish(in: ctx) else { return false }
        let p = polishedBody(for: memo.id, in: ctx)
        if p == nil || memo.polishStampHash == polishHash(p) { return false }
        return stamp(memo, in: ctx, device: device, kind: kind, now: now)
    }

    /// Bump this device's slot and write its head with the note's current words + polish.
    private static func stamp(_ memo: Memo, in ctx: ModelContext, device: String, kind: String,
                              now: Date) -> Bool {
        let heads = self.heads(for: memo.id, in: ctx)
        if detect(memo: memo, heads: heads, thisDevice: device) != nil { return false }
        let polished = polishedBody(for: memo.id, in: ctx)
        var v = memo.editVector
        v[device] = (v[device] ?? 0) + 1
        let base = combine(memo.editStampHash, memo.polishStampHash)
        memo.editVector = v
        memo.editStampHash = hash(memo)
        memo.polishStampHash = polishHash(polished)
        upsertHead(memo: memo, heads: heads, device: device, kind: kind, vector: v, baseHash: base,
                   words: (memo.title, memo.transcript, memo.tags), polished: polished, now: now, in: ctx)
        return true
    }

    private static func upsertHead(memo: Memo, heads: [MemoEditHead], device: String, kind: String,
                                   vector: EditVector, baseHash: String?,
                                   words: (String?, String?, [String]), polished: String?,
                                   now: Date, in ctx: ModelContext) {
        let mine = heads.filter { $0.deviceID == device }
        let head: MemoEditHead
        if let first = mine.first {
            head = first
            for dupe in mine.dropFirst() { ctx.delete(dupe) }
            head.vector = vector
            head.baseHash = baseHash
            head.deviceKind = kind
            head.title = words.0; head.body = words.1; head.tags = words.2
            head.polishedBody = polished
            head.editedAt = now
        } else {
            head = MemoEditHead(memoID: memo.id, deviceID: device, deviceKind: kind, vector: vector,
                                baseHash: baseHash, title: words.0, body: words.1, tags: words.2,
                                editedAt: now, polishedBody: polished)
            ctx.insert(head)
        }
    }

    static func heads(for memoID: UUID, in ctx: ModelContext) -> [MemoEditHead] {
        guard canRecord(in: ctx) else { return [] }
        let d = FetchDescriptor<MemoEditHead>(predicate: #Predicate { $0.memoID == memoID })
        return (try? ctx.fetch(d)) ?? []
    }

    // MARK: - Detection

    /// The conflict on `memo`, or nil. Pure over its inputs.
    static func detect(memo: Memo, heads: [MemoEditHead], thisDevice: String) -> EditConflict? {
        guard memo.deletedAt == nil else { return nil }
        // One head per device (CloudKit may briefly hold duplicates): the most advanced.
        var byDevice: [String: MemoEditHead] = [:]
        for h in heads where h.memoID == memo.id {
            if let cur = byDevice[h.deviceID] {
                let o = EditVectors.compare(cur.vector, h.vector)
                if o == .before || (o != .after && h.editedAt > cur.editedAt) { byDevice[h.deviceID] = h }
            } else { byDevice[h.deviceID] = h }
        }
        // A head whose words equal its base changed no words — it cannot conflict.
        let changed = byDevice.values.filter { $0.baseHash == nil || $0.baseHash != $0.contentHash }
        let sorted = changed.sorted { ($0.deviceID == thisDevice ? 0 : 1, $1.editedAt) < ($1.deviceID == thisDevice ? 0 : 1, $0.editedAt) }
        for (i, a) in sorted.enumerated() {
            for b in sorted.dropFirst(i + 1) {
                guard EditVectors.compare(a.vector, b.vector) == .concurrent,
                      a.contentHash != b.contentHash else { continue }
                // A pair the note's own vector already dominates was settled by a pick.
                let settled = EditVectors.compare(EditVectors.merged([a.vector, b.vector]), memo.editVector)
                if settled == .before { continue }
                return EditConflict(memoID: memo.id, local: words(a), other: words(b))
            }
        }
        return nil
    }

    static func conflict(for memo: Memo, in ctx: ModelContext,
                         thisDevice: String = DeviceID.current()) -> EditConflict? {
        detect(memo: memo, heads: heads(for: memo.id, in: ctx), thisDevice: thisDevice)
    }

    /// Every conflicted note id in the store — ONE fetch of heads, for the list pill and the
    /// Mac's processing/export hold.
    static func conflictedIDs(in ctx: ModelContext, memos: [Memo],
                              thisDevice: String = DeviceID.current()) -> Set<UUID> {
        guard canRecord(in: ctx), let all = try? ctx.fetch(FetchDescriptor<MemoEditHead>()) else { return [] }
        let grouped = Dictionary(grouping: all, by: \.memoID)
        var out: Set<UUID> = []
        for m in memos {
            guard let hs = grouped[m.id], hs.count > 1 else { continue }
            if detect(memo: m, heads: hs, thisDevice: thisDevice) != nil { out.insert(m.id) }
        }
        return out
    }

    private static func words(_ h: MemoEditHead) -> NoteWords {
        NoteWords(deviceID: h.deviceID, deviceKind: h.deviceKind, title: h.title, body: h.body,
                  tags: h.tags, editedAt: h.editedAt, polished: h.polishedBody)
    }

    // MARK: - Resolution (D139)

    enum Choice: Equatable { case keepBoth, keepThis, keepOther }

    /// Settle `conflict` on `memo`. `.keepBoth` keeps this device's words on the note and
    /// makes the other version its own note; `.keepThis`/`.keepOther` put the kept words on
    /// the note and move the other version to Recently Deleted as a "replaced" note (14 days;
    /// Bring back = its own note). Nothing is lost either way. Returns the new note.
    @discardableResult
    static func resolve(_ conflict: EditConflict, choice: Choice, memo: Memo, in ctx: ModelContext,
                        device: String = DeviceID.current(), kind: String = EditConflicts.thisDeviceKind,
                        now: Date = Date()) throws -> Memo {
        let kept = choice == .keepOther ? conflict.other : conflict.local
        let spare = choice == .keepOther ? conflict.local : conflict.other
        let heads = self.heads(for: memo.id, in: ctx)
        // The pick is a new edit that saw BOTH versions: its vector dominates every head, so
        // the conflict clears here and, once synced, on every other device too.
        var v = EditVectors.merged(heads.map(\.vector) + [memo.editVector])
        v[device] = (v[device] ?? 0) + 1
        let base = combine(memo.editStampHash, memo.polishStampHash)
        let original = enhancement(for: memo.id, in: ctx)
        memo.title = kept.title
        memo.transcript = kept.body
        memo.tags = kept.tags
        // The kept polished body goes back on the note's enhancement (Q38), stamped as the
        // newest write so it wins every device's newest-wins merge of that row.
        if let polished = kept.polished, canHoldPolish(in: ctx) {
            let e: MemoEnhancement
            if let original { e = original } else { e = MemoEnhancement(memoID: memo.id); ctx.insert(e) }
            e.copyedit = polished
            e.enhancedByDeviceID = device
            e.enhancedAt = now
        }
        let keptPolish = kept.polished ?? polishedBody(for: memo.id, in: ctx)
        memo.editVector = v
        memo.editStampHash = hash(memo)
        memo.polishStampHash = polishHash(keptPolish)
        upsertHead(memo: memo, heads: heads, device: device, kind: kind, vector: v, baseHash: base,
                   words: (kept.title, kept.body, kept.tags), polished: keptPolish, now: now, in: ctx)
        memo.editedAt = now
        memo.keptAt = now

        let copy = makeCopy(of: memo, words: spare, now: now)
        if choice != .keepBoth {
            copy.deletedAt = now
            copy.trashSeenAt = now      // he is looking at it: the 14-day clock starts now
            copy.replacedAt = now
        }
        ctx.insert(copy)
        // The other version's polished body travels with its copy (Q38): its own enhancement,
        // marked processed so no device re-polishes over the text he wrote.
        if let polished = spare.polished, canHoldPolish(in: ctx) {
            ctx.insert(MemoEnhancement(memoID: copy.id, copyedit: polished,
                                       title: original?.title ?? "", summary: original?.summary ?? "",
                                       enhancedByDeviceID: device, enhancedAt: now,
                                       processedAt: original?.processedAt ?? now))
        }
        try ctx.save()
        return copy
    }

    /// The other version as its own note: same day, rating and destination, the version's
    /// words, "(Mac copy)" on the title. Text only — the recording and photos stay with the
    /// original note (a copy that shared the audio file would delete it on purge).
    static func makeCopy(of memo: Memo, words: NoteWords, now: Date) -> Memo {
        let base = (words.title?.isEmpty == false ? words.title : memo.title) ?? "Note"
        let label = words.deviceKind.isEmpty ? "other" : words.deviceKind
        let marker = try? JSONSerialization.data(withJSONObject: ["mediaSource": "typed"],
                                                 options: [.sortedKeys])
        let copy = Memo(recordedAt: memo.recordedAt,
                        tags: words.tags,
                        title: "\(base) (\(label) copy)",
                        transcript: words.body,
                        transcriptStatus: .done,
                        transcriptUserEdited: true,
                        significance: memo.significance,
                        createdAt: now,
                        editedAt: now,
                        metadataData: marker)
        copy.destinationRaw = memo.destinationRaw
        copy.keptAt = now
        return copy
    }
}

#if DEBUG
extension EditConflicts {
    /// DEBUG-only, screenshot/UI-test seam (Q39): manufacture ONE conflict on the first
    /// eligible memo by writing two concurrent heads directly — one for THIS device, one
    /// for a synthetic other device — bypassing the real two-devices-apart flow. Never
    /// compiled into a Release binary; never touches a real store (callers gate it behind
    /// `-inMemoryStore`).
    static func debugForceConflict(in ctx: ModelContext, now: Date = Date()) {
        guard canRecord(in: ctx) else { return }
        // Sort matches MemosListView's own query (`recordedAt` reverse) so the conflicted
        // note IS list row 0 — the same one `-selectFirstMemo` opens on iPad.
        var d = FetchDescriptor<Memo>(predicate: #Predicate { $0.deletedAt == nil })
        d.sortBy = [SortDescriptor(\.recordedAt, order: .reverse)]
        let memos = (try? ctx.fetch(d)) ?? []
        guard let memo = memos.first else { return }
        let mine = DeviceID.current()
        let mineKind = thisDeviceKind
        let otherKind = mineKind == "Mac" ? "iPhone" : "Mac"
        let base = memo.transcript ?? ""
        let headA = MemoEditHead(memoID: memo.id, deviceID: mine, deviceKind: mineKind,
                                 vector: [mine: 1], baseHash: nil, title: memo.title,
                                 body: base + " Adding the hexagon ones from the shop.",
                                 tags: memo.tags, editedAt: now)
        let headB = MemoEditHead(memoID: memo.id, deviceID: "Q39-OTHER-DEVICE", deviceKind: otherKind,
                                 vector: ["Q39-OTHER-DEVICE": 1], baseHash: nil, title: memo.title,
                                 body: base + " Actually let's go with the plain white tiles instead.",
                                 tags: memo.tags, editedAt: now.addingTimeInterval(-1_620))
        ctx.insert(headA)
        ctx.insert(headB)
        try? ctx.save()
    }
}
#endif

/// Which notes have two versions right now — the list pill and the note gate read it, so a
/// row never fetches heads itself. Refreshed by each app when heads change (the phone's
/// `@Query` on `MemoEditHead`, the Mac's reconcile sweep) and after a pick.
@MainActor @Observable
final class EditConflictWatch {
    static let shared = EditConflictWatch()
    private(set) var ids: Set<UUID> = []
    func set(_ new: Set<UUID>) { if new != ids { ids = new } }
    func refresh(in ctx: ModelContext, thisDevice: String = DeviceID.current()) {
        let live = (try? ctx.fetch(FetchDescriptor<Memo>(predicate: #Predicate { $0.deletedAt == nil }))) ?? []
        set(EditConflicts.conflictedIDs(in: ctx, memos: live, thisDevice: thisDevice))
    }
}

extension Memo {
    /// The note's edit vector (`editVectorData`). See `EditConflicts`.
    var editVector: EditVector {
        get { EditVectors.decode(editVectorData) }
        set { editVectorData = EditVectors.encode(newValue) }
    }
}
