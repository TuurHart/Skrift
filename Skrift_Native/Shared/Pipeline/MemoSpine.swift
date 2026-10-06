import Foundation

/// The spine (mocks/lifecycle-triage-peek.html #m5/#m6): ONE status per note, computed
/// as a priority chain, first match wins, so no note carries two labels. Nothing new is
/// stored: `keptAt` is the only stored lifecycle bit, everything here is derived. Both
/// apps compute it from the synced `Memo` alone (`Input.from(memo, backlinked:)`) and
/// reuse the one-liners verbatim; the copy trio "starts fading / moves to Recently
/// Deleted / gone for good" is pinned by the twin test tables.
///
/// A touched-but-unrated note is just a clock-run note with a fresher anchor
/// (`MemoLifecycle.clockStart`). The only notes off the clock are `held` ones: locked or
/// backlinked.
enum MemoSpine {

    // ── stations ──

    enum Station: Equatable {
        // the lifecycle track (unrated, on the clock)
        case new(fadesAt: Date)            // < 30d on the clock — "starts fading 19 Aug"
        case fading(deletedAt: Date)       // 30–60d, on the conveyor
        case deleted(goneAt: Date)         // Recently Deleted, restorable
        // held off the clock (unrated but exempt — explicit or structural)
        case held(reason: HoldReason)
        // the active track (rated)
        case toProcess                     // gate passed — the Mac picks it up on its next run
    }

    /// Why a note sits off the clock — the only exemptions (rating is not one:
    /// a rated note is on the active track).
    enum HoldReason: String, Equatable {
        case locked, linked
    }

    // ── input (app-neutral; built from Memo on both apps) ──

    struct Input: Equatable {
        var recordedAt: Date
        var keptAt: Date? = nil             // the clock bump (nil = clock runs from recordedAt)
        var deletedAt: Date? = nil
        /// v3 purge clock (2026-07-23): first open with the note in the trash.
        /// nil / stale (< deletedAt) = the clock hasn't started — the deleted
        /// countdown reads a full window from `now`, and nothing dies unseen.
        var trashSeenAt: Date? = nil
        var rated: Bool = false             // significance > 0
        var holdReason: HoldReason? = nil   // nil = on the clock
        var transcriptDone: Bool = true     // still transcribing = New, never Fading

        /// The shared builder: everything derivable from a synced `Memo`.
        static func from(_ memo: Memo, backlinked: Set<UUID>) -> Input {
            Input(recordedAt: memo.ageDate,
                  keptAt: memo.keptAt,
                  deletedAt: memo.deletedAt,
                  trashSeenAt: memo.trashSeenAt,
                  rated: NoteConsent.isRated(memo),
                  holdReason: MemoSpine.holdReason(of: memo, backlinked: backlinked),
                  transcriptDone: memo.transcriptStatus == .done)
        }
    }

    /// First hold signal in `MemoLifecycle.neverFades` order (minus rating).
    /// nil = the note is on the clock.
    static func holdReason(of memo: Memo, backlinked: Set<UUID>) -> HoldReason? {
        if memo.locked { return .locked }
        if backlinked.contains(memo.id) { return .linked }
        return nil
    }

    // ── the chain (first match wins) ──

    static func station(for input: Input, now: Date = Date()) -> Station {
        // 1 · deleted beats everything — restorable, counting down to the purge.
        // v3 (2026-07-23): the countdown runs from the trash SIGHTING, not the
        // deletion — unseen rows show a full window from `now`, matching the
        // purge gate (`MemoLifecycle.purgeDue`), so the shown date stays true.
        if input.deletedAt != nil {
            let start = MemoLifecycle.trashClockStart(deletedAt: input.deletedAt,
                                                      seenAt: input.trashSeenAt) ?? now
            return .deleted(goneAt: start.addingTimeInterval(TrashPolicy.retention))
        }
        // 2 · the active track: rated (the gate).
        if input.rated { return .toProcess }
        // 3 · held off the clock: locked / backlinked.
        if let reason = input.holdReason { return .held(reason: reason) }
        // 4 · the clock. Still transcribing = New (never Fading).
        let anchor = max(input.recordedAt, input.keptAt ?? .distantPast)
        let fadesAt = anchor.addingTimeInterval(MemoLifecycle.days(MemoLifecycle.fadeAfterDays))
        if input.transcriptDone && now >= fadesAt {
            return .fading(deletedAt: anchor.addingTimeInterval(MemoLifecycle.days(MemoLifecycle.trashAfterDays)))
        }
        return .new(fadesAt: fadesAt)
    }

