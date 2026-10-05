import Foundation

/// Q314: what opening a note may do with the rest of the library. Before, every page open
/// fetched all memos and all enhancements, scanned every body for links, and built a title for
/// EVERY other note (5 regexes over each whole transcript) to name at most 6 backlinks. Now the
/// library-wide part is the shared `BacklinkIndex` (one build per memo-set version, scan off the
/// main actor) and titles are built only for the notes that link here.
@MainActor
enum NoteOpenWork {
    typealias Backlink = (id: UUID, title: String)

    /// At most `limit` notes that link to `target`, newest first, titled by the C25 ladder.
    /// `titleOf` is the test seam that counts title builds; the default is the real ladder.
    static func backlinks(to target: UUID, in index: BacklinkIndex, repository: NotesRepository,
                          limit: Int = 6,
                          titleOf: (Memo) -> String = { $0.ladderTitle() }) -> [Backlink] {
        var out: [Backlink] = []
        for id in index.linkers(of: target) {
            guard let memo = repository.memo(id: id), memo.deletedAt == nil else { continue }
            out.append((id: id, title: String(titleOf(memo).prefix(60))))
            if out.count == limit { break }
        }
        return out
    }

    /// Everything the page needs from the library when it opens: the lifecycle line's
    /// backlinked set, and (only when the footer shows connections) the "Linked from" rows.
    static func load(for memoID: UUID, wantsBacklinks: Bool, repository: NotesRepository,
                     titleOf: (Memo) -> String = { $0.ladderTitle() })
        async -> (backlinks: [Backlink], linkedIDs: Set<UUID>) {
        let index = await repository.backlinkIndex()
        let rows = wantsBacklinks
            ? backlinks(to: memoID, in: index, repository: repository, titleOf: titleOf) : []
        return (rows, index.linkedIDs)
    }

    // MARK: - The "[[" picker's titles

    typealias LinkCandidate = (id: UUID, title: String, subtitle: String)
    /// What a candidate row is built from: plain values copied from the memo on the main actor.
    typealias CandidateInput = (id: UUID, recordedAt: Date, ladder: LadderSnapshot)
    private static let candidateCache = CommitOnceCache<Int, [LinkCandidate]>()
    private static var candidateInflight: (version: Int, task: Task<[LinkCandidate], Never>)?
    /// How many times the whole-library title pass ran (tests read this).
    static var candidateBuilds: Int { candidateCache.computeCount }

    /// Cheap value copies of every live note, newest first. Main actor only: it reads the models.
    static func candidateInputs(repository: NotesRepository) -> [CandidateInput] {
        repository.allMemos().map { (id: $0.id, recordedAt: $0.recordedAt, ladder: LadderSnapshot($0)) }
    }

    /// The title pass itself: pure, so it runs off the main actor. The same ladder
    /// (`LadderSnapshot.title` = `Memo.ladderTitle`) the old per-memo builder ran.
    nonisolated static func buildCandidates(_ inputs: [CandidateInput]) -> [LinkCandidate] {
        inputs.map { (id: $0.id,
                      title: $0.ladder.title(),   // C25: never "Untitled", never a raw file name
                      subtitle: MemoDate.label($0.recordedAt)) }
    }

    /// Everything linkable, newest first, self excluded. The title for EVERY note is the point of
    /// the picker, so it is built once per memo-set version and reused (reopening the picker, or
    /// opening it on the next note, costs nothing until something is saved or synced). Called
    /// cold, this builds on the main actor; `warmLinkCandidates` builds it off main beforehand.
    static func linkCandidates(excluding id: UUID, repository: NotesRepository) -> [LinkCandidate] {
        candidateCache.value(for: repository.memoSetVersion) {
            buildCandidates(candidateInputs(repository: repository))
        }
        .filter { $0.id != id }
    }

    /// Build the picker's titles for the current memo-set version OFF the main actor (Q320), so
    /// the first `[[` after a save no longer titles every note on main. Two callers for one
    /// version share the build; a version already built costs nothing. If a save lands while it
    /// builds, the result is dropped and the new version is built.
    static func warmLinkCandidates(repository: NotesRepository) async {
        for _ in 0..<3 {
            let version = repository.memoSetVersion
            if candidateCache.peek(for: version) != nil { return }
            let task: Task<[LinkCandidate], Never>
            if let inflight = candidateInflight, inflight.version == version {
                task = inflight.task
            } else {
                let inputs = candidateInputs(repository: repository)
                task = Task.detached(priority: .userInitiated) { buildCandidates(inputs) }
                candidateInflight = (version, task)
            }
            let built = await task.value
            if candidateInflight?.version == version { candidateInflight = nil }
            if repository.memoSetVersion == version {
                _ = candidateCache.value(for: version) { built }
                return
            }
        }
    }
}
