import Foundation
import SwiftData
import os

/// Mac→phone metadata write-back — the second half of "widen the narrow Mac→phone channel".
/// The enhancement carrier (`MacCloudWriteBack`) only ever carried body/title/summary, so tags
/// and importance edited on the Mac never reached the phone (and were frozen at first ingest the
/// other way). Both are plain `Memo` fields that already sync, so — exactly like delete-sync —
/// the Mac just writes them onto the synced `Memo`, and the phone reflects them.
///
/// App-only + gated like the reconcile loop (`cloudKitMacSyncEnabled` + a container); a no-op
/// otherwise. Writes each file's CURRENT `tags`/`significance` (set moments earlier by the review
/// UI) onto its memo. No `lastEditedAt` bump — these are synced fields on their own, and NOT
/// bumping it keeps the reconciler's text-reflect echo-quiet. `MemoCloudUpdate` reflects the phone
/// direction with a plain value compare, so a Mac write converges it (no clobber loop).
@MainActor
enum MacCloudMetaSync {
    private static let log = Logger(subsystem: "com.skrift.desktop", category: "cloudkit")

    /// The gate every writer here shares: sync on, a container, and a synced `Memo` behind
    /// this file. `mutate` returns whether it actually changed anything, so an unchanged
    /// memo is never churned (and never saved). Existed four times over before 2026-08-27.
    @discardableResult
    private static func write(_ pf: PipelineFile, _ what: String,
                              _ mutate: (Memo) -> Bool) -> Bool {
        guard SettingsStore.shared.load().cloudKitMacSyncEnabled,
              let container = MemoCloudStore.container else { return false }
        let ctx = container.mainContext
        guard let memo = MacCloudWriteBack.resolve(for: pf, in: ctx), mutate(memo) else { return false }
        EditConflicts.recordEdit(memo, in: ctx)   // C98: no-op unless the words changed
        do { try ctx.save() }
        catch { log.error("\(what, privacy: .public) write failed: \(String(describing: error), privacy: .public)") }
        return true
    }

    /// Mirror each file's PASSIVE fields onto its synced `Memo` — the set is declared once in
    /// `MirroredNoteFields` (a field with no `push` is event-only in this direction, which is
    /// how importance keeps its "nil is ambiguous" rule). Safe for any files: non-synced /
    /// non-memo rows are skipped, and a memo already at the same values isn't churned.
    static func mirror(_ files: [PipelineFile]) {
        guard SettingsStore.shared.load().cloudKitMacSyncEnabled,
              let container = MemoCloudStore.container else { return }
        let ctx = container.mainContext
        var wrote = false
        for pf in files {
            guard let memo = MacCloudWriteBack.resolve(for: pf, in: ctx) else { continue }
            var pushed = false
            for field in MirroredNoteFields.pushable where field.push!(pf, memo) { pushed = true }
            if pushed { wrote = true; EditConflicts.recordEdit(memo, in: ctx) }   // C98: words only
        }
        if wrote {
            do { try ctx.save() }
            catch { log.error("meta-sync write failed: \(String(describing: error), privacy: .public)") }
        }
    }

    /// The user just set — or CLEARED — this note's rating on the Mac. Unlike `mirror`,
    /// this is driven by an actual click on the circles, so a nil is unambiguous: it's
    /// a re-tap clearing the rating, and `Memo.significance` says that with 0.
    ///
    /// Un-rating used to go nowhere at all (`mirror`'s `if let` dropped it), so a
    /// rating could be given but never taken back — Tuur, 2026-07-26: *"when i removed
    /// it it did not go grey again."*
    static func setRating(_ value: Double?, for pf: PipelineFile) {
        write(pf, "rating") { memo in
            let rating = value ?? 0
            guard memo.significance != rating else { return false }
            memo.significance = rating
            return true
        }
    }

    /// The user picked this note's DESTINATION on the Mac. Event-driven like `setRating`
    /// — a destination change has to reach the other devices the moment it is made, not on
    /// the next passive tag edit, because it decides whether a note is allowed to leave for
    /// a repo an AI reads.
    static func setDestination(_ d: NoteDestination, for pf: PipelineFile) {
        write(pf, "destination") { memo in
            guard memo.destination != d else { return false }
            memo.destination = d
            return true
        }
    }

    /// The user CHOSE this note's title on the Mac — "Suggested", "From recording", or
    /// typed their own. Event-driven like `setRating`, and for the same reason: it must
    /// be distinguishable from the passive mirror.
    ///
    /// Why this exists (Tuur, 2026-07-27: *"I think that should just happen over all
    /// devices"*): the Mac only ever wrote its title to `MemoEnhancement.title` — the
    /// SUGGESTION carrier the phone deliberately does not auto-apply — while every
    /// device's list reads `Memo.title`. So picking a title on the Mac changed the Mac's
    /// list and nothing else, and the phone kept showing the transcript's first line.
    /// A generated suggestion still goes only to the enhancement; an explicit CHOICE is
    /// the note's title on every device.
    ///
    /// No `lastEditedAt` bump — `Memo.title` syncs on its own, and not bumping keeps the
    /// reconciler's text-reflect echo-quiet (same reasoning as `mirror`).
    static func setTitle(_ title: String?, for pf: PipelineFile) {
        write(pf, "title") { memo in
            // Empty ⇒ nil: "no title", so every device falls back to its own first-line rule
            // rather than showing a blank heading.
            let clean = title?.trimmingCharacters(in: .whitespacesAndNewlines)
            let next = (clean?.isEmpty ?? true) ? nil : clean
            guard memo.title != next else { return false }
            memo.title = next
            return true
        }
        // A quiet (unrated) sidebar row renders `Memo.title` from the sidebar's own
        // fetched array — announce the change so a title chosen in the pane shows on
        // the row now, not at the next unrelated refresh (the ROUND 9 item-3 family).
        // POSTED UNCONDITIONALLY, as before: the old code posted even when the write was
        // gated out, and a refresh that finds nothing changed is harmless.
        NotificationCenter.default.post(name: .cloudMemosDidChangeFromSync, object: nil)
    }
}
