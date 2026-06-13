import Foundation
import FluidAudio

/// CTC keyword-spot + rescore pass (FluidAudio's custom-vocabulary system —
/// NeMo arXiv:2406.07096, separate CTC encoder) applied AFTER the main Parakeet
/// transcribe, per the FluidAudio CLI batch pattern. Mirrors the phone's
/// `VocabularyBooster`; the word list lives in `AppSettings.customVocabulary`
/// (Settings → Transcription → Custom words), per-device v1 (no phone sync).
///
/// Costs one extra ~97.5 MB HF model (ctc110m), downloaded on first use and
/// loaded lazily ONLY while the custom-words list is non-empty. Boosting must
/// never fail a transcription: every failure path returns nil (unboosted).
///
/// ## Aliases (the 2026-06-13 efficacy fix)
/// A word entry may carry the forms Parakeet mis-hears, in the
/// "Canonical: alias1, alias2" syntax (mirrors FluidAudio's own simple-format):
/// `Skrift: script, scrift`. The aliases widen the string-similarity gate so a
/// distant mis-hearing still surfaces the candidate; the canonical is what gets
/// written. A bare word (no colon) keeps the prior behaviour. See
/// `VocabularyTermParsing`.
actor VocabularyBooster {
    static let shared = VocabularyBooster()

    private var spotter: CtcKeywordSpotter?
    private var vocab: CustomVocabularyContext?
    private var rescorer: VocabularyRescorer?
    private var loadedWords: [String] = []

    struct Boosted {
        let text: String
        let replacementCount: Int
    }

    private var preparing = false

    /// Run the rescore pass. nil = no custom words / model not loaded yet /
    /// no replacements — caller keeps the original transcript.
    ///
    /// NEVER blocks the transcription on the model download: boosts only when the
    /// spotter is already prepared for this word list; otherwise kicks a one-shot
    /// background load and skips. (A blocking `await prepare` jammed the
    /// serialized transcription queue — see the mobile booster's 2026-06-13 fix.)
    func boost(text: String, tokenTimings: [TokenTiming], audioURL: URL,
               words: [String]) async -> Boosted? {
        guard !words.isEmpty, !tokenTimings.isEmpty, !text.isEmpty else { return nil }
        guard let spotter, let vocab, let rescorer, loadedWords == words else {
            VocabLog.log("vocab: not ready (loaded=\(loadedWords), want=\(words)) → bg prepare, unboosted")
            kickPrepare(words: words)
            return nil
        }
        do {
            let samples = try AudioConverter().resampleAudioFile(path: audioURL.path)
            let spot = try await spotter.spotKeywordsWithLogProbs(
                audioSamples: samples, customVocabulary: vocab, minScore: nil)
            guard !spot.logProbs.isEmpty else { VocabLog.log("vocab: spot returned no logProbs"); return nil }

            // DIAGNOSTIC: did the CTC spotter detect each term acoustically? This
            // is the "spotter vs rescorer" split — a term absent here means the
            // spotter never found it (phonetic limit); present-but-not-replaced
            // means the rescorer's CTC-vs-CTC gate declined.
            VocabLog.log("vocab: spot detections=\(spot.detections.map { "\($0.term.text)@\(String(format: "%.2f", $0.startTime))s=\(String(format: "%.1f", $0.score))" })")

            let base = ContextBiasingConstants.rescorerConfig(forVocabSize: vocab.terms.count)
            let cbw = VocabularyTuning.cbw(default: base.cbw)
            let minSim = VocabularyTuning.minSimilarity(default: base.minSimilarity)
            let out = rescorer.ctcTokenRescore(
                transcript: text,
                tokenTimings: tokenTimings,
                logProbs: spot.logProbs,
                frameDuration: spot.frameDuration,
                cbw: cbw,
                marginSeconds: ContextBiasingConstants.defaultMarginSeconds,
                minSimilarity: minSim)
            VocabLog.log("vocab: cbw=\(cbw) minSim=\(minSim) wasModified=\(out.wasModified) replacements=\(out.replacements.map { "\($0.originalWord)→\($0.replacementWord ?? "?")(\($0.shouldReplace)) [\($0.reason)]" })")
            guard out.wasModified else { return nil }

            // TRUST GUARD (2026-06-13): drop the boost when EVERY replacement is a
            // distant acoustic-only guess from FluidAudio's spotter-anchored rescue
            // (which mangles ordinary speech that contains none of the custom
            // words). A replacement is trusted when the original is string-similar
            // to the canonical (Route-1 grade) or hits a user alias. See
            // `VocabularyTrust`. We keep the boost if ANY replacement is trusted —
            // erring toward the user's wanted correction in the rare mixed case.
            let anyTrusted = out.replacements.contains { r in
                guard let canon = r.replacementWord else { return false }
                let aliases = vocab.terms.first { $0.text.caseInsensitiveCompare(canon) == .orderedSame }?.aliases ?? []
                return VocabularyTrust.isTrusted(original: r.originalWord, canonical: canon, aliases: aliases)
            }
            guard anyTrusted else {
                VocabLog.log("vocab: all replacements untrusted (distant spotter-rescue) → dropped, unboosted")
                return nil
            }
            return Boosted(text: out.text,
                           replacementCount: out.replacements.filter(\.shouldReplace).count)
        } catch {
            // Offline / first-download failed / spot error → unboosted transcript.
            VocabLog.log("vocab: error \(error)")
            return nil
        }
    }

    /// Fire-and-forget background model prep — one at a time, off the
    /// transcription path. On success `prepare` sets the engines so the next
    /// `boost` finds them ready.
    private func kickPrepare(words: [String]) {
        guard !preparing else { return }
        preparing = true
        Task { [weak self] in
            try? await self?.prepare(words: words)
            await self?.clearPreparing()
        }
    }
    private func clearPreparing() { preparing = false }

    /// Proactively load the spotter/rescorer for the current custom-word list so
    /// the FIRST transcribe of a run is already boosted (the non-blocking `boost`
    /// otherwise skips the first one while the ~97 MB model loads). Safe to call
    /// repeatedly — `prepare` no-ops when the list is unchanged. Awaitable so the
    /// headless `-runfile -vocab` path can wait for readiness; the app calls it
    /// fire-and-forget at launch when custom words exist.
    func prewarm(words: [String]) async {
        guard !words.isEmpty else { return }
        try? await prepare(words: words)
    }

    /// Lazily (re)build the spotter+rescorer when the word list changed.
    private func prepare(words: [String]) async throws {
        guard words != loadedWords || rescorer == nil else { return }
        let models = try await CtcModels.downloadAndLoad(variant: .ctc110m)
        let dir = CtcModels.defaultCacheDirectory(for: .ctc110m)
        let tokenizer = try await CtcTokenizer.load(from: dir)
        let terms = words.compactMap { entry -> CustomVocabularyTerm? in
            let parsed = VocabularyTermParsing.parse(entry)
            let ids = tokenizer.encode(parsed.canonical)
            guard !ids.isEmpty else { return nil }
            return CustomVocabularyTerm(text: parsed.canonical, weight: nil,
                                        aliases: parsed.aliases.isEmpty ? nil : parsed.aliases,
                                        tokenIds: nil, ctcTokenIds: ids)
        }
        guard !terms.isEmpty else { throw ASRError.notInitialized }
        let v = CustomVocabularyContext(terms: terms)
        let s = CtcKeywordSpotter(models: models, blankId: models.vocabulary.count)
        rescorer = try await VocabularyRescorer.create(
            spotter: s, vocabulary: v, config: .default, ctcModelDirectory: dir)
        spotter = s
        vocab = v
        loadedWords = words
    }
}

/// Synchronous stderr diagnostic for the booster, DEBUG only. The boost runs on
/// the booster actor and a headless `-runfile` exits right after — async
/// `AppLogger` sinks can lose their tail at `exit(0)`, so we write directly.
enum VocabLog {
    static func log(_ message: String) {
        #if DEBUG
        FileHandle.standardError.write(Data(("[vocab] " + message + "\n").utf8))
        #endif
    }
}
