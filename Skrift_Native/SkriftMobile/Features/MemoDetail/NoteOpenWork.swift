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
    private static let candidateCache = CommitOnceCache<Int, [LinkCandidate]>()
    /// How many times the whole-library title pass ran (tests read this).
    static var candidateBuilds: Int { candidateCache.computeCount }

    /// Everything linkable, newest first, self excluded. The title for EVERY note is the point of
    /// the picker, so it is built once per memo-set version and reused (reopening the picker, or
    /// opening it on the next note, costs nothing until something is saved or synced).
    static func linkCandidates(excluding id: UUID, repository: NotesRepository) -> [LinkCandidate] {
        candidateCache.value(for: repository.memoSetVersion) {
            repository.allMemos().map { m in
                (id: m.id,
                 title: m.ladderTitle(),   // C25: never "Untitled", never a raw file name
                 subtitle: MemoDate.label(m.recordedAt))
            }
        }
        .filter { $0.id != id }
    }
}
