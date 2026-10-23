import Foundation

/// Q363 (plan/perf2/f-mac-ui.md M13): the Sanitiser round trip `MacCloudEditSync.flush` runs
/// once per typing pause, pulled out of the main actor. Pure strings in, strings out, so
/// `flush` snapshots its inputs on the main actor, runs this detached, and only the store
/// work (resolve, upsert, save) goes back to main.
enum MacEditRoundTrip {
    struct Result: Equatable, Sendable {
        /// The body as the phone gets it: un-linked to each person's spoken word.
        let raw: String
        /// The words really moved compared with the last pushed polish (a title or summary
        /// edit flushes too, and must not count as a words edit, C98).
        let bodyMoved: Bool
    }

    /// `before` (the stored polish) goes through the SAME process + unlink trip as the live
    /// body, because re-linking is not byte-stable (short-name demotion), so only a real body
    /// change registers (Q42).
    static func compute(body: String, before: String?, people: [Person],
                        neverLink: Set<String>, namePicks: [String: String]) -> Result {
        let raw = Sanitiser.unlinkToSpoken(body, people: people)
        let beforeRoundTripped = before.map {
            Sanitiser.unlinkToSpoken(Sanitiser.process(text: $0, people: people,
                                                       neverLink: neverLink,
                                                       namePicks: namePicks).sanitised, people: people)
        }
        return Result(raw: raw, bodyMoved: beforeRoundTripped != raw)
    }

    /// Q489, THE rule for a body edit made on the Mac: the row's copy-edit carries it. The review
    /// editor writes into `sanitised` (linked); every re-derivation (a phone edit's recompile, a
    /// roster re-link, the open note's refresh) rebuilds from the copy-edit, and the polish
    /// write-back sends the copy-edit. So a real body change also lands there, de-linked: the
    /// same text the cloud gets. The edit write-back adopts it after each typing pause; `settle`
    /// adopts one still only in `sanitised` (the pause itself, or an edit from an older build)
    /// right before any of those paths reads the copy-edit.
    static func adopt(_ trip: Result, into pf: PipelineFile) {
        guard trip.bodyMoved, pf.sanitised != nil else { return }
        pf.enhancedCopyedit = trip.raw
    }

    /// `body` (the linked body) against `working` (the copy-edit → transcript it should derive
    /// from), both linked with `people` and the note's name decisions: a difference is his edit,
    /// adopted. A conversation keeps its turns (its linker is not this round trip's).
    static func settle(_ pf: PipelineFile, body: String?, working: String, linkedWith people: [Person],
                       neverLink: Set<String>, namePicks: [String: String]) {
        guard let body, !working.isEmpty,
              !SpeakerTranscript.isConversation(working, source: pf.noteSource) else { return }
        adopt(compute(body: body, before: working, people: people, neverLink: neverLink, namePicks: namePicks),
              into: pf)
    }

    /// `settle` on the row as it stands now.
    static func settle(_ pf: PipelineFile, linkedWith people: [Person]) {
        settle(pf, body: pf.sanitised,
               working: CompilerInput.workingBody(raw: pf.transcript, copyedit: pf.enhancedCopyedit).text,
               linkedWith: people, neverLink: Set(pf.unlinkedNames), namePicks: pf.namePicks)
    }

    /// `compute` on a background executor: the main actor only awaits the result.
    static func offMain(body: String, before: String?, people: [Person],
                        neverLink: Set<String>, namePicks: [String: String]) async -> Result {
        await Task.detached(priority: .userInitiated) {
            compute(body: body, before: before, people: people,
                    neverLink: neverLink, namePicks: namePicks)
        }.value
    }
}
