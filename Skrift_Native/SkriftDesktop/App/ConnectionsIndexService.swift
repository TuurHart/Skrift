import Foundation
import SwiftData
import os

/// Mac side of the Connections panel (`mocks/related-panel.html`): PipelineFiles →
/// `MemoSnapshot`s → the SHARED `EmbeddingIndex` — the phone's `JournalIndexService`
/// shape over the Mac's store + triggers. INERT unless the user turned Connections
/// on (the panel's consent gate) AND the 295 MB model is on disk: a background
/// sweep must never trigger a surprise download (phone rule, kept).
///
/// Each device builds its OWN local index — embeddings never sync (private by
/// construction; delete the store and a sweep rebuilds it from the queue).
@MainActor
@Observable
final class ConnectionsIndexService {
    static let shared = ConnectionsIndexService()

    /// Deliberately the SAME defaults string as the phone's Journal gate — one
    /// cross-app semantic ("this device's semantic index is on"); each device
    /// still consents on its own (defaults don't sync).
    static let enabledDefaultsKey = "journalIndexEnabled"

    private let logger = Logger(subsystem: "com.skrift.desktop", category: "connections")
    private var index: EmbeddingIndex?
    private(set) var sweeping = false
    /// Drives the panel gate's "Building the index — N of M"; nil when idle.
    private(set) var sweepProgress: (done: Int, total: Int)?
    /// 0…1 while the consent gate's model download runs; nil otherwise.
    private(set) var downloadFraction: Double?
    var lastError: String?

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.enabledDefaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.enabledDefaultsKey) }
    }
    var isModelDownloaded: Bool { GemmaEmbedder.isModelDownloaded }
    /// The panel's query surfaces (rows, thread, why-chips) exist only when true.
    var isActive: Bool { isEnabled && isModelDownloaded }

    private init() {
        // The shared embedder's app-wired seam (it can't see the app's logger).
        GemmaEmbedder.log = { msg in
            Logger(subsystem: "com.skrift.desktop", category: "connections")
                .log("\(msg, privacy: .public)")
        }
    }

    private func resolvedIndex() -> EmbeddingIndex {
        if let index { return index }
        let fresh = EmbeddingIndex(store: EmbeddingStore(), engine: GemmaEmbedder.shared)
        index = fresh
        return fresh
    }

    // ── the consent gate's enable flow (mock #m4): consent → download → first sweep ──

    /// "Turn on Connections": set the flag, pull the model (progress → the gate's
    /// bar), then sweep. Idempotent — with the model already on disk it goes
    /// straight to the sweep.
    func enableAndDownload(_ context: ModelContext) {
        isEnabled = true
        lastError = nil
        guard downloadFraction == nil else { return }
        if isModelDownloaded { sweepSoon(context); return }
        downloadFraction = 0
        GemmaEmbedder.downloadProgress = { received, total in
            Task { @MainActor in
                ConnectionsIndexService.shared.downloadFraction =
                    total > 0 ? Double(received) / Double(total) : 0
            }
        }
        Task { [weak self] in
            do {
                try await GemmaEmbedder.shared.prepare()   // downloads when missing
                await MainActor.run {
                    guard let self else { return }
                    self.downloadFraction = nil
                    self.sweepSoon(context)
                }
            } catch {
                await MainActor.run {
                    guard let self else { return }
                    self.downloadFraction = nil
                    self.lastError = "Model download failed: \(error.localizedDescription)"
                }
            }
            GemmaEmbedder.downloadProgress = nil
        }
    }

    /// Fire-and-forget engine load — call on note switch so the first row query
    /// doesn't pay the cold load (the panel opens instantly, rows fill in).
    func warmUp() {
        guard isActive else { return }
        Task.detached(priority: .utility) { try? await GemmaEmbedder.shared.prepare() }
    }

    // ── sweep ──

    /// Hash-diff sweep of the whole queue (trash excluded). Debounced by
    /// `sweeping`; rides every cloud reconcile + pipeline run, so a redundant
    /// call is nearly free (hash matches skip).
    func sweepSoon(_ context: ModelContext) {
        guard isActive, !sweeping else { return }
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }

        let files = (try? context.fetch(FetchDescriptor<PipelineFile>())) ?? []
        let snapshots = files.filter { $0.deletedAt == nil }.compactMap(Self.snapshot)
        let index = resolvedIndex()
        sweeping = true
        sweepProgress = (0, snapshots.count)
        Task.detached(priority: .utility) { [weak self, logger] in
            let t0 = Date()
            do {
                let stats = try await index.sweep(snapshots) { done, total in
                    Task { @MainActor in self?.sweepProgress = (done, total) }
                }
                logger.log("Connections sweep: \(stats.embedded, privacy: .public) embedded · \(stats.skipped, privacy: .public) skipped · \(stats.removed, privacy: .public) removed · \(Date().timeIntervalSince(t0), format: .fixed(precision: 1))s for \(snapshots.count, privacy: .public) memos")
            } catch {
                logger.error("Connections sweep failed: \(error, privacy: .public)")
                await MainActor.run { self?.lastError = "Index sweep failed: \(error.localizedDescription)" }
            }
            await MainActor.run {
                self?.sweeping = false
                self?.sweepProgress = nil
            }
        }
    }

    // ── queries (scores only — the panel applies RetrievalTuning floors + sorting) ──

    /// Semantic neighbours of one memo (score = max cosine over its rows),
    /// unfiltered. LOUD on failure (the phone's device-round-5 lesson: a swallowed
    /// engine error and an honest below-floor miss look identical without a trace).
    func relatedScores(to memoID: UUID) async -> [(memoID: UUID, score: Float)] {
        guard isActive else { return [] }
        do {
            return try await resolvedIndex().related(to: memoID)
        } catch {
            logger.error("Connections related \(memoID.uuidString.prefix(8), privacy: .public) failed: \(error, privacy: .public)")
            return []
        }
    }

    // ── snapshots ──

    /// Index-relevant content of one PipelineFile — nil when it can't join the
    /// index (non-UUID id = pre-CloudKit demo rows; empty body = nothing to embed).
    static func snapshot(_ file: PipelineFile) -> MemoSnapshot? {
        guard let uuid = UUID(uuidString: file.id) else { return nil }
        let body = file.sanitised ?? file.enhancedCopyedit ?? file.transcript ?? ""
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let meta = file.audioMetadataJSON.flatMap { try? JSONDecoder().decode(PhoneMetadata.self, from: $0) }
        let title = file.enhancedTitle?.trimmingCharacters(in: .whitespaces)
        return MemoSnapshot(
            id: uuid,
            title: (title?.isEmpty == false) ? title : nil,
            summary: file.enhancedSummary,
            body: body,
            place: meta?.location?.placeName,
            tags: file.tags,
            createdAt: journalDate(file))
    }

    /// The journal/thread axis (panel dates + thread order): the phone's recorded
    /// moment when synced; locally-ingested files fall back to their upload time.
    nonisolated static func journalDate(_ file: PipelineFile) -> Date {
        let meta = file.audioMetadataJSON.flatMap { try? JSONDecoder().decode(PhoneMetadata.self, from: $0) }
        return meta?.recordedAt.flatMap { ISO8601.date(from: $0) } ?? file.uploadedAt
    }
}
