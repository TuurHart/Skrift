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
        }
    }

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
