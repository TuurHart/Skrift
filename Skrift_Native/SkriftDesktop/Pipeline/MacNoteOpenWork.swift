import Foundation
import SwiftData

// Q362 (D186 / D191; plan/perf2/f-mac-ui.md M5 M7 M8 M12 M15, h-shared-data.md N1): what opening
// and playing a note may do with the rest of the library, on the Mac. The Mac half of the phone's
// `NoteOpenWork` (Q314). Before, every note open fetched every note several times (Connections
// backlinks, the fading line, the tag typeahead, the `[[` picker) and scanned every body for
// links; every 20 Hz playback tick split the body into words and decoded the timings JSON.
//
// Rule: library-wide facts are computed once per LIBRARY VERSION and read from then on. The
// version moves whenever any model context saves or a CloudKit import lands (`MacLibraryVersion`).

// MARK: - The library version

/// A counter that moves whenever the library may have changed. Caches keyed on it are rebuilt
/// at most once per change, never per note open.
@MainActor
final class MacLibraryVersion {
    /// The app's one counter: bumped by every `ModelContext` save (any store) and by a CloudKit import.
    static let shared = MacLibraryVersion(observingSaves: true)

    /// `MemoCloudReconciler`'s notification (`.cloudMemosDidChangeFromSync`, App/MemoCloudReconciler+Wiring.swift),
    /// spelled out here because the App folder is not part of the host-less test bundle.
    static let syncNotification = Notification.Name("skrift.cloudMemosDidChangeFromSync")

    private(set) var value = 0
    private var tokens: [NSObjectProtocol] = []

    init(observingSaves: Bool = false) {
        guard observingSaves else { return }
        for name in [ModelContext.didSave, Self.syncNotification] {
            let token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.bump() }
            }
            tokens.append(token)
        }
    }

    deinit { tokens.forEach { NotificationCenter.default.removeObserver($0) } }

    /// Something the caches read may have changed (a tag edit calls this before re-reading the counts).
    func bump() { value += 1 }
}

// MARK: - Plain values the Features layer maps onto its own types

struct MacBacklinkHit: Equatable {
    let fileID: String
    let title: String
    let date: Date
}

struct MacLinkCandidate: Equatable {
    let id: UUID
    let fileID: String
    let title: String
    let subtitle: String
    let sortDate: Date
}

// MARK: - The work

@MainActor
final class MacNoteOpenWork {

    static let shared = MacNoteOpenWork(version: .shared)

    private let version: MacLibraryVersion
    private let fileBacklinks = BacklinkIndexCache()
    private let memoBacklinks = BacklinkIndexCache()
    /// Row id the index was built with -> the note's string id (a local note with a non-UUID id
    /// still counts as a linker, under a throwaway row id).
    private var fileIDByRow: [UUID: String] = [:]
    private var candidates: (version: Int, items: [MacLinkCandidate])?
    private var tags: (version: Int, counts: [String: Int])?

    /// Every UNSCOPED fetch of notes, memos or polishes made for the work above. A fetch for a
    /// handful of ids does not count. The open-cost tests read this.
    private(set) var corpusFetches = 0
    var fileIndexBuilds: Int { fileBacklinks.buildCount }
    var memoIndexBuilds: Int { memoBacklinks.buildCount }

    init(version: MacLibraryVersion) { self.version = version }

    // MARK: Connections backlinks (M7)

