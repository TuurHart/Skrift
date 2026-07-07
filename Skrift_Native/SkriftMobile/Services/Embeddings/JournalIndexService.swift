import Foundation

/// App-side bridge: `NotesRepository` → snapshots → `EmbeddingIndex` sweep.
///
/// INERT BY DEFAULT: the sweep runs only when (a) the user enabled the journal
/// index (the Journal UI's download-consent flow sets the flag) AND (b) the
/// 295 MB model is already on disk — a background sweep must never trigger a
/// surprise download or fight ASR for memory (iPhone-13 rule: the sweep runs on
/// foreground, when no recording is active).
@MainActor
final class JournalIndexService {
    static let shared = JournalIndexService()

    static let enabledDefaultsKey = "journalIndexEnabled"

    private var index: EmbeddingIndex?
    private var sweeping = false

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.enabledDefaultsKey)
    }

    /// Foreground entry point (SkriftApp scenePhase). Debounced by the
    /// `sweeping` flag; hash-diffing makes a redundant sweep nearly free.
    func sweepSoon(_ repository: NotesRepository) {
        guard isEnabled, GemmaEmbedder.isModelDownloaded, !sweeping else { return }
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }

        let snapshots = Self.snapshots(from: repository)
        let index = resolvedIndex()
        sweeping = true
        Task.detached(priority: .utility) { [weak self] in
            do {
                let stats = try await index.sweep(snapshots)
                DevLog.log("JournalIndex sweep: \(stats)")
            } catch {
                DevLog.log("JournalIndex sweep failed: \(error)")
            }
            await MainActor.run { self?.sweeping = false }
        }
    }

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

    private func resolvedIndex() -> EmbeddingIndex {
        if let index { return index }
        let fresh = EmbeddingIndex(store: EmbeddingStore(), engine: GemmaEmbedder.shared)
        index = fresh
        return fresh
    }
}
