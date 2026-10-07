import SwiftUI
import SwiftData
import AppKit

/// Q333: the state behind the Apple Notes triage sheet (mocks/Q71-apple-notes-triage-v3.html,
/// Mac layout from Q67). The rules live in `AppleNotesTriage` (host-less, tested); this owns the
/// database copy, the decoded-body cache, the JSON file every tap is saved to, and the import hook.
@MainActor @Observable
final class AppleNotesTriageModel {

    enum Phase: Equatable {
        case loading
        case denied(String)
        case failed(String)
        case start
        case triage
        /// `end` = after the last batch; false = "So far".
        case report(end: Bool)
    }

    var phase: Phase = .loading
    private(set) var triage: AppleNotesTriage
    private(set) var notes: [AppleNoteSummary] = []
    private(set) var readAt: Date?
    var toast: String?
    /// What the importer reports it could not carry over, per imported note id.
    private(set) var unmapped: [String: NotesBodyDecoder.Media] = [:]
    private var decoded: [String: NotesBodyDecoder.Decoded?] = [:]
    private var reader: NotesStoreReader?
    private let store: AppleNotesTriageStore
    /// Puts one rated note into Skrift; returns the new note's id. nil in snapshots.
    var importer: ((AppleNoteSummary, NotesBodyDecoder.Decoded, Int) throws -> (id: String, unmapped: NotesBodyDecoder.Media))?
    var libraryTags: () -> [String] = { [] }

    init(store: AppleNotesTriageStore = .standard) {
        self.store = store
        self.triage = AppleNotesTriage(state: store.load())
    }

