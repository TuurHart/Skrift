import Foundation

/// Requests that arrive while a run is already going (Q77 / C49).
///
/// `ProcessingCoordinator` runs one batch at a time. Before this, a Process click during a run
/// was REFUSED ("A run is already going — wait for it to finish") and an import's automatic
/// transcription was dropped silently — so with several memos, only the first right-click
/// Process took and the rest "worked flaky" (Tuur, 2026-09-30). Now a request that can't start
/// yet waits here and the coordinator drains it, in arrival order, the moment the run ends.
///
/// Pure value logic (no engines) so the MLX-free test bundle can pin it.
struct RunQueue {
    enum Job: Equatable {
        /// Full pipeline (transcribe → enhance → …). `retranscribe` = ids forced through a fresh ASR pass.
        case process(ids: [String], retranscribe: Set<String>)
        /// Capture-only: words and nothing else.
        case transcribe(ids: [String])
        /// Q87 "Split speakers": ONE note's fresh transcription + diarization (then the normal
        /// pipeline over the turns). Its own case so a queued split can be cancelled by id.
        case split(id: String)
    }

    private(set) var jobs: [Job] = []

    var isEmpty: Bool { jobs.isEmpty }

    /// Add a job. Duplicates collapse. Process supersedes a waiting transcribe-only of the same
    /// note (Process transcribes too), and a transcribe-only request for a note already waiting
    /// on a Process is dropped for the same reason. A re-transcribe request is never lost: if the
    /// note already waits in a plain Process job, that job is upgraded to force the fresh pass.
    mutating func enqueue(_ job: Job) {
        switch job {
        case .process(let ids, let retranscribe):
            let waiting = processIDs()
            // Upgrade already-waiting process jobs that now need a forced re-transcribe.
            jobs = jobs.map { j in
                guard case .process(let pids, let r) = j else { return j }
                return .process(ids: pids, retranscribe: r.union(retranscribe.intersection(pids)))
            }
            // The process job now covers these ids, so a waiting transcribe-only for them is redundant.
            let taking = Set(ids)
            jobs = jobs.compactMap { j in
                guard case .transcribe(let tids) = j else { return j }
                let left = tids.filter { !taking.contains($0) }
                return left.isEmpty ? nil : .transcribe(ids: left)
            }
            let fresh = ids.filter { !waiting.contains($0) }
            if !fresh.isEmpty {
                jobs.append(.process(ids: fresh, retranscribe: retranscribe.intersection(fresh)))
            }
        case .transcribe(let ids):
            let covered = processIDs().union(transcribeIDs())
            let fresh = ids.filter { !covered.contains($0) }
            if !fresh.isEmpty { jobs.append(.transcribe(ids: fresh)) }
        case .split(let id):
            if !jobs.contains(job) { jobs.append(.split(id: id)) }
        }
    }

    /// Drop a waiting split for `id` (the user pressed Cancel while it was still queued).
    /// Returns whether one was waiting.
    @discardableResult
    mutating func removeSplit(id: String) -> Bool {
        let before = jobs.count
        jobs.removeAll { $0 == .split(id: id) }
        return jobs.count != before
    }

    func isWaitingSplit(id: String) -> Bool { jobs.contains(.split(id: id)) }

    /// The next job to run, oldest first.
    mutating func next() -> Job? {
        jobs.isEmpty ? nil : jobs.removeFirst()
    }

    private func processIDs() -> Set<String> {
        var out = Set<String>()
        for case .process(let ids, _) in jobs { out.formUnion(ids) }
        return out
    }

    private func transcribeIDs() -> Set<String> {
        var out = Set<String>()
        for case .transcribe(let ids) in jobs { out.formUnion(ids) }
        return out
    }
}

/// Who holds the Mac's one run slot, and what waits behind them (Q77, Q208).
///
/// Every kind of run takes the slot through here — a queued job (`request`) or a Redo
/// (`acquire`) — and the holder drains `waiting` with `advance()` before letting go. A request
/// that arrives during a Redo used to sit in `waiting` until some later request happened to
/// drain it, because Redo took the slot without ever draining. Pure value logic so the
/// MLX-free test bundle can pin it; `ProcessingCoordinator` owns the one instance.
struct RunTurn {
    private(set) var waiting = RunQueue()
    private(set) var held = false

    /// Ask to run `job`. True = the slot was free and is now yours: run it, then `advance()`
    /// until nil. False = the job is queued and the current holder will run it.
    mutating func request(_ job: RunQueue.Job) -> Bool {
        if held { waiting.enqueue(job); return false }
        held = true
        return true
    }

    /// Take the slot for a run that is not a queued job (Redo). False = busy, nothing queued.
    mutating func acquire() -> Bool {
        if held { return false }
        held = true
        return true
    }

    /// Holder only, after finishing a run: the next waiting job (oldest first), or nil after
    /// releasing the slot.
    mutating func advance() -> RunQueue.Job? {
        if let next = waiting.next() { return next }
        held = false
        return nil
    }

    /// Drop a waiting split for `id` (Cancel pressed while it was still queued).
    @discardableResult
    mutating func removeSplit(id: String) -> Bool { waiting.removeSplit(id: id) }
}
