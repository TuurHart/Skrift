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

    /// Bumped on every consent write so views that read `isEnabled` (UserDefaults is not
    /// observable) re-render when the Settings switch or the panel gate moves it.
    private(set) var consentRevision = 0
    var isEnabled: Bool {
        get { _ = consentRevision; return UserDefaults.standard.bool(forKey: Self.enabledDefaultsKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.enabledDefaultsKey)
            consentRevision += 1
        }
    }
    var isModelDownloaded: Bool { GemmaEmbedder.isModelDownloaded }
    /// The panel's query surfaces (rows, thread, why-chips) exist only when true.
    var isActive: Bool { isEnabled && isModelDownloaded }

    private init() {
        // The shared embedder's app-wired seam (it can't see the app's logger).
        GemmaEmbedder.log = { [logger] msg in
            logger.log("\(msg, privacy: .public)")
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
                    // Same as the phone after a failed download: the switch flips back off, the
                    // failure line stays (Settings + the gate both read `lastError`).
                    self.isEnabled = false
                    self.lastError = RetrievalGate.Copy.downloadFailed(error.localizedDescription)
                }
            }
            GemmaEmbedder.downloadProgress = nil
        }
    }

    /// The Settings switch (Q161): on = the panel gate's enable flow; off = withdraw consent.
    /// Withdrawing stops sweeps and hides every semantic surface; the model and the local
    /// index stay on disk, so turning it back on is instant (the phone's rule).
    func setConsent(_ on: Bool, _ context: ModelContext) {
        switch RetrievalGate.consentAction(wasEnabled: isEnabled, nowEnabled: on) {
        case .enable: enableAndDownload(context)
        case .withdraw: isEnabled = false; lastError = nil
        case .none: break
        }
    }

    /// Fire-and-forget engine load — call on note switch and on the first search keystroke
    /// (Q168) so the first query doesn't pay the cold load.
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
        // Consent-gated membership (NoteConsent.joinsConnectionsIndex): live +
        // rated. Rows absent from this set are REMOVED by the sweep's orphan
        // pass, so un-rating a note also withdraws it from the graph.
        // Q168: the TEXT comes from the synced Memo + MemoEnhancement (the phone's rule), so
        // one note embeds the same words on both devices. A fresh context sees CloudKit imports.
        let cloud = MemoCloudStore.container.map { ModelContext($0) }
        let snapshots = MacEmbeddingSnapshot.snapshots(files: files, cloud: cloud)
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
                await MainActor.run { self?.lastError = nil }   // a good sweep ends the failure Settings showed
            } catch {
                logger.error("Connections sweep failed: \(error, privacy: .public)")
                await MainActor.run { self?.lastError = RetrievalGate.Copy.sweepFailed(error.localizedDescription) }
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
            let out = try await resolvedIndex().related(to: memoID)
            lastError = nil
            return out
        } catch {
            logger.error("Connections related \(memoID.uuidString.prefix(8), privacy: .public) failed: \(error, privacy: .public)")
            // Observable, not just logged — an empty panel with lastError set is
            // "Connections unavailable", NOT "no matches" (the no-bad-info rule).
            lastError = "Related lookup failed: \(error.localizedDescription)"
            return []
        }
    }

    /// Scores of every indexed memo against a typed query — the sidebar's Related section
    /// (the phone's `JournalIndexService.searchScores`). The caller applies the shared floor.
    func searchScores(_ query: String) async -> [(memoID: UUID, score: Float)] {
        guard isActive else { return [] }
        do {
            return try await resolvedIndex().search(query)
        } catch {
            logger.error("Connections search failed: \(error, privacy: .public)")
            lastError = "Search by meaning failed: \(error.localizedDescription)"
            return []
        }
    }

    // ── snapshots ──

    /// The journal/thread axis (panel dates + thread order): the phone's recorded
    /// moment when synced; locally-ingested files fall back to their upload time.
    nonisolated static func journalDate(_ file: PipelineFile) -> Date {
        let meta = MemoMetadata.lenient(from: file.audioMetadataJSON)
        return meta?.recordedAt.flatMap { ISO8601.date(from: $0) } ?? (MemoDate.isUnknown(file.uploadedAt) ? (file.lastActivityAt ?? Date()) : file.uploadedAt)
    }
}
