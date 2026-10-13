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

    /// `compute` on a background executor: the main actor only awaits the result.
    static func offMain(body: String, before: String?, people: [Person],
                        neverLink: Set<String>, namePicks: [String: String]) async -> Result {
        await Task.detached(priority: .userInitiated) {
            compute(body: body, before: before, people: people,
                    neverLink: neverLink, namePicks: namePicks)
        }.value
    }
}
