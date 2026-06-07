import Foundation

/// The unattended auto-run for one file: transcribe → copy-edit / title / summary
/// (all on the RAW transcript) → deterministic tag candidates → name-link (on the
/// copy-edit, the LAST deterministic step) → compile the review draft → Ready for
/// Review. Engines are injected via `Transcribing`/`Enhancing` so this orchestration
/// host-tests with stubs. Mirrors `backend/services/batch_manager.py` (one
/// model-grouped run; no mid-flight gates). The caller persists the PipelineFile +
/// writes the compiled.md / word-timing sidecars.
struct BatchRunner {
    var transcriber: Transcribing
    var enhancer: Enhancing
    var settings: AppSettings
    var people: [Person]
    var tagWhitelist: [String]

    /// Run the pipeline on one file, mutating it in place. `audioURL` is nil for
    /// notes/captures whose transcript is already present.
    func run(_ pf: PipelineFile, audioURL: URL?, imageManifest: [ImageManifestEntry] = []) async throws {
        // 1. Transcribe — skipped when already done (trusted phone transcript / note).
        if pf.transcribeStatus != .done {
            pf.transcribeStatus = .processing
            if let audioURL {
                let result = try await transcriber.transcribe(audioURL: audioURL, imageManifest: imageManifest)
                pf.transcript = result.text
            }
            pf.transcribeStatus = .done
        }

        let transcript = pf.transcript ?? ""
        guard !transcript.isEmpty else {
            pf.enhanceStatus = .done   // nothing to enhance (e.g. empty/cancelled)
            return
        }

        // 2. Enhance — every LLM step runs on the RAW transcript.
        pf.enhanceStatus = .processing
        let prompts = settings.prompts
        let repo = settings.enhancementModelRepo

        let copyedit = try await enhancer.copyEdit(transcript, prompts: prompts, modelRepo: repo)
        pf.enhancedCopyedit = copyedit
        let suggestedTitle = try await enhancer.title(transcript, prompts: prompts, modelRepo: repo)
        pf.titleSuggested = suggestedTitle
        // Keep a title the user/phone already set; only fill from the LLM if empty.
        if (pf.enhancedTitle ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
            pf.enhancedTitle = suggestedTitle
        }
        pf.enhancedSummary = try await enhancer.summary(transcript, prompts: prompts, modelRepo: repo)

        // Deterministic steps work on the cleaned copy-edit (fall back to transcript).
        let working = copyedit.isEmpty ? transcript : copyedit

        // 3. Deterministic tag candidates (review-time selection).
        let suggestions = TagMatcher.suggest(text: working, whitelist: tagWhitelist)
        pf.tagSuggestions = suggestions.matched + suggestions.spoken

        // 4. Name-link — last deterministic step, non-blocking.
        let san = Sanitiser.process(text: working, people: people)
        pf.sanitised = san.sanitised
        pf.ambiguousNames = san.ambiguous.isEmpty ? nil : san.ambiguous

        pf.enhanceStatus = .done

        // 5. Compile the review draft (body precedence: sanitised → copy-edit → transcript).
        pf.compiledText = Compiler.compile(file: pf, author: settings.authorName)
    }
}
