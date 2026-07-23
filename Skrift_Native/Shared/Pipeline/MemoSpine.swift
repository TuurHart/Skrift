import Foundation

/// The spine (v2 "one clock" — mocks/lifecycle-triage-peek.html #m5/#m6, signed
/// 2026-07-22; v1 direction locked 2026-07-20): ONE status per note, computed as
/// a priority chain — first match wins, so no note can ever carry two labels.
/// Not a new stored state: `keptAt` stays the only stored lifecycle bit;
/// everything here is derived. Both apps compute this (the Mac from
/// Memo ⟕ PipelineFile, the phone from Memo + whether polish arrived) and reuse
/// the one-liners verbatim — the copy trio "starts fading / moves to Recently
/// Deleted / gone for good" is signed and pinned by the twin test tables.
///
/// v2 changes: the Parked siding is GONE — a touched-but-unrated note is just a
/// clock-run note with a fresher anchor (`MemoLifecycle.clockStart`). The only
/// notes off the clock are `held` ones: locked, pending reminder, or backlinked.
enum MemoSpine {

    // ── stations ──

    enum Station: Equatable {
        // the lifecycle track (unrated, on the clock)
        case new(fadesAt: Date)            // < 30d on the clock — "starts fading 19 Aug"
        case fading(deletedAt: Date)       // 30–60d, on the conveyor
        case deleted(goneAt: Date)         // Recently Deleted, restorable
        // held off the clock (unrated but exempt — explicit or structural)
        case held(reason: HoldReason)
        // the active track (rated, or a Mac-local file)
        case toProcess                     // gate passed; queue row waiting (or not reconciled yet)
        case processing                    // transcribe / enhance running
        case stuck                         // queue row in error
        case ready                         // processed, awaiting review
        case exported                      // in Obsidian — kept forever
    }

    /// Why a note sits off the clock — the only exemptions (rating is not one:
    /// a rated note is on the active track).
    enum HoldReason: String, Equatable {
        case locked, reminder, linked
    }

    /// The Mac queue's phase for a note that has a pipeline row. The phone has
    /// no queue; it passes `.none` (no row) or `.ready`/`.exported` when the
    /// Mac's polish/export state synced back.
    enum QueuePhase: Equatable {
        case queued, transcribing, enhancing, error, ready, exported
    }

    // ── input (app-neutral; built from Memo on both apps, or raw for Mac-local files) ──

    struct Input: Equatable {
        var recordedAt: Date
        var keptAt: Date?               // the clock bump (nil = clock runs from recordedAt)
        var deletedAt: Date?
        /// v3 purge clock (2026-07-23): first open with the note in the trash.
        /// nil / stale (< deletedAt) = the clock hasn't started — the deleted
        /// countdown reads a full window from `now`, and nothing dies unseen.
        var trashSeenAt: Date?
        var rated: Bool                 // significance > 0
        var holdReason: HoldReason?     // nil = on the clock
        var transcriptDone: Bool        // still transcribing = New, never Fading
        var queue: QueuePhase?          // nil = no pipeline row
        /// Mac-local upload (PipelineFile with no Memo): active track only,
        /// never fades. Transitional — Q5 direction is that Mac captures
        /// author a Memo and sync like any note.
        var macLocalFile: Bool

        init(recordedAt: Date, keptAt: Date? = nil, deletedAt: Date? = nil,
             trashSeenAt: Date? = nil,
             rated: Bool = false, holdReason: HoldReason? = nil,
             transcriptDone: Bool = true, queue: QueuePhase? = nil,
             macLocalFile: Bool = false) {
            self.recordedAt = recordedAt
            self.keptAt = keptAt
            self.deletedAt = deletedAt
            self.trashSeenAt = trashSeenAt
            self.rated = rated
            self.holdReason = holdReason
            self.transcriptDone = transcriptDone
            self.queue = queue
            self.macLocalFile = macLocalFile
        }

        /// The shared builder: everything derivable from a synced `Memo`.
        /// `queue` stays whatever the caller knows (Mac: its pipeline row;
        /// phone: enhancement-arrived → `.ready`, exported → `.exported`).
        static func from(_ memo: Memo, backlinked: Set<UUID>,
                         queue: QueuePhase? = nil) -> Input {
            Input(recordedAt: memo.recordedAt,
                  keptAt: memo.keptAt,
                  deletedAt: memo.deletedAt,
                  trashSeenAt: memo.trashSeenAt,
                  rated: memo.significance > 0,
                  holdReason: MemoSpine.holdReason(of: memo, backlinked: backlinked),
                  transcriptDone: memo.transcriptStatus == .done,
                  queue: queue)
        }
    }

    /// First hold signal in `MemoLifecycle.neverFades` order (minus rating).
    /// nil = the note is on the clock.
    static func holdReason(of memo: Memo, backlinked: Set<UUID>) -> HoldReason? {
        if memo.locked { return .locked }
        if memo.remindAt != nil { return .reminder }
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
        // 2 · the active track: rated (the gate) or a Mac-local upload.
        if input.rated || input.macLocalFile {
            switch input.queue {
            case .queued, nil: return .toProcess   // not reconciled yet still counts
            case .transcribing, .enhancing: return .processing
            case .error: return .stuck
            case .ready: return .ready
            case .exported: return .exported
            }
        }
        // 3 · held off the clock: locked / reminder / backlinked.
        if let reason = input.holdReason { return .held(reason: reason) }
        // 4 · the clock. Still transcribing = New (never Fading).
        let anchor = max(input.recordedAt, input.keptAt ?? .distantPast)
        let fadesAt = anchor.addingTimeInterval(Self.days(MemoLifecycle.fadeAfterDays))
        if input.transcriptDone && now >= fadesAt {
            return .fading(deletedAt: anchor.addingTimeInterval(Self.days(MemoLifecycle.trashAfterDays)))
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
            case .reminder: return "reminder set — won't fade"
            case .linked:   return "linked — won't fade"
            }
        case .toProcess: return "processes on next run"
        case .processing: return "processing"
        case .stuck: return "stuck — needs a look"
        case .ready: return "waiting for your review"
        case .exported: return "arrived — kept forever"
        }
    }

    /// Station display names (chips, shelf headers). "Recently Deleted" and
    /// "In Obsidian" match the surfaces that count them.
    static func name(for station: Station) -> String {
        switch station {
        case .new: return "New"
        case .fading: return "Fading"
        case .deleted: return "Recently Deleted"
        case .held: return "Held"
        case .toProcess: return "To process"
        case .processing: return "Processing"
        case .stuck: return "Stuck"
        case .ready: return "Ready"
        case .exported: return "In Obsidian"
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
            case .reminder: why = "Has a reminder, so it won't fade"
            case .linked:   why = "Linked from another note, so it won't fade"
            }
            return "\(why) — but it's not rated, so the Mac won't polish it."
        case .new(let fadesAt):
            if let kept = memo.keptAt, kept > memo.recordedAt {
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

    private static func days(_ n: Int) -> TimeInterval { TimeInterval(n) * 86_400 }
    private static func daysUntil(_ date: Date, now: Date) -> Int {
        max(0, Int(ceil(date.timeIntervalSince(now) / 86_400)))
    }
    private static func day(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated))
    }
}
