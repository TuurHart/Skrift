import Foundation

/// Pure lifecycle-IA logic (mocks/lifecycle-ia-explorations.html #m2/#m3, locked
/// 2026-07-21) shared by the Queue band (`SidebarView` / `UnpipelinedMemoSheet`),
/// the "one trash" footer count (`SidebarView`), and the "On its way out"
/// conveyor (`WayOutColumn`). Kept dependency-free of both views AND of
/// `App/` (no `MemoCloudStore`, no `ModelContext` mutation —
/// callers fetch/save), so it compiles into the MLX-free `SkriftDesktopTests`
/// bundle exactly like `DesktopTrash` — see `Pipeline/DesktopTrash.swift` for
/// the sibling precedent this follows. `MacCloudWriteBack` (Pipeline/Ingest,
/// LANE_AUTHOR's — read-only use of its pure `memoID(for:)` helper) is also
/// visible to both targets, so the mac-only test below can call it directly.
enum WayOutRules {

    // MARK: - ② the Queue band

    /// Cloud memos not yet in the local pipeline: unrated, not deleted, and either
    /// no `PipelineFile` shares their id at all, OR the one that does is a quiet
    /// local take (`isQuietLocalTake` — the unrated-take doctrine, 2026-07-28): a
    /// Mac recording nobody has rated yet still renders here, exactly like an
    /// unrated phone memo, even though its transcript-bearing row already exists.
    /// `MemoCloudIngest` always sets an ingested row's id to `memo.id.uuidString`
    /// — a legacy/local-upload `PipelineFile.id` that ISN'T a well-formed UUID can
    /// never collide with one, so it's naturally excluded from the lookup map
    /// with no extra filtering needed (same as the old `ingested` Set).
    static func unpipelined(memos: [Memo], files: [PipelineFile], now: Date = Date()) -> [Memo] {
        var byMemoID: [UUID: PipelineFile] = [:]
        for f in files {
            guard let id = UUID(uuidString: f.id) else { continue }
            byMemoID[id] = f
        }
        // One-home law (the spine): a FADING note's counting surface is the
        // Review conveyor — the band listing it too made it double-homed
        // ("are those the fading ones?", Tuur's 2026-07-21 eyeball round).
        // The list = quiet clock-run notes: what the Mac is quietly ignoring.
        // LOCKED notes are excluded too (m6, 2026-07-22): lock is the explicit
        // keep-don't-polish verb — a resolved note doesn't nag.
        let backlinked = MemoLifecycle.backlinkedIDs(in: memos)
        return memos.filter { memo in
            guard memo.deletedAt == nil && !NoteConsent.isRated(memo) && !memo.locked
                    && !MemoLifecycle.isFading(memo, backlinked: backlinked, now: now) else { return false }
            guard let pf = byMemoID[memo.id] else { return true }   // no pipeline row at all
            return isQuietLocalTake(pf)   // a row exists, but it's a quiet local take
        }
    }

    /// STRANDED: rated, live memos with no `PipelineFile` at all — the state that has no
    /// home in the list. The queue rows are files; the quiet rows above are the UNRATED
    /// memos; so a memo that is rated but rowless renders in neither, and reads as a note
    /// that was deleted (Tuur, 2026-08-19 — three copies sat safe in the store the whole
    /// time). Every known cause is fixed at the ingest end; this is the standing floor, so
    /// the next cause shows up as a visible row instead of a vanished note.
    ///
    /// Trashed memos are excluded (the bin is their home) and locked ones are NOT: lock
    /// means keep-don't-polish, which is a reason to skip processing, never to hide a note.
    static func stranded(memos: [Memo], files: [PipelineFile]) -> [Memo] {
        var rowIDs = Set<UUID>()
        for f in files { if let id = UUID(uuidString: f.id) { rowIDs.insert(id) } }
        return memos.filter { $0.deletedAt == nil && NoteConsent.isRated($0) && !rowIDs.contains($0.id) }
    }