    /// Snapshot fixture: no database, no file.
    init(fixtureNotes: [AppleNoteSummary], decoded: [String: NotesBodyDecoder.Decoded],
         state: TriageState, phase: Phase) {
        self.store = AppleNotesTriageStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("q333-fixture.json"))
        self.triage = AppleNotesTriage(state: state)
        self.notes = fixtureNotes
        self.decoded = decoded.mapValues { Optional($0) }
        self.phase = phase
        self.readAt = Date()
    }

    // MARK: - reading Notes

    /// Copies the Notes database off the main thread and lists it. Called every time the sheet
    /// opens, so a note written in Notes since last time simply appears.
    func load() async {
        phase = .loading
        let result: Result<(NotesStoreReader, [AppleNoteSummary]), Error> = await Task.detached {
            do {
                let reader = try NotesStoreReader()
                return .success((reader, try reader.listNotes()))
            } catch { return .failure(error) }
        }.value
        switch result {
        case .failure(let error):
            if let f = error as? NotesStoreReader.Failure, f.kind == .denied { phase = .denied(f.errorDescription ?? "") }
            else { phase = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription) }
        case .success(let (reader, list)):
            self.reader = reader
            notes = list
            readAt = Date()
            decoded = [:]
            triage.beginSession(notes: list)
            persist()
            phase = .start
        }
    }

    // MARK: - what the screens read

    var counts: AppleNotesTriage.Counts { triage.counts(notes: notes) }
    var batchIDs: [String] { triage.state.batch }
    var cursor: Int { min(triage.state.cursor, max(0, batchIDs.count - 1)) }
    func note(_ id: String) -> AppleNoteSummary? { notes.first { $0.id == id } }
    var current: AppleNoteSummary? { batchIDs.indices.contains(cursor) ? note(batchIDs[cursor]) : nil }
    var position: (number: Int, of: Int) { triage.batchPosition(notes: notes) }
    var openCount: Int { triage.openCount }
    var canAdvance: Bool { triage.canAdvance }
    var isLastBatch: Bool { triage.queue(from: notes).filter { !batchIDs.contains($0.id) }.isEmpty }
    var ratedPending: Int { triage.pendingImports().count }
    func decision(_ id: String) -> TriageDecision? { triage.decision(id) }
    var firstOpenNumber: Int {
        // "note K of T": how many are decided, plus one.
        min(counts.total, counts.decided + 1)
    }
    var dayLog: [(day: Date, decided: Int)] { triage.dayLog() }

    /// Decoded body of a note (cached). nil = locked, missing, or did not parse.
    func body(of note: AppleNoteSummary) -> NotesBodyDecoder.Decoded? {
        if let hit = decoded[note.id] { return hit }
        let value = reader?.content(of: note)
        decoded[note.id] = .some(value)
        return value
    }

    /// Titles of notes in a state, newest first, for the report lists.
    func decided(_ kind: TriageDecision.Kind, imported: Bool? = nil) -> [(id: String, decision: TriageDecision)] {
        let live = Set(notes.map(\.id))
        return triage.state.decisions
            .filter { live.contains($0.key) && triage.isDecided($0.key) && $0.value.kind == kind
                      && (imported == nil || ($0.value.skriftID != nil) == imported!) }
            .map { ($0.key, $0.value) }
            .sorted { ($0.1.created ?? .distantPast) > ($1.1.created ?? .distantPast) }
    }

    // MARK: - taps

    func select(_ index: Int) {
        guard batchIDs.indices.contains(index) else { return }
        triage.state.cursor = index
        persist()
    }

    func rate(_ step: Int) { decide(.rated, rating: step) }
    func skip() { decide(.skipped) }
    func never() { decide(.never) }

    private func decide(_ kind: TriageDecision.Kind, rating: Int? = nil) {
        guard let n = current else { return }
        switch triage.decide(n, kind: kind, rating: rating) {
        case .alreadyInSkrift:
            say("Already in Skrift. Change its rating, or delete it, there.")
        case .cleared: say("Cleared: back to undecided")
        case .changed:
            switch kind {
            case .rated: say("\(ThreeBallScale.name(forStep: rating ?? 0)) · imports when you tap Next 10")
            case .skipped: say("Skipped for now · comes back next session")
            case .never: say("Never import · remembered by its Notes ID")
            }
            if let next = triage.nextOpenIndex(after: cursor) { triage.state.cursor = next }
        }
        persist()
    }

    /// Next 10 (or Finish on the last batch). Tapping it while notes are open jumps to the first one.
    func nextTen() async {
        guard triage.canAdvance else {
            if let i = triage.firstOpenIndex() { select(i) }
            say("Decide the \(triage.openCount) left first. Showing the first one.")
            return
        }
        let last = isLastBatch
        let ids = triage.advance(notes: notes) ?? []
        let landed = await importNow(ids)
        persist()
        if last && triage.state.batch.isEmpty { phase = .report(end: true) }
        say("Batch done: \(landed) imported")
    }

    func importSoFar() async {
        let landed = await importNow(triage.pendingImports())
        persist()
        phase = .report(end: false)
        say(landed > 0 ? "\(landed) imported. Here is what you can delete in Apple Notes." : "Nothing new to import. Here is what you can delete in Apple Notes.")
    }

    func finishLater() {
        persist()
        phase = .start
        say("Saved at note \(firstOpenNumber) of \(counts.total). Pick up here any time.")
    }

    func resume() {
        triage.state.cursor = triage.firstOpenIndex() ?? 0
        persist()
        phase = .triage
    }

    private func importNow(_ ids: [String]) async -> Int {
        guard let importer else { return 0 }
        var landed = 0
        for id in ids {
            guard let n = note(id), let d = triage.state.decisions[id], d.kind == .rated, let rating = d.rating,
                  let body = body(of: n) else { continue }
            do {
                let r = try importer(n, body, rating)
                triage.markImported(id, skriftID: r.id)
                unmapped[id] = r.unmapped
                landed += 1
            } catch { say("Could not import “\(n.title)”: \(error.localizedDescription)") }
        }
        return landed
    }

    private func persist() { store.save(triage.state) }
    private func say(_ t: String) { toast = t }
}
