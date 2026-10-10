#if DEBUG
import Foundation
import SwiftData

/// Q336: the fake test library in the NORMAL (CloudKit-synced) Dev store, on phone, iPad and Mac.
///
/// `fill` runs the same deterministic generator `-perfLibrary` uses (`PerfLibrarySeeder`) but into
/// the store the app really syncs, so the 2,000 fake notes (and the 150 fake people, into the names
/// DB) reach every Dev device through the Dev CloudKit environment. Every note carries
/// `MemoMetadata.testLibrary == true`; ids are deterministic, and notes already in the store are
/// skipped, so filling twice adds nothing. `remove` soft-deletes exactly the marked notes, then
/// purges them (rows, asset blobs, enhancements, edit heads) and tombstones the fake people, so
/// the removal syncs the same way. Real notes are never marked and never touched.
///
/// DEBUG only: this whole file, the Settings rows that call it, and the marker's writer vanish in
/// Release (`TestLibrarySyncSeedTests` checks the file and the Settings call sites).
enum TestLibrary {

    struct FillSummary: Equatable {
        var memosAdded = 0
        var assetsAdded = 0
        var peopleAdded = 0
    }

    struct RemoveSummary: Equatable {
        var memos = 0
        var assets = 0
        var people = 0
    }

    /// True for a note the "Fill with test notes" action made.
    static func isMarked(_ memo: Memo) -> Bool { memo.metadata?.testLibrary == true }

    /// The fake roster's canonical keys (`[[First Last]]`). The names file has no marker field
    /// (it stays byte-compatible across both apps), so the roster is recognised by name.
    static func fakeRosterKeys(now: Date = Date()) -> Set<String> {
        Set(PerfLibrarySeeder.makePeople(count: PerfLibrarySeeder.Plan().people, now: now)
            .map { NamesMerge.matchKey($0.canonical) })
    }

    // MARK: Fill

    /// Seed the library into `context` (call off the main thread for the full 2,000: a few
    /// seconds of CPU) and the roster into `names`. `recordingsDirectory` is the phone's media
    /// folder (nil on the Mac, which reads the asset blobs). Every recording-shaped note carries a
    /// tiny AAC blob by default, because the Mac builds no row for a voice memo without audio.
    @discardableResult
    static func fill(into context: ModelContext, names: NamesStore, recordingsDirectory: URL?,
                     tinyAudioForEveryRecording: Bool = true, now: Date = Date(),
                     plan basePlan: PerfLibrarySeeder.Plan = PerfLibrarySeeder.Plan(),
                     progress: ((String, Int, Int) -> Void)? = nil) throws -> FillSummary {
        var plan = basePlan
        plan.markAsTestLibrary = true
        plan.tinyAudioForEveryRecording = tinyAudioForEveryRecording
        plan.skipIDs = Set(((try? context.fetch(FetchDescriptor<Memo>())) ?? []).map(\.id))
        let seeded = try PerfLibrarySeeder.seed(into: context, recordingsDirectory: recordingsDirectory,
                                                now: now, plan: plan, progress: progress)
        // `seeded` counts only what was inserted: the seeder skips the ids already in the store.
        var out = FillSummary(memosAdded: seeded.memos, assetsAdded: seeded.assets, peopleAdded: 0)
        out.peopleAdded = addFakePeople(to: names, count: plan.people, now: now)
        return out
    }

    /// Roster in, existing people untouched: returns how many were new (or came back from a tombstone).
    @discardableResult
    static func addFakePeople(to names: NamesStore, count: Int = PerfLibrarySeeder.Plan().people,
                              now: Date = Date()) -> Int {
        let live = names.livePeople()
        let have = Set(live.map { NamesMerge.matchKey($0.canonical) })
        let fresh = PerfLibrarySeeder.makePeople(count: count, now: now)
            .filter { !have.contains(NamesMerge.matchKey($0.canonical)) }
        guard !fresh.isEmpty else { return 0 }
        names.writeWithSmartBumps(live + fresh)
        return fresh.count
    }

    // MARK: Remove

    /// Delete exactly the marked notes: soft-delete and save, then purge. `deleteLocalFiles` is
    /// the phone's chance to drop a note's audio / photos from its media folder before the row
    /// goes. `afterSoftDelete` fires between the two steps (tests).
    @discardableResult
    static func remove(from context: ModelContext, names: NamesStore,
                       deleteLocalFiles: ((Memo) -> Void)? = nil,
                       afterSoftDelete: (() -> Void)? = nil) throws -> RemoveSummary {
        let marked = ((try? context.fetch(FetchDescriptor<Memo>())) ?? []).filter(isMarked)
        var out = RemoveSummary()

        // 1. soft-delete (the path every device already understands), saved on its own.
        let stamp = Date()
        for m in marked where m.deletedAt == nil { WayOut.softDelete(m, now: stamp) }
        try context.save()
        afterSoftDelete?()

        // 2. purge: the asset blobs, the Mac's polish, the edit heads, then the row.
        let ids = marked.map(\.id)
        var offset = 0
        while offset < ids.count {
            let chunk = Array(ids[offset..<min(ids.count, offset + 200)])
            for a in (try? context.fetch(FetchDescriptor<MemoAsset>(predicate: #Predicate { chunk.contains($0.memoID) }))) ?? [] {
                context.delete(a); out.assets += 1
            }
            for e in (try? context.fetch(FetchDescriptor<MemoEnhancement>(predicate: #Predicate { chunk.contains($0.memoID) }))) ?? [] {
                context.delete(e)
            }
            for h in (try? context.fetch(FetchDescriptor<MemoEditHead>(predicate: #Predicate { chunk.contains($0.memoID) }))) ?? [] {
                context.delete(h)
            }
            offset += chunk.count
        }
        for (i, m) in marked.enumerated() {
            deleteLocalFiles?(m)
            context.delete(m)
            out.memos += 1
            if (i + 1) % 200 == 0 { try context.save() }
        }
        try context.save()

        out.people = removeFakePeople(from: names)
        return out
    }

    /// Tombstone the fake roster. A person with a voiceprint is a real enrolment under a coinciding
    /// name and stays. Returns how many were removed.
    @discardableResult
    static func removeFakePeople(from names: NamesStore, now: Date = Date()) -> Int {
        let fake = fakeRosterKeys(now: now)
        let live = names.livePeople()
        let keep = live.filter { p in
            !fake.contains(NamesMerge.matchKey(p.canonical)) || !(p.voiceEmbeddings ?? []).isEmpty
        }
        let removed = live.count - keep.count
        guard removed > 0 else { return 0 }
        names.writeWithSmartBumps(keep)
        return removed
    }
}
#endif
