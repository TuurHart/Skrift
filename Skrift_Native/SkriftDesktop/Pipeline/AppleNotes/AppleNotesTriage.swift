import Foundation

/// Q333 (mocks/Q71-apple-notes-triage-v3.html): what Tuur decided about each Apple Note, kept
/// across days. Everything is keyed on the note's `ZIDENTIFIER` (`AppleNoteSummary.id`), never
/// its title, so a renamed note is still recognised and a "Never import" note is never offered
/// again.
struct TriageDecision: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case rated, skipped, never }
    var kind: Kind
    /// 1...3 (Passing / Useful / Important) for `.rated`, else nil.
    var rating: Int?
    /// Title + creation date as they were when decided, so the report can list a note
    /// (Never import, Safe to delete) without re-reading Notes.
    var title: String
    var created: Date?
    var decidedAt: Date
    /// `TriageState.session` at decision time. A skip only hides the note for that session.
    var session: Int
    /// Set once the note is in Skrift (the `PipelineFile` id).
    var skriftID: String?
    var importedAt: Date?
}

struct TriageState: Codable, Equatable, Sendable {
    var version = 1
    var decisions: [String: TriageDecision] = [:]
    /// The open batch (note ids, ≤ 10, in the order shown). Persisted so "continue where you left off" lands on it.
    var batch: [String] = []
    var batchesDone = 0
    var session = 0
    /// Index of the note showing in the open batch.
    var cursor = 0
}

/// Reads and writes `TriageState` as one JSON file next to the other app data
/// (`AppPaths.appSupportDirectory`, so Skrift Dev and Skrift keep separate lists).
struct AppleNotesTriageStore: Sendable {
    var url: URL

    static var standard: AppleNotesTriageStore {
        AppleNotesTriageStore(url: AppPaths.appSupportDirectory.appendingPathComponent("apple-notes-triage.json"))
    }

    func load() -> TriageState {
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder.triage.decode(TriageState.self, from: data) else { return TriageState() }
        return state
    }

    func save(_ state: TriageState) {
        guard let data = try? JSONEncoder.triage.encode(state) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}

private extension JSONEncoder {
    static let triage: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.sortedKeys]; return e
    }()
}
private extension JSONDecoder {
    static let triage: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()
}

/// The rules, with no UI and no database: batches of ten, the Next-10 lock, skip vs never,
/// resume. Every method that changes `state` is `mutating`; the owner saves after each tap.
struct AppleNotesTriage {
    static let batchSize = 10

    var state: TriageState
    init(state: TriageState = TriageState()) { self.state = state }

    enum DecideOutcome: Equatable { case changed, cleared, alreadyInSkrift }

    // MARK: - what is on offer

    /// Newest first, date-unknown last (Q141), id as the final tiebreak so the order never shuffles.
    static func ordered(_ notes: [AppleNoteSummary]) -> [AppleNoteSummary] {
        notes.sorted {
            switch ($0.created, $1.created) {
            case let (a?, b?) where a != b: return a > b
            case (_?, nil): return true
            case (nil, _?): return false
            default: return $0.id < $1.id
            }
        }
    }

    /// Locked notes stay behind: no body to read, never offered.
    static func offerable(_ notes: [AppleNoteSummary]) -> [AppleNoteSummary] { ordered(notes.filter { !$0.isLocked }) }

    /// A decision stands unless it is a skip from an earlier session (those come back).
    func isDecided(_ id: String) -> Bool {
        guard let d = state.decisions[id] else { return false }
        return !(d.kind == .skipped && d.session < state.session)
    }

    func decision(_ id: String) -> TriageDecision? { isDecided(id) ? state.decisions[id] : nil }

    /// Notes still to decide, in order: nothing that is decided, Never import, or in Skrift.
    func queue(from notes: [AppleNoteSummary]) -> [AppleNoteSummary] {
        Self.offerable(notes).filter { !isDecided($0.id) }
    }

    // MARK: - sessions and batches

    /// One call per opening of the flow: skips from earlier sessions become offerable again and the
    /// open batch is trimmed of notes that no longer exist in Notes.
    mutating func beginSession(notes: [AppleNoteSummary]) {
        state.session += 1
        let live = Set(Self.offerable(notes).map(\.id))
        state.batch = state.batch.filter { live.contains($0) }
        state.cursor = firstOpenIndex() ?? min(state.cursor, max(0, state.batch.count - 1))
        fillBatchIfEmpty(from: notes)
    }

    /// Takes the next ten undecided notes when there is no open batch.
    mutating func fillBatchIfEmpty(from notes: [AppleNoteSummary]) {
        guard state.batch.isEmpty else { return }
        state.batch = Array(queue(from: notes).prefix(Self.batchSize).map(\.id))
        state.cursor = 0
    }

    func firstOpenIndex() -> Int? { state.batch.firstIndex { !isDecided($0) } }

