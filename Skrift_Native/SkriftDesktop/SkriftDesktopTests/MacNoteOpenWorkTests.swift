import XCTest
import SwiftData

/// Q362 (D186 / D191; `plan/perf2/f-mac-ui.md` M5 M7 M8 M12 M15, `h-shared-data.md` N1): opening and
/// playing a note on the Mac does no whole-library work. The Mac half of the phone's
/// `NoteOpenWorkTests` (Q314). 2,000 in-memory notes stand in for the measured library.
///
/// The counters are the contract: `MacNoteOpenWork.corpusFetches` counts every UNSCOPED fetch of
/// notes, memos or polishes (a fetch with a predicate for a handful of ids is not one). They must
/// never be loosened to pass.
@MainActor
final class MacNoteOpenWorkTests: XCTestCase {

    private func link(_ id: UUID) -> String { MemoLinkSyntax.link(id: id, title: "Old thought") }

    private func pipelineContext() throws -> ModelContext {
        ModelContext(try ModelContainer(for: PipelineFile.self,
                                        configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    private func cloudContainer() throws -> ModelContainer {
        try ModelContainer(for: Memo.self, MemoAsset.self, MemoEnhancement.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
    }

    /// `count` notes; the first `linkers` link to `target` (one via `sanitised`, the rest via the transcript).
    private func library(count: Int = 2000, target: UUID, linkers: Int = 2)
        -> (ctx: ModelContext, target: PipelineFile, linkerIDs: [String]) {
        let ctx = (try? pipelineContext())!
        let now = Date()
        let t = PipelineFile(id: target.uuidString, filename: "t.m4a", uploadedAt: now.addingTimeInterval(-10_000_000))
        t.transcript = "The note being opened"
        t.tags = ["alpha"]
        ctx.insert(t)
        var linkerIDs: [String] = []
        for i in 0..<count {
            let f = PipelineFile(id: UUID().uuidString, filename: "m\(i).m4a",
                                 uploadedAt: now.addingTimeInterval(-Double(i) * 60))
            let body = "Line \(i) of a long untitled body. " + String(repeating: "More words here. ", count: 30)
            if i < linkers {
                if i == 0 { f.transcript = body; f.sanitised = "see \(link(target)) " + body }
                else { f.transcript = "see \(link(target)) " + body }
                linkerIDs.append(f.id)
            } else {
                f.transcript = body
            }
            f.tags = i % 2 == 0 ? ["alpha", "beta"] : ["beta"]
            ctx.insert(f)
        }
        try? ctx.save()
        return (ctx, t, linkerIDs)
    }

    // MARK: - M7: Connections reuses ONE backlink index

    func testOpeningTwoNotesScansTheLibraryOnceAndTitlesOnlyTheLinkers() async {
        let target = UUID()
        let (ctx, t, linkerIDs) = library(target: target)
        let work = MacNoteOpenWork(version: MacLibraryVersion())
        var titles = 0
        let titleOf: (PipelineFile) -> String = { titles += 1; return $0.filename }

        let first = await work.backlinks(to: t, context: ctx, titleOf: titleOf)
        XCTAssertEqual(Set(first.map(\.fileID)), Set(linkerIDs))
        XCTAssertEqual(titles, linkerIDs.count, "one title per note that links here, not 2,001")
        XCTAssertEqual(work.corpusFetches, 1, "the first open builds the index with ONE pass over the notes")

        let other = linkerIDs[0]
        var d = FetchDescriptor<PipelineFile>(predicate: #Predicate { $0.id == other })
        d.fetchLimit = 1
        let second = await work.backlinks(to: try! ctx.fetch(d).first!, context: ctx, titleOf: titleOf)
        XCTAssertTrue(second.isEmpty)
        XCTAssertEqual(work.corpusFetches, 1, "the second open does no full-corpus fetch")
        XCTAssertEqual(work.fileIndexBuilds, 1)
    }

    func testTheIndexRebuildsAfterTheLibraryChangesAndNotBefore() async {
        let target = UUID()
        let version = MacLibraryVersion()
        let (ctx, t, linkerIDs) = library(count: 50, target: target)
        let work = MacNoteOpenWork(version: version)
        _ = await work.backlinks(to: t, context: ctx, titleOf: { $0.filename })
        _ = await work.backlinks(to: t, context: ctx, titleOf: { $0.filename })
        XCTAssertEqual(work.fileIndexBuilds, 1)

        let late = PipelineFile(id: UUID().uuidString, filename: "late.m4a", uploadedAt: Date())
        late.transcript = "newest \(link(target))"
        ctx.insert(late)
        version.bump()
        let after = await work.backlinks(to: t, context: ctx, titleOf: { $0.filename })
        XCTAssertEqual(work.fileIndexBuilds, 2, "rebuilt after the library changed")
        XCTAssertEqual(after.first?.fileID, late.id, "newest first")
        XCTAssertEqual(after.count, linkerIDs.count + 1)
    }

    func testTheIndexAnswersWhatTheOldScanAnswered() async {
        let target = UUID()
        let (ctx, t, _) = library(count: 30, target: target)
        let all = try! ctx.fetch(FetchDescriptor<PipelineFile>())
        // The scan `ConnectionsModel.backlinkScan` ran per open before Q362: every live other note, three bodies.
        let rows = all.filter { $0.id != t.id && $0.deletedAt == nil }
            .map { Backlinks.Row(id: UUID(uuidString: $0.id)!, bodies: [$0.transcript, $0.sanitised, $0.enhancedCopyedit]) }
        let old = Set(Backlinks.scan(for: target, in: rows).map(\.uuidString))
        let work = MacNoteOpenWork(version: MacLibraryVersion())
        let hits = await work.backlinks(to: t, context: ctx, titleOf: { $0.filename })
        XCTAssertEqual(Set(hits.map(\.fileID)), old)
    }

    // MARK: - M8: the fading line reads cached backlinks

    func testTheFadingLineOfAnUnratedNoteScansTheMemosOncePerVersion() async throws {
        let container = try cloudContainer()
        let seed = ModelContext(container)
        let now = Date()
        var ids: [UUID] = []
        for i in 0..<2000 {
            let m = Memo(audioFilename: "m\(i).m4a", recordedAt: now.addingTimeInterval(-Double(100 + i) * 86_400),
                         transcript: "Memo \(i) " + String(repeating: "words ", count: 40), transcriptStatus: .done)
            seed.insert(m); ids.append(m.id)
        }
        try seed.save()
        let work = MacNoteOpenWork(version: MacLibraryVersion())

        let a = await work.fadingLine(forMemoID: ids[0], container: container, now: now)
        XCTAssertNotNil(a, "an old unrated note shows its way-out line")
        let afterFirst = work.corpusFetches
        XCTAssertEqual(afterFirst, 2, "first unrated open: one memo pass + one polish pass, to build the linked set")
        _ = await work.fadingLine(forMemoID: ids[1], container: container, now: now)
        _ = await work.fadingLine(forMemoID: ids[2], container: container, now: now)
        XCTAssertEqual(work.corpusFetches, afterFirst, "later unrated opens fetch no corpus")
        XCTAssertEqual(work.memoIndexBuilds, 1)
    }

    func testABacklinkedNoteHasNoFadingLine() async throws {
        let container = try cloudContainer()
        let seed = ModelContext(container)
        let now = Date()
        let old = Memo(audioFilename: "o.m4a", recordedAt: now.addingTimeInterval(-200 * 86_400),
                       transcript: "old", transcriptStatus: .done)
        let linker = Memo(audioFilename: "l.m4a", recordedAt: now.addingTimeInterval(-60),
                          transcript: "see \(link(old.id))", transcriptStatus: .done)
        seed.insert(old); seed.insert(linker); try seed.save()
        let work = MacNoteOpenWork(version: MacLibraryVersion())
        let line = await work.fadingLine(forMemoID: old.id, container: container, now: now)
        XCTAssertNil(line)
    }

    // MARK: - M15: `[[` candidates and tag counts come from a cache keyed on the library version

    func testLinkCandidatesAndTagCountsAreBuiltOncePerVersion() {
        let target = UUID()
        let version = MacLibraryVersion()
        let (ctx, t, _) = library(count: 200, target: target)
        let work = MacNoteOpenWork(version: version)

        let a = work.linkCandidates(excluding: t.id, context: ctx, titleOf: { $0.filename })
        let b = work.linkCandidates(excluding: UUID().uuidString, context: ctx, titleOf: { $0.filename })
        XCTAssertEqual(work.corpusFetches, 1, "reopening the picker reuses the candidates")
        XCTAssertEqual(a.count, 200)
        XCTAssertEqual(b.count, 201)
        XCTAssertTrue(zip(a, a.dropFirst()).allSatisfy { $0.sortDate >= $1.sortDate }, "newest first")

        let c1 = work.tagCounts(ctx), c2 = work.tagCounts(ctx)
        XCTAssertEqual(c1, c2)
        XCTAssertEqual(c1["beta"], 200)
        XCTAssertEqual(c1["alpha"], 101)
        XCTAssertEqual(work.corpusFetches, 2, "tag counts: one more pass, once")

        version.bump()
        _ = work.linkCandidates(excluding: t.id, context: ctx, titleOf: { $0.filename })
        _ = work.tagCounts(ctx)
        XCTAssertEqual(work.corpusFetches, 4, "both rebuilt after the library changed")
    }

    func testTheLibraryVersionMovesWhenAContextSaves() throws {
        let version = MacLibraryVersion(observingSaves: true)
        let before = version.value
        let ctx = try pipelineContext()
        ctx.insert(PipelineFile(id: UUID().uuidString, filename: "x.m4a"))
        try ctx.save()
        let moved = expectation(description: "version bumped")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { moved.fulfill() }
        wait(for: [moved], timeout: 2)
        XCTAssertGreaterThan(version.value, before)
    }

    // MARK: - M5: playback ticks read a word map built once per note version

    private func timings(_ n: Int) -> Data {
        let t = (0..<n).map { WordTiming(word: "w\($0)", start: Double($0) * 0.4, end: Double($0) * 0.4 + 0.3) }
        return try! JSONEncoder().encode(t)
    }

    func testTenPlaybackTicksBuildTheWordMapOnce() {
        let cache = MacKaraokeCache()
        let body = (0..<500).map { "w\($0)" }.joined(separator: " ")
        let json = timings(500)
        var actives: [Int?] = []
        for tick in 0..<10 {
            let p = cache.playback(fileID: "n1", body: body, timingsJSON: json,
                                   loadedDuration: 200, fallbackDuration: { 0 })
            actives.append(p.track.activeIndex(at: Double(tick) * 0.05 + 40))
        }
        XCTAssertEqual(cache.builds, 1, "ten 20 Hz ticks: one split + one decode + one align")
        XCTAssertEqual(cache.timingDecodes, 1)
        XCTAssertEqual(actives.last!, 100, "word 100 starts at 40.0 s")

        _ = cache.playback(fileID: "n1", body: body + " extra", timingsJSON: json,
                           loadedDuration: 200, fallbackDuration: { 0 })
        XCTAssertEqual(cache.builds, 2, "an edited body is a new note version")
        _ = cache.playback(fileID: "n2", body: body, timingsJSON: json,
                           loadedDuration: 200, fallbackDuration: { 0 })
        XCTAssertEqual(cache.builds, 3, "another note is another version")
    }

    func testTheFallbackDurationIsOnlyReadWhenNothingIsLoaded() {
        let cache = MacKaraokeCache()
        var reads = 0
        for _ in 0..<5 {
            _ = cache.playback(fileID: "n", body: "a b c", timingsJSON: timings(3),
                               loadedDuration: 12, fallbackDuration: { reads += 1; return 1 })
        }
        XCTAssertEqual(reads, 0)
        let p = cache.playback(fileID: "m", body: "a b c", timingsJSON: nil,
                               loadedDuration: 0, fallbackDuration: { reads += 1; return 9 })
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(p.duration, 9)
    }

    func testTheTextViewWordRangesAreMappedOnceUntilTheTextResets() {
        let cache = KaraokeStorageMapCache<[Int]>()
        var maps = 0
        for _ in 0..<10 {
            _ = cache.value(length: 42) { maps += 1; return [0, 1, 2] }
        }
        XCTAssertEqual(maps, 1)
        _ = cache.value(length: 43) { maps += 1; return [0] }
        XCTAssertEqual(maps, 2, "different text length: rebuilt")
        cache.reset()
        _ = cache.value(length: 43) { maps += 1; return [0] }
        XCTAssertEqual(maps, 3, "a render resets it")
    }

    // MARK: - N1: names.json is decoded once

    func testNamesJsonIsDecodedOnceAcrossTwoOpens() throws {
        let url = makeTempDir().appendingPathComponent("names.json")
        let writer = NamesStore(fileURL: url)
        writer.upsert(canonical: "Anna Test", aliases: ["Anna"], short: nil)

        let store = NamesStore(fileURL: url)
        XCTAssertEqual(store.livePeople().count, 1)    // note open 1
        XCTAssertEqual(store.livePeople().count, 1)    // note open 2
        _ = store.load()
        XCTAssertEqual(store.diskDecodes, 1, "decoded once, then served from memory")

        writer.upsert(canonical: "Ben Test", aliases: [], short: nil)   // another process / the sync wrote it
        XCTAssertEqual(store.livePeople().count, 2, "a changed file is re-read")
        XCTAssertEqual(store.diskDecodes, 2)
    }

    func testASaveWarmsTheCacheSoTheNextReadDecodesNothing() {
        let url = makeTempDir().appendingPathComponent("names.json")
        let store = NamesStore(fileURL: url)
        store.upsert(canonical: "Anna Test", aliases: [], short: nil)
        let before = store.diskDecodes
        _ = store.livePeople(); _ = store.livePeople()
        XCTAssertEqual(store.diskDecodes, before)
    }
}
