import Foundation
import CoreMLLLM
#if canImport(UIKit)
import UIKit
#endif

/// Production engine: EmbeddingGemma-300M via CoreML-LLM, on the ANE.
///
/// Decided by the 2026-07-07 bake-off (`spikes/EmbeddingBakeoff/`): 10/10 top-1,
/// margin +0.37, EN↔NL 3/3, ~5 ms/embed — Apple's NLContextualEmbedding was
/// eliminated (5/10). **Dim 512 is fixed at load and never switched** — encoding
/// two Matryoshka dims on one live instance was flaky in the spike; one dim is
/// 100% stable.
///
/// `Shared/RetrievalEngine/` — compiled by BOTH app targets, NEVER by the
/// host-less test bundles (it links the CoreML-LLM package; tests use
/// `MockEmbedder`). One engine + one `modelRev` ⇒ the two devices' local
/// indexes stay comparable.
actor GemmaEmbedder: EmbeddingEngine {
    static let shared = GemmaEmbedder(
        loader: {
            try await EmbeddingGemma.downloadAndLoad(modelsDir: GemmaEmbedder.modelsDir) { p in
                GemmaEmbedder.downloadProgress?(p.bytesReceived, p.bytesTotal)
            }
        },
        observesBackground: true)

    /// How the model gets loaded. Production = download + CoreML load; tests inject a
    /// counting stand-in, because `EmbeddingGemma` itself needs the 295 MB assets.
    typealias Loader = @Sendable () async throws -> EmbeddingGemma
    private let loader: Loader

    /// App-wired log sink (phone → DevLog, Mac → its own trace). No-op default.
    nonisolated(unsafe) static var log: @Sendable (String) -> Void = { _ in }

    /// App-wired download progress (bytesReceived, bytesTotal) — drives the consent
    /// gates' "121 / 295 MB" bars. nil = nobody listening.
    nonisolated(unsafe) static var downloadProgress: (@Sendable (Int64, Int64) -> Void)?

    nonisolated let modelRev = "embeddinggemma-300m-d512"
    private let dim = 512
    private var model: EmbeddingGemma?
    private var lastUse = Date.distantPast
    private var idleTask: Task<Void, Never>?

    /// Foreground hold: a cold `prepare()` costs MINUTES on an A15 (ANE model
    /// load + the 31.8 MB tokenizer parse — devlog 2026-07-08: first query of a
    /// session stalled ~2 min and queued everything behind the actor), so the
    /// old 60 s idle window re-paid that on nearly every search. Hold for 10
    /// minutes while the app is frontmost; backgrounding unloads immediately
    /// (the observer below), which keeps the memory citizenship the 60 s window
    /// was buying.
    private let idleUnloadAfter: TimeInterval = 600

    init(loader: @escaping Loader, observesBackground: Bool = false) {
        self.loader = loader
        // iOS: a suspended app holding 295 MB is first in line for jetsam — free it
        // on background. macOS has no jetsam pressure; the idle timer suffices.
        #if canImport(UIKit)
        guard observesBackground else { return }
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil
        ) { _ in
            Task { await GemmaEmbedder.shared.unloadNow() }
        }
        #endif
    }

    /// ~295 MB, cached here after the first download.
    static var modelsDir: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        #if os(macOS)
        // Non-sandboxed Mac: ~/Library/Application Support is shared ground — nest
        // under Skrift/. Deliberately ONE dir for dev+prod (read-only model assets,
        // version-keyed inside; download the 295 MB once, both builds use it).
        return appSupport.appendingPathComponent("Skrift/EmbeddingModels", isDirectory: true)
        #else
        return appSupport.appendingPathComponent("EmbeddingModels", isDirectory: true)
        #endif
    }

    /// True once the model files exist on disk — the sweep must NOT trigger a
    /// surprise 295 MB download; the Journal UI owns the download consent flow.
    static var isModelDownloaded: Bool {
        FileManager.default.fileExists(
            atPath: modelsDir.appendingPathComponent("embeddinggemma-300m").path)
    }

    /// The in-flight cold load, shared by every concurrent `prepare()`. The actor
    /// SUSPENDS at the load's `await`, so without this a second caller re-enters,
    /// still sees `model == nil`, and loads the 295 MB model AGAIN — device-proven
    /// 2026-07-10: the first-keystroke warmup racing the query path produced two
    /// concurrent loads (43.9s + 50.3s).
    private var loadTask: Task<EmbeddingGemma, Error>?

    func prepare() async throws {
        if model == nil {
            if loadTask == nil {
                // The transcription wait lives INSIDE the single-flight task: out here the loop
                // suspends the actor before `loadTask` is set, so a second caller re-enters, still
                // sees nil, and starts a second 295 MB load.
                loadTask = Task { [loader] in
                    // Yield the Neural Engine to an active transcription: this cold load is ~2 min and
                    // would otherwise STARVE the ASR (device-found 2026-07-15 — a 13s clip waited ~2 min).
                    // Capped so a long book transcription can't defer Related notes forever.
                    var waited = 0.0
                    while TranscriptionActivity.isActive, waited < 30 {
                        try? await Task.sleep(for: .milliseconds(400)); waited += 0.4
                    }
                    let t0 = Date()
                    Self.log("embedder: cold load START")
                    let m = try await loader()
                    Self.log(String(format: "embedder: cold load DONE in %.1fs", Date().timeIntervalSince(t0)))
                    return m
                }
            }
            defer { loadTask = nil }   // success: model is set; failure: allow a retry
            model = try await loadTask!.value
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
        guard idleTask == nil else { return }   // ONE sleeper; it re-reads `lastUse` when it wakes
        idleTask = Task { [weak self] in await self?.idleLoop() }
    }

    /// Sleeps until `lastUse + idleUnloadAfter`, re-checking after each wake (a use in the
    /// meantime pushes the deadline out), then unloads. `embed()` calls `prepare()` per chunk,
    /// so a sweep used to leave one 605 s sleeper per chunk.
    private func idleLoop() async {
        while model != nil {
            let remaining = lastUse.addingTimeInterval(idleUnloadAfter).timeIntervalSinceNow
            if remaining <= 0 { break }
            try? await Task.sleep(nanoseconds: UInt64((remaining + 5) * 1_000_000_000))
        }
        unloadIfIdle()
        idleTask = nil
    }

    private func unloadIfIdle() {
        if model != nil, Date().timeIntervalSince(lastUse) >= idleUnloadAfter {
            model = nil
            Self.log("embedder: unloaded after idle")
        }
    }

    /// Backgrounding: give the memory back right away — a suspended app holding
    /// 295 MB is first in line for jetsam.
    func unloadNow() {
        if model != nil {
            model = nil
            Self.log("embedder: unloaded on background")
        }
    }

    enum EmbeddingError: Error { case notLoaded }
}
