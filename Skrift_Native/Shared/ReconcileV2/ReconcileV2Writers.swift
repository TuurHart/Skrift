import Foundation
import SwiftData

extension ReconcileV2 {

    /// Mac → phone: the writes the Mac makes onto the synced store. Every one resolves its memo
    /// through the STORE (C186), and none bumps the memo's edit time (C188: a Mac meta write is
    /// not a content edit, and bumping it would read as a phone edit on the next sweep).
    enum Writers {

        /// The memo a row belongs to. A Mac recording's audio filename carries the recorder's
        /// UUID, not the memo's, so no naming rule is right for every vintage of row: try each
        /// candidate UUID and take the one the store has.
        static func resolve(_ row: PipelineFile, in ctx: ModelContext) -> Memo? {
            for candidate in candidates(for: row) {
                var d = FetchDescriptor<Memo>(predicate: #Predicate { $0.id == candidate })
                d.fetchLimit = 1
                if let memo = (try? ctx.fetch(d))?.first { return memo }
            }
            return nil
        }

        /// The UUIDs a row's memo may have, most likely first: the row id for a Mac recording,
        /// else the filename's. Use `resolve` where a store is at hand.
        nonisolated static func candidates(for row: PipelineFile) -> [UUID] {
            let fromName = uuid(fromFilename: row.filename), fromID = UUID(uuidString: row.id)
            let order = row.isLocalRecording ? [fromID, fromName] : [fromName, fromID]
            var seen = Set<UUID>()
            return order.compactMap { $0 }.filter { seen.insert($0).inserted }
        }

        /// The most likely memo UUID, with no store to ask (`candidates.first`).
        nonisolated static func memoID(for row: PipelineFile) -> UUID? { candidates(for: row).first }

        /// `memo_<uuid>.<ext>` / `capture_<uuid>` → the UUID in the name.
        nonisolated static func uuid(fromFilename name: String) -> UUID? {
            for prefix in ["memo_", "capture_"] where name.hasPrefix(prefix) {
                return UUID(uuidString: String((name as NSString).deletingPathExtension.dropFirst(prefix.count)))
            }
            return nil
        }

        /// How far two devices' clocks may disagree before a stamp counts as newer (D60).
        static let skew: TimeInterval = 5

        enum Upsert: Equatable { case written, refusedNewer, noMemo, nothingToWrite }

        /// The Mac's polish as the memo's `MemoEnhancement`, last-writer-wins by `enhancedAt`.
        ///
        /// R44 / C46: v1 refused when the other device's stamp was later than THIS Mac's clock, so
        /// a phone with a fast clock had every later Mac polish refused forever. v2 compares stamp
        /// to stamp: it refuses only a polish written by another device that this row has not
        /// seen (its stamp beyond the row's watermark by more than the skew). Its own stamp is
        /// never earlier than the one it replaces, so every device orders the two the same way
        /// whatever the clocks say.
        @discardableResult
        static func upsertEnhancement(for row: PipelineFile, into ctx: ModelContext, deviceID: String,
                                      now: Date = Date(), body: String? = nil, passRan: Bool = false) throws -> Upsert {
            guard let memo = resolve(row, in: ctx) else { return .noMemo }
            let copyedit = body ?? (row.enhancedCopyedit ?? "")
            let title = row.enhancedTitle ?? "", summary = row.enhancedSummary ?? ""
            guard passRan || !(copyedit.isEmpty && title.isEmpty && summary.isEmpty) else { return .nothingToWrite }
            let memoID = memo.id
            let existing = try ctx.fetch(FetchDescriptor<MemoEnhancement>(predicate: #Predicate { $0.memoID == memoID })).first
            if let existing, existing.enhancedByDeviceID != deviceID,
               existing.enhancedAt > (row.syncedSourceEditedAt ?? .distantPast).addingTimeInterval(skew) {
                return .refusedNewer
            }
            let e = existing ?? MemoEnhancement(memoID: memoID)
            let stamp = max(now, (existing?.enhancedAt ?? .distantPast).addingTimeInterval(0.001))
            (e.copyedit, e.title, e.summary) = (copyedit, title, summary)
            e.pendingBlock = row.pendingPolishBlock ?? ""   // C152: empty once a pass polished it
            e.enhancedByDeviceID = deviceID
            e.enhancedAt = stamp
            if passRan { e.processedAt = stamp }
            if existing == nil { ctx.insert(e) }
            try ctx.save()
            return .written
        }

        /// The row's tags and (non-nil) rating onto its memo — the passive mirror. A nil rating is
        /// never written here: on a row it means "never rated" as often as "cleared", and clearing
        /// is an event (`setRating(nil, …)`, C47).
        @discardableResult
        static func mirrorMeta(_ row: PipelineFile, in ctx: ModelContext) -> Bool {
            guard let memo = resolve(row, in: ctx) else { return false }
            return pushMeta(row, to: memo)
        }

        /// `mirrorMeta` onto a memo the caller already resolved.
        @discardableResult
        static func pushMeta(_ row: PipelineFile, to memo: Memo) -> Bool {
            var changed = false
            if memo.tags != row.tags { memo.tags = row.tags; changed = true }
            if let s = row.significance, memo.significance != s { memo.significance = s; changed = true }
            return changed
        }

        /// The rating as an event: nil clears it (0 on the memo), never inferred from a nil row.
        /// These event writes touch the MEMO only; the caller has already set the row.
        @discardableResult
        static func setRating(_ value: Double?, for row: PipelineFile, in ctx: ModelContext) -> Bool {
            write(row, ctx, \.significance, value ?? 0)
        }

        @discardableResult
        static func setDestination(_ d: NoteDestination, for row: PipelineFile, in ctx: ModelContext) -> Bool {
            write(row, ctx, \.destination, d)
        }

        /// A title he chose on the Mac; nil or blank clears the chosen title (each device then
        /// falls back to its own first-line rule; the Mac's suggestion on the row is untouched).
        @discardableResult
        static func setTitle(_ title: String?, for row: PipelineFile, in ctx: ModelContext) -> Bool {
            let t = title?.trimmingCharacters(in: .whitespacesAndNewlines)
            return write(row, ctx, \.title, (t?.isEmpty ?? true) ? nil : t)
        }

        private static func write<V: Equatable>(_ row: PipelineFile, _ ctx: ModelContext,
                                                _ key: ReferenceWritableKeyPath<Memo, V>, _ value: V) -> Bool {
            guard let memo = resolve(row, in: ctx), memo[keyPath: key] != value else { return false }
            memo[keyPath: key] = value
            return true
        }

        /// A Mac trash or restore onto the memo; a trash starts the phone's purge clock at the
        /// same stamp (C188: `trashSeenAt`). Permanent delete stays device-local (C190).
        @discardableResult
        static func mirrorTrash(_ row: PipelineFile, in ctx: ModelContext) -> Bool {
            guard let memo = resolve(row, in: ctx), memo.deletedAt != row.deletedAt else { return false }
            memo.deletedAt = row.deletedAt
            if let d = row.deletedAt { memo.trashSeenAt = d }
            return true
        }
    }
}
