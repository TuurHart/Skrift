import Foundation
import CoreMLLLM

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
            model = try await EmbeddingGemma.downloadAndLoad(modelsDir: Self.modelsDir)
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

    /// Never leave a model pinned (desktop lesson). Unloads ~60 s after last use;
    /// the next embed reloads from the on-disk cache in a moment.
    private func scheduleIdleUnload() {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 65_000_000_000)
            await self?.unloadIfIdle()
        }
    }

    private func unloadIfIdle() {
        if Date().timeIntervalSince(lastUse) >= 60 { model = nil }
    }

    enum EmbeddingError: Error { case notLoaded }
}