    /// The quiet line for a stranded row. The spine would answer `.toProcess` →
    /// "processes on next run", which for the two 2026-06-11 audiobook quotes sitting in
    /// the Dev store with no audio asset has been untrue for two months. A rated note with
    /// no row is waiting on its media, so it says that instead (better no info than bad
    /// info): the note is readable, and nothing pretends it is queued.
    /// Kept SHORT deliberately: the quiet line renders after a date (and a duration, when
    /// there is one), and the first draft — "waiting for its audio to sync — not queued" —
    /// clipped to "waiting for its audio to sync…", losing the half that carried the point.
    static func strandedLine(for memo: Memo) -> String {
        memo.audioFilename.isEmpty ? "not queued yet" : "waiting for its audio"
    }

    // MARK: - Unrated Mac takes (the unrated-take doctrine, 2026-07-28)

    /// A Mac-recorded take nobody has rated yet. "The RATING is what pipelines a
    /// memo" (`SidebarView.openInPane`) — a capture must not look or act pipelined
    /// just because it happens to have words. Doesn't care about errors; see
    /// `isQuietLocalTake` for the row-visibility carve-out.
    static func isUnratedLocalRecording(_ pf: PipelineFile) -> Bool {
        pf.isLocalRecording && !NoteConsent.isRated(pf)
    }

    /// An unrated local take that ALSO leaves the queue-row channel entirely — its
    /// authored `Memo` (same UUID as `pf.id`) renders as a quiet row instead
    /// (`SidebarView.entries`/`queueRowFiles`). An errored take is the carve-out:
    /// it KEEPS its queue row + Error chip even while unrated (a failed capture
    /// that quietly faded would bury a real failure) — only the Process gate
    /// (`needsProcessing` below) still refuses it.
    static func isQuietLocalTake(_ pf: PipelineFile) -> Bool {
        isUnratedLocalRecording(pf) && pf.transcribeStatus != .error && pf.error == nil
    }

    /// Whether a `PipelineFile` still needs the auto-run pipeline — the pure
    /// predicate `ProcessingCoordinator.needsProcessing` forwards to. Pulled out
    /// to here (rather than living only on the coordinator) because that class
    /// isn't a source of the MLX-free `SkriftDesktopTests` target — same
    /// dependency-free reasoning as the rest of this file's header comment.
    /// Not soft-deleted, not already enhanced, and — the unrated-take doctrine —
    /// not an unrated Mac recording. A RATED local recording, and any ordinary
    /// import (never `isLocalRecording`), are unaffected.
    static func needsProcessing(_ pf: PipelineFile) -> Bool {
        pf.deletedAt == nil && pf.enhanceStatus != .done && !isUnratedLocalRecording(pf)
    }