    /// Who links to `file`, newest first. The scan is the shared `BacklinkIndex`, built once per
    /// library version off the main actor; the open itself fetches only the notes that link here
    /// and titles only those (`titleOf` is the seam the tests count).
    func backlinks(to file: PipelineFile, context: ModelContext,
                   titleOf: (PipelineFile) -> String) async -> [MacBacklinkHit] {
        guard let target = UUID(uuidString: file.id) else { return [] }
        let index = await fileBacklinks.index(version: version.value) { fileRows(context) }
        let ids = index.linkers(of: target).compactMap { fileIDByRow[$0] }.filter { $0 != file.id }
        guard !ids.isEmpty else { return [] }
        let linkers = (try? context.fetch(FetchDescriptor<PipelineFile>(
            predicate: #Predicate { ids.contains($0.id) }))) ?? []
        return linkers
            .filter { $0.deletedAt == nil }
            .map { MacBacklinkHit(fileID: $0.id, title: titleOf($0), date: $0.uploadedAt) }
            .sorted { $0.date > $1.date }
    }

    private func fileRows(_ context: ModelContext) -> [Backlinks.Row] {
        corpusFetches += 1
        let all = (try? context.fetch(FetchDescriptor<PipelineFile>())) ?? []
        var map: [UUID: String] = [:]
        var rows: [Backlinks.Row] = []
        rows.reserveCapacity(all.count)
        for f in all where f.deletedAt == nil {
            let rowID = UUID(uuidString: f.id) ?? UUID()
            map[rowID] = f.id
            // Q120: a phone link sits in the transcript, a Mac one in the name-linked or copy-edited body.
            rows.append(Backlinks.Row(id: rowID, bodies: [f.transcript, f.sanitised, f.enhancedCopyedit]))
        }
        fileIDByRow = map
        return rows
    }

    // MARK: The fading line of an unrated note (M8)

    /// The orange "starts fading … rate it to keep it" line for the memo behind an unrated note, or
    /// nil when it never fades. Reads the cached linked-id set (one pass over the memos + polishes
    /// per library version) and fetches the ONE memo by id.
    func fadingLine(forMemoID id: UUID, container: ModelContainer, now: Date = Date()) async -> String? {
        let ctx = ModelContext(container)   // fresh: a CloudKit import never refreshes a long-lived context
        var d = FetchDescriptor<Memo>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        guard let memo = try? ctx.fetch(d).first,
              memo.deletedAt == nil, memo.transcriptStatus == .done else { return nil }
        let linked = await memoBacklinks.index(version: version.value) { memoRows(container) }.linkedIDs
        guard !MemoLifecycle.neverFades(memo, backlinked: linked) else { return nil }
        return SharedCopy.fadingLine(WayOut.oneLiner(for: memo, backlinked: linked, now: now))
    }

    private func memoRows(_ container: ModelContainer) -> [Backlinks.Row] {
        corpusFetches += 2
        let ctx = ModelContext(container)
        let memos = (try? ctx.fetch(FetchDescriptor<Memo>())) ?? []
        let copyedits = Backlinks.copyeditsByMemoID(in: ctx)
        return memos.lazy.filter { $0.deletedAt == nil }
            .map { Backlinks.Row(id: $0.id, transcript: $0.transcript, copyedit: copyedits[$0.id]) }
    }

    // MARK: The `[[` picker and the tag typeahead (M15)

    /// Every other live note a memo-link can point at, newest first. Built once per library version.
    func linkCandidates(excluding fileID: String, context: ModelContext,
                        titleOf: (PipelineFile) -> String) -> [MacLinkCandidate] {
        if candidates?.version != version.value {
            let v = version.value
            corpusFetches += 1
            let all = (try? context.fetch(FetchDescriptor<PipelineFile>())) ?? []
            let df = DateFormatter(); df.dateStyle = .medium; df.timeStyle = .none
            let items: [MacLinkCandidate] = all
                .filter { $0.deletedAt == nil }
                .sorted { $0.uploadedAt > $1.uploadedAt }
                .compactMap { f in
                    guard let id = UUID(uuidString: f.id) else { return nil }   // memo-links key on the memo UUID
                    return MacLinkCandidate(id: id, fileID: f.id, title: titleOf(f),
                                            subtitle: df.string(from: f.uploadedAt), sortDate: f.uploadedAt)
                }
            candidates = (v, items)
        }
        return (candidates?.items ?? []).filter { $0.fileID != fileID }
    }

    /// How many live notes carry each tag. Once per library version.
    func tagCounts(_ context: ModelContext) -> [String: Int] {
        if tags?.version != version.value {
            let v = version.value
            corpusFetches += 1
            let files = (try? context.fetch(FetchDescriptor<PipelineFile>())) ?? []
            tags = (v, TagRules.counts(files.lazy.filter { $0.deletedAt == nil }.map(\.tags)))
        }
        return tags?.counts ?? [:]
    }
}

// MARK: - Playback (M5)

/// The karaoke word map for the note being played, built once per note VERSION (its id, its body,
/// its timings, its duration) instead of per 20 Hz tick: the body split into words, the timings JSON
/// decoded, the track aligned. A tick is then a key compare plus `track.activeIndex`.
/// A plain class on purpose: it lives in a view's `@State`, like `KaraokeTrackCache`.
final class MacKaraokeCache {
    struct Playback {
        let track: KaraokeTrack
        let duration: Double
    }
    private struct Key: Equatable {
        let fileID: String
        let body: String
        let timings: Data?
        let loadedDuration: Double
    }

    private var cached: (key: Key, value: Playback)?
    private var attributionMemo: (metadata: Data?, value: String?)?
    /// Word map builds (split + decode + align). Tests read this.
    private(set) var builds = 0
    private(set) var timingDecodes = 0

    init() {}

    /// `loadedDuration` is the player's real duration (0 until loaded); `fallbackDuration` is read
    /// only then (metadata hint), then the last word's end.
    func playback(fileID: String, body: String, timingsJSON: Data?, loadedDuration: Double,
                  fallbackDuration: () -> Double) -> Playback {
        let key = Key(fileID: fileID, body: body, timings: timingsJSON, loadedDuration: loadedDuration)
        if let cached, cached.key == key { return cached.value }
        builds += 1
        let words = body.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var timings: [WordTiming] = []
        if let timingsJSON {
            timingDecodes += 1
            timings = (try? JSONDecoder().decode([WordTiming].self, from: timingsJSON)) ?? []
        }
        var duration = loadedDuration
        if duration <= 0 { duration = fallbackDuration() }
        if duration <= 0 { duration = timings.last?.end ?? 0 }
        let value = Playback(track: KaraokeTrack(displayedWords: words, timings: timings, duration: duration),
                             duration: duration)
        cached = (key, value)
        return value
    }

    /// The book attribution under a quote, decoded from the metadata blob once per blob.
    func attribution(metadata: Data?, compute: () -> String?) -> String? {
        if let attributionMemo, attributionMemo.metadata == metadata { return attributionMemo.value }
        let value = compute()
        attributionMemo = (metadata, value)
        return value
    }
}

/// The text view's per-text map (word ranges + model word index), built once until the text is
/// re-rendered. Keyed on the storage length as a guard: the text view is read-only while playing.
final class KaraokeStorageMapCache<Value> {
    private var cached: (length: Int, value: Value)?
    init() {}

    func value(length: Int, build: () -> Value) -> Value {
        if let cached, cached.length == length { return cached.value }
        let v = build()
        cached = (length, v)
        return v
    }

    func reset() { cached = nil }
}
