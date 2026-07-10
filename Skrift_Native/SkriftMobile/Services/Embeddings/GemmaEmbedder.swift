import Foundation
import CoreMLLLM
import UIKit

/// Production engine: EmbeddingGemma-300M via CoreML-LLM, on the ANE.
///
/// Decided by the 2026-07-07 bake-off (`spikes/EmbeddingBakeoff/`): 10/10 top-1,
/// margin +0.37, EN↔NL 3/3, ~5 ms/embed — Apple's NLContextualEmbedding was
/// eliminated (5/10). **Dim 512 is fixed at load and never switched** — encoding
/// two Matryoshka dims on one live instance was flaky in the spike; one dim is
/// 100% stable.
///
/// App-side (not `Shared/Retrieval/`) only because the CoreML-LLM package is
/// mobile-only until the Mac adopts it in Phase 2 — then this file moves.
actor GemmaEmbedder: EmbeddingEngine {
    static let shared = GemmaEmbedder()

    nonisolated let modelRev = "embeddinggemma-300m-d512"
    private let dim = 512
    private var model: EmbeddingGemma?
    private var lastUse = Date.distantPast

    /// Foreground hold: a cold `prepare()` costs MINUTES on an A15 (ANE model
    /// load + the 31.8 MB tokenizer parse — devlog 2026-07-08: first query of a
    /// session stalled ~2 min and queued everything behind the actor), so the
    /// old 60 s idle window re-paid that on nearly every search. Hold for 10
    /// minutes while the app is frontmost; backgrounding unloads immediately
    /// (the observer below), which keeps the memory citizenship the 60 s window
    /// was buying.
    private let idleUnloadAfter: TimeInterval = 600

    private init() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil
        ) { _ in
            Task { await GemmaEmbedder.shared.unloadNow() }
        }
    }

    /// ~295 MB, cached here after the first download.
    static var modelsDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EmbeddingModels", isDirectory: true)
    }

    /// True once the model files exist on disk — the sweep must NOT trigger a
    /// surprise 295 MB download; the Journal UI owns the download consent flow.
    static var isModelDownloaded: Bool {
        FileManager.default.fileExists(
            atPath: modelsDir.appendingPathComponent("embeddinggemma-300m").path)
    }

    func prepare() async throws {
        if model == nil {
            let t0 = Date()
            DevLog.log("embedder: cold load START")
            model = try await EmbeddingGemma.downloadAndLoad(modelsDir: Self.modelsDir)
            DevLog.log(String(format: "embedder: cold load DONE in %.1fs", Date().timeIntervalSince(t0)))
        }
        lastUse = Date()
        scheduleIdleUnload()
    }

    func embed(_ text: String, isQuery: Bool) async throws -> [Float] {
        try await prepare()
        guard let model else { throw EmbeddingError.notLoaded }
        let v = try model.encode(text: text,
                                 task: isQuery ? .retrievalQuery : .retrievalDocument,
                                 dim: dim)
        lastUse = Date()
        return RetrievalMath.normalize(v)
    }

    /// Never leave a model pinned forever (desktop lesson) — but see
    /// `idleUnloadAfter`: the reload is minutes, not "a moment", so the idle
    /// window must outlast a whole search-and-read session.
    private func scheduleIdleUnload() {
        Task { [weak self, idleUnloadAfter] in
            try? await Task.sleep(nanoseconds: UInt64((idleUnloadAfter + 5) * 1_000_000_000))
            await self?.unloadIfIdle()
        }
    }

    private func unloadIfIdle() {
        if model != nil, Date().timeIntervalSince(lastUse) >= idleUnloadAfter {
            model = nil
            DevLog.log("embedder: unloaded after idle")
        }
    }

    /// Backgrounding: give the memory back right away — a suspended app holding
    /// 295 MB is first in line for jetsam.
    func unloadNow() {
        if model != nil {
            model = nil
            DevLog.log("embedder: unloaded on background")
        }
    }

    enum EmbeddingError: Error { case notLoaded }
}