    /// The band row / peek-sheet title: phone-set title → transcript's first
    /// line (`[[img_NNN]]` markers stripped, 80-char cap) → "Voice note" — the
    /// desktop's existing `displayTitle` idiom (`Features/Review/ReviewHelpers.swift`
    /// `PipelineFile.displayTitle`, and the mobile `Memo.displayTitle` in
    /// `SkriftMobile/Models/MemoDisplay.swift`), re-derived here because the
    /// desktop's `Memo` has no such accessor of its own.
    static func displayTitle(_ memo: Memo) -> String {
        if let t = memo.title?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { return t }
        let cleaned = (memo.transcript ?? "")
            .replacingOccurrences(of: #"\[\[img_\d+\]\]"#, with: "", options: .regularExpression)
        let line = cleaned.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first(where: { !$0.isEmpty })
        if let line, !line.isEmpty { return NoteTitle.clip(line) }
        return SourceKind.of(memo).emptyTitleFallback   // typed → "Note", else "Voice note"
    }

    /// The spine one-liner for a `Memo` (band rows, the peek sheet, and the
    /// conveyor's fading/deleted rows) — builds the `MemoSpine.Input` and reads
    /// its station in one call, so every caller stays byte-identical to the
    /// signed copy trio. `backlinked` only matters when the memo might still be
    /// on the untouched lifecycle track (band rows); a memo already known
    /// deleted-or-fading short-circuits the chain before backlink status is
    /// ever consulted, so a caller that already knows that can pass the
    /// default empty set.
    static func oneLiner(for memo: Memo, backlinked: Set<UUID> = [], now: Date = Date()) -> String {
        let station = MemoSpine.station(for: .from(memo, backlinked: backlinked), now: now)
        return MemoSpine.oneLiner(for: station, now: now)
    }

    // MARK: - ③ one Recently Deleted (memo trash + the Mac-local tail)

    /// A trashed `PipelineFile` with no backing `Memo` — a Mac-local upload from
    /// before captures synced (Q5's transitional tail, dissolved once step ⑤
    /// ships `MacMemoAuthor`). NOTE: `PipelineFile.id` defaults to a random UUID
    /// string for a LOCAL upload too (`PipelineFile.init`), not just a CloudKit-
    /// ingested one — so `MacCloudWriteBack.memoID(for:)` (designed for callers
    /// who already know a file is memo-sourced) can derive a UUID-shaped
    /// *candidate* from either kind of row. The only real test is whether that
    /// candidate is a memo that's ACTUALLY in `memoIDs` (the live cloud fetch).
    static func isMacOnly(_ pf: PipelineFile, memoIDs: Set<UUID>) -> Bool {
        guard let candidate = MacCloudWriteBack.memoID(for: pf) else { return true }
        return !memoIDs.contains(candidate)
    }

    /// The transitional tail: trashed, Mac-local-only files.
    static func macOnlyTrashed(_ files: [PipelineFile], memoIDs: Set<UUID>) -> [PipelineFile] {
        files.filter { $0.deletedAt != nil && isMacOnly($0, memoIDs: memoIDs) }
    }

    /// Free-text match for a quiet (unrated) row — title + transcript, the
    /// memo-side mirror of `AppModel.matchesSearch`. Empty query matches all.
    static func matchesSearch(_ memo: Memo, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return true }
        if displayTitle(memo).lowercased().contains(q) { return true }
        if memo.transcript?.lowercased().contains(q) == true { return true }
        return false
    }

    // MARK: - ④ the conveyor

    /// The one rescue verb for both a fading and a deleted note (Q4): sets
    /// `keptAt` ALWAYS (an explicit rescue is a touch — the note must not
    /// re-fade the next second) and clears `deletedAt` when it was set. Caller
    /// saves the cloud context.
    static func bringBack(_ memo: Memo, now: Date = Date()) {
        memo.keptAt = now
        memo.deletedAt = nil
        memo.trashSeenAt = nil   // purge-clock hygiene (v3); the validity guard ignores stale stamps anyway
    }

    /// Fading rows, soonest-to-move-to-Recently-Deleted first (imminence
    /// ordering — mirrors `FadingShelfColumn`'s prior comparator, unchanged).
    static func fadingOrdered(_ memos: [Memo]) -> [Memo] {
        memos.sorted { MemoLifecycle.fadesAt($0) < MemoLifecycle.fadesAt($1) }
    }

    /// Deleted rows, soonest-to-purge-for-good first (imminence ordering —
    /// oldest `deletedAt` first). Deliberately NOT `MacTrashColumn`'s old
    /// newest-deleted-first comparator: the mock's worked example ("deleted
    /// 7 Jul · ~1d" listed above "deleted 14 Jul · ~8d") shows the conveyor
    /// orders by what happens next, not by what you did most recently.
    static func deletedOrdered(_ memos: [Memo]) -> [Memo] {
        memos.sorted { ($0.deletedAt ?? .distantPast) < ($1.deletedAt ?? .distantPast) }
    }
}
