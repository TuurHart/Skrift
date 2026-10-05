import XCTest
import SwiftData
import AVFoundation
import ImageIO
@testable import SkriftMobile

/// Q313: the `-perfLibrary` generator is deterministic, produces the documented shape into an
/// in-memory store, is stable under the at-open fading sweep, and the perf store configuration
/// has no CloudKit database and a different URL from SwiftData's default store.
final class PerfLibrarySeederTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("perf-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    private func words(_ s: String?) -> Int { (s ?? "").split(whereSeparator: \.isWhitespace).count }

    // MARK: configuration

    func testPerfStoreConfigurationHasNoCloudKitAndASeparateURL() throws {
        let schema = Schema([Memo.self, MemoAsset.self])
        let perf = PerfLibrary.storeConfiguration(schema: schema)
        XCTAssertEqual(perf.cloudKitDatabase, ModelConfiguration.CloudKitDatabase.none,
                       "the perf store must never be CloudKit-backed")
        XCTAssertEqual(perf.url.lastPathComponent, "perf.store")
        XCTAssertNotEqual(perf.url, ModelConfiguration(schema: schema).url, "must not be SwiftData's default store")
        XCTAssertNotEqual(perf.url, PerfLibrary.defaultStoreURL)
        XCTAssertEqual(perf.url.deletingLastPathComponent(), PerfLibrary.defaultStoreURL.deletingLastPathComponent(),
                       "next to the normal store")

        // And it really opens as an on-disk store (temp URL, so the sim's real folder is untouched).
        let url = tempDir().appendingPathComponent("perf.store")
        let container = try ModelContainer(for: schema,
                                           configurations: PerfLibrary.storeConfiguration(schema: schema, url: url))
        let ctx = ModelContext(container)
        ctx.insert(Memo(transcript: "x"))
        try ctx.save()
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testPerfFlagIsOffInTests() {
        XCTAssertFalse(PerfLibrary.isActive)
        XCTAssertTrue(AppPaths.namesFile.lastPathComponent == "names.json", "normal names file without the flag")
    }

    // MARK: determinism

    @MainActor
    func testGeneratorIsDeterministic() throws {
        func fingerprint() throws -> [String] {
            let repo = NotesRepository(inMemory: true)
            try PerfLibrarySeeder.seed(into: repo.context, recordingsDirectory: tempDir(), now: now,
                                       plan: .init(total: 200))
            return repo.allMemosIncludingTrashed()
                .sorted { $0.id.uuidString < $1.id.uuidString }
                .map { m in
                    let assets = repo.assets(forMemo: m.id).map { "\($0.kind):\($0.filename):\($0.byteCount)" }.sorted()
                    return [m.id.uuidString, "\(m.recordedAt.timeIntervalSince1970)", m.title ?? "-", m.transcript ?? "-",
                            m.tags.joined(separator: ","), "\(m.significance)", "\(m.locked)",
                            "\(m.deletedAt?.timeIntervalSince1970 ?? 0)", "\(m.keptAt?.timeIntervalSince1970 ?? 0)",
                            String(data: m.metadataData ?? Data(), encoding: .utf8) ?? "", assets.joined(separator: ";")]
                        .joined(separator: "|")
                }
        }
        let a = try fingerprint(), b = try fingerprint()
        XCTAssertEqual(a.count, 200)
        XCTAssertEqual(a, b, "same seed + same `now` must give the same library")
        XCTAssertEqual(PerfLibrarySeeder.makePeople(count: 150, now: now), PerfLibrarySeeder.makePeople(count: 150, now: now))
    }

    // MARK: the documented shape

    @MainActor
    func testFullLibraryShape() throws {
        let recordings = tempDir()
        let repo = NotesRepository(inMemory: true)
        let summary = try PerfLibrarySeeder.seed(into: repo.context, recordingsDirectory: recordings, now: now)
        let memos = repo.allMemosIncludingTrashed()
        XCTAssertEqual(memos.count, 2000)
        XCTAssertEqual(summary.memos, 2000)
        XCTAssertEqual(Set(memos.map(\.id)).count, 2000, "ids are unique")

        // kinds
        var typed = 0, links = 0, quotes = 0, recordings_ = 0, conversations = 0
        var voiceWords: [Int] = []
        for m in memos {
            switch SourceKind.of(m) {
            case .typedNote: typed += 1
            case .captureURL: links += 1
            case .audiobookQuote: quotes += 1
            case .voiceMemo:
                recordings_ += 1
                if SpeakerTranscript.isConversation(m.transcript, source: .audio) { conversations += 1 }
                else { voiceWords.append(words(m.transcript)) }
            default: XCTFail("unexpected source kind for \(m.id)")
            }
            if m.metadataData != nil { XCTAssertNotNil(m.metadata, "metadata blob decodes") }
            if m.sharedContentData != nil { XCTAssertNotNil(m.sharedContent, "sharedContent blob decodes") }
        }
        XCTAssertEqual(typed, 200)
        XCTAssertEqual(links, 100)
        XCTAssertEqual(quotes, 100)
        XCTAssertEqual(recordings_, 1600)
        XCTAssertEqual(conversations, 200, "10% conversations with **Name:** turns")
        XCTAssertEqual(voiceWords.count, 1400)

        // voice lengths: 5% long (2,000-6,000 words), the rest ~50-400
        let long = voiceWords.filter { $0 >= 2000 }
        XCTAssertEqual(long.count, 70)
        XCTAssertLessThanOrEqual(long.max() ?? 0, 6100)
        XCTAssertEqual(voiceWords.filter { $0 < 2000 && $0 >= 50 && $0 <= 470 }.count, 1330)

        // photos: 300 notes, 1-4 real ~2000 px JPEGs each, files on disk, markers in the text
        let photoNotes = memos.filter { !($0.metadata?.imageManifest ?? []).isEmpty }
        XCTAssertEqual(photoNotes.count, 300)
        var photoCount = 0
        for m in photoNotes {
            let manifest = m.metadata?.imageManifest ?? []
            XCTAssertTrue((1...4).contains(manifest.count))
            photoCount += manifest.count
            XCTAssertEqual((m.transcript ?? "").components(separatedBy: "[[img_").count - 1, manifest.count)
            XCTAssertTrue(m.transcriptMarkersInjected)
            for e in manifest { XCTAssertTrue(FileManager.default.fileExists(atPath: recordings.appendingPathComponent(e.filename).path)) }
        }
        XCTAssertEqual(summary.photoAssets, photoCount)
        let firstPhoto = try XCTUnwrap(photoNotes.first?.metadata?.imageManifest?.first)
        let photoBytes = try Data(contentsOf: recordings.appendingPathComponent(firstPhoto.filename))
        XCTAssertEqual(Array(photoBytes.prefix(2)), [0xFF, 0xD8], "real JPEG bytes")
        let src = try XCTUnwrap(CGImageSourceCreateWithData(photoBytes as CFData, nil))
        let props = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any])
        let w = props[kCGImagePropertyPixelWidth] as? Int ?? 0, h = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        XCTAssertEqual(max(w, h), 2000)

        // audio: 60 real AAC clips (45 voice + 15 quotes), a few seconds each
        XCTAssertEqual(summary.audioAssets, 60)
        let audioNotes = memos.filter { !$0.audioFilename.isEmpty && FileManager.default.fileExists(atPath: recordings.appendingPathComponent($0.audioFilename).path) }
        XCTAssertEqual(audioNotes.count, 60)
        let clipURL = recordings.appendingPathComponent(try XCTUnwrap(audioNotes.first).audioFilename)
        let clipBytes = try Data(contentsOf: clipURL)
        XCTAssertEqual(String(decoding: clipBytes[4..<8], as: UTF8.self), "ftyp", "an MP4/M4A container")
        let file = try AVAudioFile(forReading: clipURL)
        let seconds = Double(file.length) / file.processingFormat.sampleRate
        XCTAssertTrue((2...5).contains(seconds), "a few seconds, got \(seconds)")
        XCTAssertEqual(repo.assets(forMemo: try XCTUnwrap(audioNotes.first).id).filter { $0.kind == MemoAsset.Kind.audio }.count, 1)

        // tags from a pool of 80
        XCTAssertEqual(PerfLibrarySeeder.tagPool.count, 80)
        let tagsUsed = Set(memos.flatMap(\.tags))
        XCTAssertTrue(tagsUsed.isSubset(of: Set(PerfLibrarySeeder.tagPool)))
        XCTAssertGreaterThan(tagsUsed.count, 50)

        // memo links between ~200 notes; every target exists
        let ids = Set(memos.map(\.id))
        let sources = memos.filter { !MemoLinkSyntax.occurrences(in: $0.transcript ?? "").isEmpty }
        XCTAssertEqual(sources.count, summary.linkSources)
        XCTAssertTrue((190...200).contains(sources.count), "got \(sources.count)")
        for s in sources { for o in MemoLinkSyntax.occurrences(in: s.transcript ?? "") { XCTAssertTrue(ids.contains(o.id)) } }

        // ratings: a real mix incl. unrated; some locked
        let unrated = memos.filter { !NoteConsent.isRated($0) }.count
        XCTAssertGreaterThan(unrated, 200); XCTAssertGreaterThan(2000 - unrated, 1000)
        XCTAssertGreaterThanOrEqual(memos.filter(\.locked).count, 40)
        XCTAssertLessThanOrEqual(memos.filter(\.locked).count, 60)

        // lifecycle: 100 fading, 50 trashed, and NOTHING due for the at-open sweep
        let trashed = memos.filter { $0.deletedAt != nil }
        XCTAssertEqual(trashed.count, 50)
        XCTAssertTrue(trashed.allSatisfy { !MemoLifecycle.purgeDue($0, now: now) })
        let live = memos.filter { $0.deletedAt == nil }
        let backlinked = MemoLifecycle.backlinkedIDs(in: live)
        XCTAssertEqual(MemoLifecycle.partition(live, backlinked: backlinked, now: now).fading.count, 100)
        XCTAssertEqual(live.filter { MemoLifecycle.sweepDue($0, backlinked: backlinked, now: now) }.count, 0,
                       "a first launch must not move notes to Recently Deleted")

        // three years
        let oldest = try XCTUnwrap(memos.map(\.recordedAt).min()), newest = try XCTUnwrap(memos.map(\.recordedAt).max())
        XCTAssertGreaterThan(now.timeIntervalSince(oldest), 2.8 * 365 * 86_400)
        XCTAssertLessThan(now.timeIntervalSince(newest), 3 * 86_400)

        // 150 people with aliases, in the names.json shape
        let people = PerfLibrarySeeder.makePeople(count: 150, now: now)
        XCTAssertEqual(Set(people.map(\.canonical)).count, 150)
        XCTAssertTrue(people.allSatisfy { !$0.aliases.isEmpty && $0.canonical.hasPrefix("[[") })
        let namesURL = tempDir().appendingPathComponent("names.perf.json")
        PerfLibrary.writeNames(people, to: NamesStore(fileURL: namesURL))
        XCTAssertEqual(NamesStore(fileURL: namesURL).livePeople().count, 150)
    }
}