    var openCount: Int { state.batch.filter { !isDecided($0) }.count }

    /// Next 10 is locked until every note of the batch is decided (a skip counts, Q71 choice 3).
    var canAdvance: Bool { !state.batch.isEmpty && openCount == 0 }

    /// Rated notes of the open batch not yet in Skrift: what "Next 10" and "Import what I've
    /// decided so far" hand to the importer.
    func pendingImports() -> [String] {
        state.batch.filter { id in
            guard let d = state.decisions[id], d.kind == .rated, d.skriftID == nil else { return false }
            return true
        }
    }

    /// Closes the batch and opens the next ten. Refuses (nil) while any note is undecided.
    /// Returns the ids to import from the batch just closed.
    @discardableResult
    mutating func advance(notes: [AppleNoteSummary]) -> [String]? {
        guard canAdvance else { return nil }
        let toImport = pendingImports()
        state.batch = []
        state.batchesDone += 1
        fillBatchIfEmpty(from: notes)
        return toImport
    }

    /// Batch counter words for the header: "batch 19 of 42".
    func batchPosition(notes: [AppleNoteSummary]) -> (number: Int, of: Int) {
        let remaining = queue(from: notes).count + state.batch.filter { isDecided($0) }.count
        let total = state.batchesDone + Int((Double(max(remaining, state.batch.count)) / Double(Self.batchSize)).rounded(.up))
        return (state.batchesDone + 1, max(total, state.batchesDone + 1))
    }

    // MARK: - deciding

    /// Records, changes or clears (same tap again) one decision.
    @discardableResult
    mutating func decide(_ note: AppleNoteSummary, kind: TriageDecision.Kind, rating: Int? = nil,
                         now: Date = Date()) -> DecideOutcome {
        let existing = state.decisions[note.id].flatMap { isDecided(note.id) ? $0 : nil }
        if let existing, existing.skriftID != nil, kind != .rated { return .alreadyInSkrift }
        if let existing, existing.kind == kind, existing.rating == rating {
            if existing.skriftID != nil { return .alreadyInSkrift }
            state.decisions[note.id] = nil
            return .cleared
        }
        var d = TriageDecision(kind: kind, rating: kind == .rated ? rating : nil, title: note.title,
                               created: note.created, decidedAt: now, session: state.session)
        if let existing, existing.kind == .rated, kind == .rated {   // re-rating keeps the import link
            d.skriftID = existing.skriftID; d.importedAt = existing.importedAt
        }
        state.decisions[note.id] = d
        return .changed
    }

    mutating func markImported(_ id: String, skriftID: String, now: Date = Date()) {
        state.decisions[id]?.skriftID = skriftID
        state.decisions[id]?.importedAt = now
    }

    /// The next undecided note after `index` in the open batch (wrapping), or nil when none is left.
    func nextOpenIndex(after index: Int) -> Int? {
        let n = state.batch.count
        guard n > 0 else { return nil }
        for step in 1...n {
            let j = (index + step) % n
            if !isDecided(state.batch[j]) { return j }
        }
        return nil
    }

    // MARK: - numbers for the start screen and the report

    struct Counts: Equatable {
        var decided = 0, rated = 0, never = 0, skipped = 0, inSkrift = 0
        var byRating: [Int: Int] = [:]
        var total = 0
        var lockedLeftBehind = 0
        var left: Int { max(0, total - decided) }
    }

    func counts(notes: [AppleNoteSummary]) -> Counts {
        var c = Counts()
        c.total = notes.filter { !$0.isLocked }.count
        c.lockedLeftBehind = notes.filter(\.isLocked).count
        let live = Set(notes.filter { !$0.isLocked }.map(\.id))
        for (id, d) in state.decisions where live.contains(id) && isDecided(id) {
            c.decided += 1
            switch d.kind {
            case .rated: c.rated += 1; if let r = d.rating { c.byRating[r, default: 0] += 1 }
            case .never: c.never += 1
            case .skipped: c.skipped += 1
            }
            if d.skriftID != nil { c.inSkrift += 1 }
        }
        return c
    }

    /// "Thu 24 Sep: 80 decided" lines, derived from the decisions themselves.
    func dayLog(calendar: Calendar = .current) -> [(day: Date, decided: Int)] {
        var perDay: [Date: Int] = [:]
        for d in state.decisions.values { perDay[calendar.startOfDay(for: d.decidedAt), default: 0] += 1 }
        return perDay.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }
}

/// Apple Notes tags become Skrift tags (Q71 / C93): case folds into a tag already in the library
/// (`TagRules.resolveSpelling`), a multi-word tag keeps its spaces, a second spelling of the same
/// tag in one note is dropped.
enum AppleNotesTags {
    static func map(_ notesTags: [String], library: [String]) -> [String] {
        let accepted = notesTags.flatMap { TagRules.split($0).accepted }
        return TagRules.fold(accepted, existing: [], library: library)
    }
}
