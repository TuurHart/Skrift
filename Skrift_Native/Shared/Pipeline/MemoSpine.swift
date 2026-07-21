import Foundation

/// The spine (mocks/lifecycle-ia-explorations.html, direction locked 2026-07-20):
/// ONE status per note, computed as a priority chain over the five old axes —
/// first match wins, so no note can ever carry two labels. Not a new stored
/// state: `keptAt` stays the only stored lifecycle bit; everything here is
/// derived. Both apps compute this (the Mac from Memo ⟕ PipelineFile, the phone
/// from Memo + whether polish arrived) and reuse the one-liners verbatim —
/// the copy trio "starts fading / moves to Recently Deleted / gone for good"
/// is signed off and pinned by the twin test tables.
enum MemoSpine {

    // ── stations ──

    enum Station: Equatable {
        // the lifecycle track (unrated, untouched)
        case new(fadesAt: Date)            // < 30d — "starts fading 19 Aug"
        case fading(deletedAt: Date)       // 30–60d, on the shelf
        case deleted(goneAt: Date)         // Recently Deleted, restorable
        // the siding
        case parked(reason: TouchReason)   // touched but never rated — processed never, fades never
        // the active track (rated, or a Mac-local file)
        case toProcess                     // gate passed; queue row waiting (or not reconciled yet)
        case processing                    // transcribe / enhance running
        case stuck                         // queue row in error
        case ready                         // processed, awaiting review
        case exported                      // in Obsidian — kept forever
    }

    /// Why a parked note is safe — the first touch signal that applies, in
    /// `MemoLifecycle.isTouched` order (minus rating, which parks nothing:
    /// a rated note is on the active track).
    enum TouchReason: String, Equatable {
        case edited, titled, tagged, locked, reminder, annotated, kept, linked
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
        var deletedAt: Date?
        var rated: Bool                 // significance > 0
        var touchReason: TouchReason?   // nil = untouched (rating excluded)
        var transcriptDone: Bool        // still transcribing = New, never Fading
        var queue: QueuePhase?          // nil = no pipeline row
        /// Mac-local upload (PipelineFile with no Memo): active track only,
        /// never fades. Transitional — Q5 direction is that Mac captures
        /// author a Memo and sync like any note.
        var macLocalFile: Bool

        init(recordedAt: Date, deletedAt: Date? = nil, rated: Bool = false,
                    touchReason: TouchReason? = nil, transcriptDone: Bool = true,
                    queue: QueuePhase? = nil, macLocalFile: Bool = false) {
            self.recordedAt = recordedAt
            self.deletedAt = deletedAt
            self.rated = rated
            self.touchReason = touchReason
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
                  deletedAt: memo.deletedAt,
                  rated: memo.significance > 0,
                  touchReason: MemoSpine.touchReason(of: memo, backlinked: backlinked),
                  transcriptDone: memo.transcriptStatus == .done,
                  queue: queue)
        }
    }

    /// First non-rating touch signal, in `MemoLifecycle.isTouched` order — the
    /// parked one-liner's "kept — tagged". nil when only rating (or nothing)
    /// touches the note.
    static func touchReason(of memo: Memo, backlinked: Set<UUID>) -> TouchReason? {
        if memo.transcriptUserEdited { return .edited }
        if !(memo.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .titled }
        if !memo.tags.isEmpty { return .tagged }
        if memo.locked { return .locked }
        if memo.remindAt != nil { return .reminder }
        if !(memo.annotationText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .annotated }
        if memo.keptAt != nil { return .kept }
        if backlinked.contains(memo.id) { return .linked }
        return nil
    }

    // ── the chain (first match wins) ──

    static func station(for input: Input, now: Date = Date()) -> Station {
        // 1 · deleted beats everything — restorable, counting down to the purge.
        if let deleted = input.deletedAt {
            return .deleted(goneAt: deleted.addingTimeInterval(TrashPolicy.retention))
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
        // 3 · the siding: touched but never rated (the zombie, finally named).
        if let reason = input.touchReason { return .parked(reason: reason) }
        // 4 · the lifecycle track. Still transcribing = New (never Fading).
        let fadesAt = input.recordedAt.addingTimeInterval(Self.days(MemoLifecycle.fadeAfterDays))
        if input.transcriptDone && now >= fadesAt {
            return .fading(deletedAt: input.recordedAt.addingTimeInterval(Self.days(MemoLifecycle.trashAfterDays)))
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
        case .parked(let reason):
            return "kept — \(reason.rawValue)"
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
        case .parked: return "Parked"
        case .toProcess: return "To process"
        case .processing: return "Processing"
        case .stuck: return "Stuck"
        case .ready: return "Ready"
        case .exported: return "In Obsidian"
        }
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
