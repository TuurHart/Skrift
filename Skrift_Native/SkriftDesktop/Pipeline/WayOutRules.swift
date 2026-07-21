import Foundation

/// Pure lifecycle-IA logic (mocks/lifecycle-ia-explorations.html #m2/#m3, locked
/// 2026-07-21) shared by the Queue band (`SidebarView` / `UnpipelinedMemoSheet`)
/// and — once step ③/④ land — the "one trash" footer count and the "On its way
/// out" conveyor. Kept dependency-free of both views AND of `App/` (no
/// `MemoCloudStore`, no `ModelContext` mutation — callers fetch/save), so it
/// compiles into the MLX-free `SkriftDesktopTests` bundle exactly like
/// `DesktopTrash` — see `Pipeline/DesktopTrash.swift` for the sibling
/// precedent this follows.
enum WayOutRules {

    // MARK: - ② the Queue band

    /// Cloud memos not yet in the local pipeline: unrated, not deleted, and no
    /// ingested `PipelineFile` shares their id. `MemoCloudIngest` always sets an
    /// ingested row's id to `memo.id.uuidString` — a legacy/local-upload
    /// `PipelineFile.id` that ISN'T a well-formed UUID can never collide with
    /// one, so it's naturally excluded from the "already ingested" set with no
    /// extra filtering needed.
    static func unpipelined(memos: [Memo], files: [PipelineFile]) -> [Memo] {
        let ingested = Set(files.compactMap { UUID(uuidString: $0.id) })
        return memos.filter { $0.deletedAt == nil && $0.significance == 0 && !ingested.contains($0.id) }
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

    /// The spine one-liner for a `Memo` (band rows, the peek sheet, and —
    /// once step ④ lands — the conveyor's fading/deleted rows) — builds the
    /// `MemoSpine.Input` and reads its station in one call, so every caller
    /// stays byte-identical to the signed copy trio. `backlinked` only matters
    /// when the memo might still be on the untouched lifecycle track (band
    /// rows); a memo already known deleted-or-fading short-circuits the chain
    /// before backlink status is ever consulted, so a caller that already
    /// knows that can pass the default empty set.
    static func oneLiner(for memo: Memo, backlinked: Set<UUID> = [], now: Date = Date()) -> String {
        let station = MemoSpine.station(for: .from(memo, backlinked: backlinked), now: now)
        return MemoSpine.oneLiner(for: station, now: now)
    }
}
