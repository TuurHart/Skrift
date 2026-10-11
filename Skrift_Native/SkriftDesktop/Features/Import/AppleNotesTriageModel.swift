import SwiftUI
import SwiftData
import AppKit

/// Q333: the state behind the Apple Notes triage sheet (mocks/Q71-apple-notes-triage-v3.html,
/// Mac layout from Q67). The rules live in `AppleNotesTriage` (host-less, tested); this owns the
/// database copy, the decoded-body cache, the JSON file every tap is saved to, and the import hook.
@MainActor @Observable
final class AppleNotesTriageModel: Identifiable {

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
    /// Rated notes whose last import attempt failed (or whose text could not be read), with the reason.
    /// They stay retryable: the next Next 10 / Import so far tries them again, and the report lists them.
    private(set) var importFailures: [String: String] = [:]
    private var decoded: [String: NotesBodyDecoder.Decoded?] = [:]
    private var reader: NotesStoreReader?
    private let store: AppleNotesTriageStore
    /// Puts one rated note into Skrift; returns the new note's id. nil in snapshots.
    var importer: (@MainActor (AppleNoteSummary, NotesBodyDecoder.Decoded, Int) throws -> (id: String, unmapped: NotesBodyDecoder.Media))?
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
    func load(from source: URL = NotesStoreReader.defaultStoreURL) async {
        phase = .loading
        let result: Result<(NotesStoreReader, [AppleNoteSummary]), Error> = await Task.detached {
            do {
                let reader = try NotesStoreReader(copying: source)
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
            await prefetchBodies()
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

    /// Decoded body of a note, from the cache only (decoding is off the main thread: see `prefetchBodies`).
    /// nil = locked, missing, did not parse, or not read yet (`bodyPending`).
    func body(of note: AppleNoteSummary) -> NotesBodyDecoder.Decoded? {
        if let hit = decoded[note.id] { return hit }
        return nil
    }

    /// True while a note's body has not been decoded yet (the preview says "Reading…", not "could not be read").
    func bodyPending(_ id: String) -> Bool { decoded[id] == nil }

    /// Decodes the bodies of the open batch (and any extra ids) on a background task, then fills the cache.
    /// Gunzip + protobuf + SQLite never run on the main thread.
    func prefetchBodies(extra: [String] = []) async {
        guard let reader else { return }
        let want = (batchIDs + extra).filter { decoded[$0] == nil }
        let todo = want.compactMap { note($0) }
        guard !todo.isEmpty else { return }
        let results: [(String, NotesBodyDecoder.Decoded?)] = await Task.detached {
            todo.map { ($0.id, reader.content(of: $0)) }
        }.value
        for (id, value) in results { decoded[id] = .some(value) }
    }

    /// Titles of notes in a state, newest first, for the report lists. A Never-import decision keeps
    /// only its UUID, so its title and date come from the live note.
    func decided(_ kind: TriageDecision.Kind, imported: Bool? = nil,
                 dropped: Bool? = nil) -> [(id: String, decision: TriageDecision)] {
        let live = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        return triage.state.decisions
            .filter { live[$0.key] != nil && triage.isDecided($0.key) && $0.value.kind == kind
                      && (imported == nil || ($0.value.skriftID != nil) == imported!)
                      && (dropped == nil || $0.value.hasDroppedMedia == dropped!) }
            .map { id, d -> (String, TriageDecision) in
                var d = d
                if d.title.isEmpty, let n = live[id] { d.title = n.title; d.created = n.created }
                return (id, d)
            }
            .sorted { ($0.1.created ?? .distantPast) > ($1.1.created ?? .distantPast) }
    }

    /// Imported notes that are safe to delete in Apple Notes: everything of theirs is in Skrift.
    var safeToDelete: [(id: String, decision: TriageDecision)] { decided(.rated, imported: true, dropped: false) }
    /// Imported notes that left media behind (pictures, drawings, ...): keep them in Apple Notes.
    var keepInNotes: [(id: String, decision: TriageDecision)] { decided(.rated, imported: true, dropped: true) }
    /// Rated notes still waiting to get into Skrift (failed or unreadable earlier), live in Notes only.
    var waitingToImport: [(id: String, decision: TriageDecision)] {
        let live = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        return triage.pendingImports().compactMap { id in
            guard let n = live[id], let d = triage.state.decisions[id] else { return nil }
            var d2 = d; d2.title = n.title; d2.created = n.created
            return (id, d2)
        }
    }
    /// Sum of the media the importer left behind, across every imported note (survives a relaunch).
    var droppedTotals: NotesBodyDecoder.Media {
        triage.state.decisions.values.compactMap(\.dropped).reduce(NotesBodyDecoder.Media()) { a, m in
            var r = a
            r.pictures += m.pictures; r.drawings += m.drawings; r.scans += m.scans; r.tables += m.tables
            r.pdfs += m.pdfs; r.audio += m.audio; r.video += m.video; r.other += m.other; return r
        }
    }

    /// The folders the offerable notes sit in. The mock's "one flat list, no folders" is only true with one.
    var folderNames: [String] {
        Array(Set(AppleNotesTriage.offerable(notes).compactMap(\.folder))).sorted()
    }
    var hasFolders: Bool { folderNames.count > 1 }

    // MARK: - taps

    func select(_ index: Int) {
        guard batchIDs.indices.contains(index) else { return }
        triage.state.cursor = index
        persist()
    }

    /// Decodes whatever the note on screen still needs (called as the cursor lands on it).
    func ensureBody(_ id: String) { if decoded[id] == nil { Task { await prefetchBodies(extra: [id]) } } }

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
        persist()   // the batch is closed on disk before the (slow) imports start
        let landed = await importNow(ids)
        persist()
        await prefetchBodies()
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
        Task { await prefetchBodies() }
    }

    private func importNow(_ ids: [String]) async -> Int {
        guard let importer else { return 0 }
        await prefetchBodies(extra: ids)
        var landed = 0
        for id in ids {
            guard let n = note(id), let d = triage.state.decisions[id], d.kind == .rated, let rating = d.rating else { continue }
            guard let body = body(of: n) else {
                importFailures[id] = "The text of this note could not be read."
                continue
            }
            do {
                let r = try importer(n, body, rating)
                triage.markImported(id, skriftID: r.id, dropped: r.unmapped)
                importFailures[id] = nil
                persist()   // after EVERY note: a crash on the next one cannot forget this one
                landed += 1
            } catch {
                importFailures[id] = error.localizedDescription
                say("Could not import “\(n.title)”: \(error.localizedDescription)")
            }
        }
        return landed
    }

    private func persist() { store.save(triage.state) }
    private func say(_ t: String) { toast = t }
}
