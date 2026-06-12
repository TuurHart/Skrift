import Foundation
import FluidAudio

// MARK: - Custom words store

/// The user's custom vocabulary ("Skrift", names of products, jargon …) —
/// words Parakeet routinely mis-hears. Settings → Transcription → Custom words.
/// Per-device v1 (no phone↔Mac sync; the Mac keeps its own list).
enum CustomVocabularyStore {
    static let defaultsKey = "customVocabularyWords"

    static func words(defaults: UserDefaults = .standard) -> [String] {
        (defaults.array(forKey: defaultsKey) as? [String]) ?? []
    }

    static func save(_ words: [String], defaults: UserDefaults = .standard) {
        // Trimmed, de-duplicated (case-insensitive), order-preserving.
        var seen = Set<String>()
        let clean = words
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
        defaults.set(clean, forKey: defaultsKey)
    }
}

// MARK: - Booster

/// CTC keyword-spot + rescore pass (FluidAudio's custom-vocabulary system —
/// NeMo arXiv:2406.07096, separate CTC encoder) applied AFTER the main Parakeet
/// transcribe, per the FluidAudio CLI batch pattern: spot the custom terms in
/// the same samples, then token-rescore the transcript and take the rescored
/// text when modified.
///
/// Costs one extra ~97.5 MB HF model (ctc110m), downloaded on first use and
/// loaded lazily ONLY while the custom-words list is non-empty. Boosting must
/// never fail a transcription: every failure path returns nil (unboosted).
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

    /// Run the rescore pass. nil = no custom words / model unavailable /
    /// no replacements — caller keeps the original transcript.
    func boost(text: String, tokenTimings: [TokenTiming], audioURL: URL) async -> Boosted? {
        let words = CustomVocabularyStore.words()
        guard !words.isEmpty, !tokenTimings.isEmpty, !text.isEmpty else { return nil }
        do {
            try await prepare(words: words)
            guard let spotter, let vocab, let rescorer else { return nil }

            let samples = try AudioConverter().resampleAudioFile(path: audioURL.path)
            let spot = try await spotter.spotKeywordsWithLogProbs(
                audioSamples: samples, customVocabulary: vocab, minScore: nil)
            guard !spot.logProbs.isEmpty else { return nil }

            let cfg = ContextBiasingConstants.rescorerConfig(forVocabSize: vocab.terms.count)
            let out = rescorer.ctcTokenRescore(
                transcript: text,
                tokenTimings: tokenTimings,
                logProbs: spot.logProbs,
                frameDuration: spot.frameDuration,
                cbw: cfg.cbw,
                marginSeconds: ContextBiasingConstants.defaultMarginSeconds,
                minSimilarity: cfg.minSimilarity)
            guard out.wasModified else { return nil }
            return Boosted(text: out.text,
                           replacementCount: out.replacements.filter(\.shouldReplace).count)
        } catch {
            // Offline / first-download failed / spot error → unboosted transcript.
            return nil
        }
    }

    /// Lazily (re)build the spotter+rescorer when the word list changed.
    private func prepare(words: [String]) async throws {
        guard words != loadedWords || rescorer == nil else { return }
        let models = try await CtcModels.downloadAndLoad(variant: .ctc110m)
        let dir = CtcModels.defaultCacheDirectory(for: .ctc110m)
        let tokenizer = try await CtcTokenizer.load(from: dir)
        let terms = words.compactMap { w -> CustomVocabularyTerm? in
            let ids = tokenizer.encode(w)
            guard !ids.isEmpty else { return nil }
            return CustomVocabularyTerm(text: w, weight: nil, aliases: nil,
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

    // MARK: - Word-timings alignment (pure)

    /// The rescorer replaces whole words in the TEXT; the word-timings sidecar
    /// (karaoke/tap-to-seek) must show the corrected words too. When the
    /// rescored text still has the same word count, swap strings positionally
    /// (times unchanged). nil = counts diverged — caller keeps the original
    /// words (rare; only the replaced span would read stale).
    nonisolated static func alignWords(original: [String], rescoredText: String) -> [String]? {
        let rescored = rescoredText
            .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
            .map(String.init)
        guard rescored.count == original.count else { return nil }
        return rescored
    }
}