    // ── one-liners (the signed copy trio + station lines; every surface reuses these verbatim) ──

    static func oneLiner(for station: Station, now: Date = Date()) -> String {
        switch station {
        case .new(let fadesAt):
            return "starts fading \(Self.day(fadesAt))"
        case .fading(let deletedAt):
            let d = Self.daysUntil(deletedAt, now: now)
            return d == 0 ? "moves to Recently Deleted today"
                          : "moves to Recently Deleted in \(d)d"
        case .deleted(let goneAt):
            let d = Self.daysUntil(goneAt, now: now)
            return d == 0 ? "gone for good soon" : "gone for good in ~\(d)d"
        case .held(let reason):
            switch reason {
            case .locked:   return "locked — won't fade"
            case .linked:   return "linked — won't fade"
            }
        case .toProcess: return "processes on next run"
        }
    }

    /// The peek header's compact clock chip (m6): the one-liner, minus the
    /// "starts fading" verbiage on the quiet leg — a chip reads as state, not
    /// prose. Every other station reuses its one-liner verbatim.
    static func chipText(for station: Station, now: Date = Date()) -> String {
        if case .new(let fadesAt) = station { return "fades \(Self.day(fadesAt))" }
        return oneLiner(for: station, now: now)
    }

    /// The peek's one explanatory sentence (m6) — holds the clock truth AND the
    /// gate truth in prose, replacing the contradicting "Not rated" +
    /// "kept — edited" chip pair. Only for notes OFF the active track; a rated
    /// note's peek is the editor, not this sheet.
    static func peekSentence(for memo: Memo, backlinked: Set<UUID>, now: Date = Date()) -> String {
        let station = station(for: .from(memo, backlinked: backlinked), now: now)
        switch station {
        case .held(let reason):
            let why: String
            switch reason {
            case .locked:   why = "Locked, so it never fades"
            case .linked:   why = "Linked from another note, so it won't fade"
            }
            return "\(why) — but it's not rated, so the Mac won't polish it."
        case .new(let fadesAt):
            if let kept = memo.keptAt, kept > memo.ageDate {
                return "You \(touchVerb(for: memo)) this on \(Self.day(kept)), which restarted its clock — it starts fading \(Self.day(fadesAt)) unless you rate it."
            }
            return "Not rated, so the Mac won't polish it — it starts fading \(Self.day(fadesAt))."
        case .fading(let deletedAt):
            let d = Self.daysUntil(deletedAt, now: now)
            let when = d == 0 ? "today" : "in \(d)d"
            return "Fading — it moves to Recently Deleted \(when) unless you rate it or bring it back."
        case .deleted(let goneAt):
            let d = Self.daysUntil(goneAt, now: now)
            let when = d == 0 ? "soon" : "in ~\(d)d"
            return "In Recently Deleted — gone for good \(when) unless you bring it back."
        default:
            return oneLiner(for: station, now: now)
        }
    }

    /// How close a note's fade must be before a list row mentions it (D136).
    static let fadeWarningDays = 7

    /// The urgency-only amber clock line a LIST ROW carries (⏱ eyeball wave 2, 2026-07-22; D136;
    /// Q107 moved it here from the phone's `MemosListView` so the Mac's quiet rows call the same
    /// rule): shown only when fading starts within `fadeWarningDays`, or the note is already
    /// fading (a search hit). Rated, trashed and locked notes carry none.
    static func rowClockLine(for memo: Memo, backlinked: Set<UUID>, now: Date = Date()) -> String? {
        guard !NoteConsent.isRated(memo), memo.deletedAt == nil, !memo.locked else { return nil }
        let station = station(for: .from(memo, backlinked: backlinked), now: now)
        switch station {
        case .fading:
            return oneLiner(for: station, now: now)
        case .new(let fadesAt):
            let warnAt = fadesAt.addingTimeInterval(-Double(fadeWarningDays) * 86_400)
            return now >= warnAt ? oneLiner(for: station, now: now) : nil
        default:
            return nil
        }
    }

    /// Display verb for the clock-restart sentence — freshest-signal precedence
    /// (the old touch order, kept for display only; all of these write `keptAt`
    /// at their commit sites now).
    private static func touchVerb(for memo: Memo) -> String {
        if memo.transcriptUserEdited { return "edited" }
        if !(memo.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "titled" }
        if !memo.tags.isEmpty { return "tagged" }
        if !(memo.annotationText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "annotated" }
        return "kept"
    }

    // ── helpers ──

    private static func daysUntil(_ date: Date, now: Date) -> Int {
        WayOut.daysLeft(until: date, now: now)
    }
    private static func day(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated))
    }
}
