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

    /// Cloud memos not yet in the local pipeline: unrated, not deleted, and no
    /// ingested `PipelineFile` shares their id. `MemoCloudIngest` always sets an
    /// ingested row's id to `memo.id.uuidString` — a legacy/local-upload
    /// `PipelineFile.id` that ISN'T a well-formed UUID can never collide with
    /// one, so it's naturally excluded from the "already ingested" set with no
    /// extra filtering needed.
    static func unpipelined(memos: [Memo], files: [PipelineFile], now: Date = Date()) -> [Memo] {
        let ingested = Set(files.compactMap { UUID(uuidString: $0.id) })
        // One-home law (the spine): a FADING note's counting surface is the
        // Review conveyor — the band listing it too made it double-homed
        // ("are those the fading ones?", Tuur's 2026-07-21 eyeball round).
        // The band = New + Parked only: what the Mac is quietly ignoring.
        let backlinked = MemoLifecycle.backlinkedIDs(in: memos)
        return memos.filter {
            $0.deletedAt == nil && $0.significance == 0 && !ingested.contains($0.id)
                && !MemoLifecycle.isFading($0, backlinked: backlinked, now: now)
        }
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
        if let line, !line.isEmpty { return String(line.prefix(80)) }
        return "Voice note"
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
