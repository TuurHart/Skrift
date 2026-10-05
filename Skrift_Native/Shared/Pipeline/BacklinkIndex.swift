import Foundation

/// The whole-library backlink fact, computed ONCE per memo-set version (Q314): for every note,
/// who links to it, plus the set of notes linked at all. Opening a note used to rescan every
/// transcript and copy-edit (and title every note) per open; now every note-open reads this.
/// Built from `Backlinks.Row`s with the same rules as `Backlinks.scan` / `.linkedIDs` (a note
/// linking to itself counts as "linked" but is never its own linker).
struct BacklinkIndex: Sendable {
    /// target -> the ids that link to it, in row order (the phone passes newest first).
    let linkersByTarget: [UUID: [UUID]]
    /// Every id linked from any row (self-links included) — the lifecycle's "backlinked never fades".
    let linkedIDs: Set<UUID>

    static let empty = BacklinkIndex(linkersByTarget: [:], linkedIDs: [])

    /// One pass over `rows`. Pure and `Sendable`, so callers run it off the main actor.
    static func build(rows: [Backlinks.Row]) -> BacklinkIndex {
        var linkers: [UUID: [UUID]] = [:]
        var linked: Set<UUID> = []
        for row in rows {
            for target in Backlinks.targets(in: row.bodies) {
                linked.insert(target)
                if target != row.id { linkers[target, default: []].append(row.id) }
            }
        }
        return BacklinkIndex(linkersByTarget: linkers, linkedIDs: linked)
    }

    func linkers(of target: UUID) -> [UUID] { linkersByTarget[target] ?? [] }
}

/// One `BacklinkIndex` per memo-set version. The rows are cheap value copies taken on the main
/// actor only when the version moved; the scan itself runs detached. Two callers asking for the
/// same version while a build is in flight share it. `buildCount` is what the open-cost tests read.
@MainActor
final class BacklinkIndexCache {
    private(set) var buildCount = 0
    private var cached: (version: Int, index: BacklinkIndex)?
    private var inflight: (version: Int, task: Task<BacklinkIndex, Never>)?

    init() {}

    func index(version: Int, rows: () -> [Backlinks.Row]) async -> BacklinkIndex {
        if let cached, cached.version == version { return cached.index }
        let task: Task<BacklinkIndex, Never>
        if let inflight, inflight.version == version {
            task = inflight.task
        } else {
            buildCount += 1
            let snapshot = rows()
            task = Task.detached(priority: .utility) { BacklinkIndex.build(rows: snapshot) }
            inflight = (version, task)
        }
        let built = await task.value
        // Keep the newest version's result; a slow older build must not overwrite a newer one.
        if let cached, cached.version > version {} else { cached = (version, built) }
        if let inflight, inflight.version == version { self.inflight = nil }
        return built
    }

    func invalidate() { cached = nil; inflight = nil }
}
