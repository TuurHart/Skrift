import Foundation

/// App-side bridge: `NotesRepository` → snapshots → `EmbeddingIndex`, plus the
/// query passthroughs the UI uses (search Related, threads).
///
/// INERT BY DEFAULT: everything activates only when (a) the user enabled the
/// journal index (the Journal UI's download-consent flow sets the flag) AND
/// (b) the 295 MB model is already on disk — a background sweep must never
/// trigger a surprise download or fight ASR for memory. The sim/UI-test escape
/// hatch is `-mockJournalIndex`: an in-memory index over `MockEmbedder` with
/// demo axes matching `-seedJournal`, so search/threads are demoable without
/// model assets.
@MainActor
@Observable
final class JournalIndexService {
    static let shared = JournalIndexService()

    static let enabledDefaultsKey = "journalIndexEnabled"

    private var index: EmbeddingIndex?
    private var sweeping = false
    private var mockSeeded = false
    /// Live "N of M" while a sweep runs (the settings gate's indexing row —
    /// shared-gate parity with the Mac panel); nil when idle.
    private(set) var sweepProgress: (done: Int, total: Int)?

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.enabledDefaultsKey)
    }

    /// Query surfaces (search Related section, View Thread) exist only when this
    /// is true — otherwise the whole feature stays invisible.
    var isActive: Bool {
        if LaunchFlags.mockJournalIndex { return true }
        return isEnabled && GemmaEmbedder.isModelDownloaded
    }

    /// Fire-and-forget engine load, called when the user starts a search so the
    /// Related section doesn't pay the model load — exact Matches never wait.
    func warmUp() {
        guard isActive, !LaunchFlags.mockJournalIndex else { return }
        Task.detached(priority: .utility) { try? await GemmaEmbedder.shared.prepare() }
    }

    /// Foreground entry point (SkriftApp scenePhase). Debounced by the
    /// `sweeping` flag; hash-diffing makes a redundant sweep nearly free.
    func sweepSoon(_ repository: NotesRepository) {
        guard isActive, !sweeping else { return }
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }

        let snapshots = Self.snapshots(from: repository)
        let index = resolvedIndex()
        sweeping = true
        sweepProgress = (0, snapshots.count)
        Task.detached(priority: .utility) { [weak self] in
            let t0 = Date()
            do {
                let stats = try await index.sweep(snapshots) { done, total in
                    Task { @MainActor in self?.sweepProgress = (done, total) }
                }
                // The chunk-8 perf trace: pull via devlog after a device sweep.
                DevLog.log(String(format: "JournalIndex sweep: %d embedded · %d skipped · %d removed · %.1fs for %d memos",
                                  stats.embedded, stats.skipped, stats.removed,
                                  Date().timeIntervalSince(t0), snapshots.count))
            } catch {
                DevLog.log("JournalIndex sweep failed: \(error)")
            }
            await MainActor.run {
                self?.sweeping = false
                self?.sweepProgress = nil
            }
        }
    }

    /// Chunk-3/8 calibration harness: score distributions over the REAL corpus,
    /// written to the devlog (pull via devicectl). Gist-pair percentiles say
    /// where the related/thread floors should sit; query trials sanity-check
    /// search. DEBUG-only entry (Settings dev row).
    func logScoreHistogram(_ repository: NotesRepository) {
        let index = resolvedIndex()
        Task.detached(priority: .utility) {
            do {
                let sample = try await index.gistPairScores(limit: 2000)
                guard !sample.isEmpty else { DevLog.log("Histogram: empty index"); return }
                let sorted = sample.sorted()
                func pct(_ p: Double) -> Float { sorted[min(sorted.count - 1, Int(p * Double(sorted.count)))] }
                DevLog.log(String(format: "Histogram gist-pairs n=%d · p10 %.3f · p50 %.3f · p90 %.3f · p99 %.3f · max %.3f (floors: related %.2f, search %.2f)",
                                  sorted.count, pct(0.10), pct(0.50), pct(0.90), pct(0.99),
                                  sorted.last ?? 0, RetrievalTuning.relatedFloor, RetrievalTuning.searchFloor))
            } catch {
                DevLog.log("Histogram failed: \(error)")
            }
        }
    }

    // ── queries ──

    /// Semantic scores for a search query (memo id → max cosine), unfiltered —
    /// the caller applies floors/filters/exclusions via `relatedResults`.
    /// LOUD on purpose (device round 5: "semantic search sometimes finds
    /// nothing" — a swallowed model-load error and an honest below-floor miss
    /// look identical without the trace).
    func searchScores(_ query: String, repository: NotesRepository) async -> [(memoID: UUID, score: Float)] {
        guard isActive else { return [] }
        await ensureMockSeeded(repository)
        do {
            let scores = try await resolvedIndex().search(query)
            let top = scores.first.map { String(format: "%.2f", $0.score) } ?? "—"
            DevLog.log("SemanticSearch '\(query.prefix(40))' → \(scores.count) scored · top \(top) · floor \(RetrievalTuning.searchFloor)")
            return scores
        } catch {
            DevLog.log("SemanticSearch FAILED '\(query.prefix(40))': \(error)")
            return []
        }
    }

    /// Scores against a memo's gist — powers threads (and later the Related card).
    func relatedScores(to memoID: UUID, repository: NotesRepository) async -> [(memoID: UUID, score: Float)] {
        guard isActive else { return [] }
        await ensureMockSeeded(repository)
        do {
            return try await resolvedIndex().related(to: memoID)
        } catch {
            DevLog.log("Related FAILED \(memoID.uuidString.prefix(8)): \(error)")
            return []
        }
    }

    /// The pair type + pick moved to `Shared/Retrieval/ThenVsNow` (iPad wave v2 —
    /// one rule on all three devices); this alias keeps the phone's API stable.
    typealias ThenNowPair = ThenVsNow.Pair

    /// Then vs Now (fast-follow, built 2026-07-08; core SHARED since v2): the
    /// newest memos vs their ≥6-month-older semantic kin. Window + pick =
    /// `ThenVsNow`; this wrapper feeds it the phone's related-scores.
    func thenVsNow(repository: NotesRepository) async -> ThenNowPair? {
        guard isActive else { return nil }
        let memos = repository.allMemos()
        let calendar = Calendar.current
        let now = Date()
        guard let recentCut = calendar.date(byAdding: .day, value: -ThenVsNow.recentWindowDays, to: now),
              let gapCut = calendar.date(byAdding: .month, value: -ThenVsNow.minGapMonths, to: now) else { return nil }
        let dates = Dictionary(memos.map { ($0.id, $0.recordedAt) }, uniquingKeysWith: { a, _ in a })
        let recents = memos.filter { $0.recordedAt >= recentCut }
            .sorted { $0.recordedAt > $1.recordedAt }
            .prefix(ThenVsNow.maxRecents)
        var candidates: [(now: UUID, hits: [(memoID: UUID, score: Float)])] = []
        for memo in recents {
            candidates.append((memo.id, await relatedScores(to: memo.id, repository: repository)))
        }
        return Self.bestThenNow(candidates: candidates, dates: dates, gapCut: gapCut,
                                floor: RetrievalTuning.relatedFloor)
    }

    /// Pure pair-picking — forwards to the SHARED `ThenVsNow.pick` (kept for
    /// API/test stability; the rule itself lives in Shared/Retrieval).
    nonisolated static func bestThenNow(
        candidates: [(now: UUID, hits: [(memoID: UUID, score: Float)])],
        dates: [UUID: Date], gapCut: Date, floor: Float) -> ThenNowPair? {
        ThenVsNow.pick(candidates: candidates, dates: dates, gapCut: gapCut, floor: floor)
    }

    // ── pure result shaping (unit-tested) ──

    /// The search "Related" section: floor-gated, exact hits excluded, best-first.
    nonisolated static func relatedResults(scores: [(memoID: UUID, score: Float)],
                               excluding exact: Set<UUID>,
                               memosByID: [UUID: Memo],
                               floor: Float = RetrievalTuning.searchFloor,
                               limit: Int = 8) -> [Memo] {
        scores
            .filter { $0.score >= floor && !exact.contains($0.memoID) }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .compactMap { memosByID[$0.memoID] }
    }

    /// A thread = the seed + its related-above-floor set, oldest first (the arc
    /// of the idea; `.first` is the first mention).
    nonisolated static func threadOrder(seedID: UUID,
                            scores: [(memoID: UUID, score: Float)],
                            memosByID: [UUID: Memo],
                            floor: Float = RetrievalTuning.relatedFloor) -> [Memo] {
        var members = scores
            .filter { $0.score >= floor }
            .compactMap { memosByID[$0.memoID] }
        if let seed = memosByID[seedID] { members.append(seed) }
        return members.sorted { LookbackProvider.journalDate($0) < LookbackProvider.journalDate($1) }
    }

    // ── snapshots ──

    /// Snapshots are built on the main actor — `Memo` is a main-context @Model
    /// and must not cross into the index actor.
    static func snapshots(from repository: NotesRepository) -> [MemoSnapshot] {
        repository.allMemos().compactMap { memo in
            let enhancement = repository.enhancement(forMemo: memo.id)
            let polished = (enhancement?.hasContent == true) ? enhancement?.copyedit : nil
            let body = polished ?? memo.transcript ?? ""
            let annotated = memo.annotationText.map { body.isEmpty ? $0 : body + "\n" + $0 } ?? body
            guard !annotated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return MemoSnapshot(
                id: memo.id,
                title: memo.title ?? enhancement?.title,
                summary: enhancement?.summary,
                body: annotated,
                place: memo.metadata?.location?.placeName,
                tags: memo.tags,
                createdAt: memo.recordedAt // journal axis = recorded moment (see LookbackProvider)
            )
        }
    }

    // ── wiring ──

    /// Mock path: sweep once on first query so sim demos/tests have an index.
    private func ensureMockSeeded(_ repository: NotesRepository) async {
        guard LaunchFlags.mockJournalIndex, !mockSeeded else { return }
        mockSeeded = true
        _ = try? await resolvedIndex().sweep(Self.snapshots(from: repository))
    }

    private func resolvedIndex() -> EmbeddingIndex {
        if let index { return index }
        let fresh = LaunchFlags.mockJournalIndex
            ? EmbeddingIndex(store: EmbeddingStore(inMemory: true), engine: Self.demoEngine())
            : EmbeddingIndex(store: EmbeddingStore(), engine: GemmaEmbedder.shared)
        index = fresh
        return fresh
    }

    /// Keyword axes matching the `-seedJournal` memos, so sim search/threads
    /// behave like the real engine ("cost money" relates to the subscription
    /// memo with no shared substring).
    private static func demoEngine() -> EmbeddingEngine {
        let mock = MockEmbedder(dimension: 32)
        mock.register("cost money", [1, 0.1, 0, 0])
        mock.register("subscription", [0.92, 0.39, 0, 0])
        mock.register("fietslease", [0, 0, 1, 0])
        mock.register("standalone", [0.1, 0, 0, 0.99])
        mock.register("walk", [0, 0, 0, 1])
        return mock
    }
}
