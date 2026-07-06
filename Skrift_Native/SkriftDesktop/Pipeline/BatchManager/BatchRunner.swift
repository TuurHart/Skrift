import Foundation
import os

/// The unattended auto-run for one file: transcribe → copy-edit / title / summary
/// (all on the RAW transcript) → deterministic tag candidates → name-link (on the
/// copy-edit, the LAST deterministic step) → compile the review draft → Ready for
/// Review. Engines are injected via `Transcribing`/`Enhancing` so this orchestration
/// host-tests with stubs. Mirrors `backend/services/batch_manager.py` (one
/// model-grouped run; no mid-flight gates). The caller persists the PipelineFile +
/// writes the compiled.md / word-timing sidecars.
struct BatchRunner {
    private static let log = Logger(subsystem: "com.skrift.desktop", category: "batch")

    var transcriber: Transcribing
    var enhancer: Enhancing
    var settings: AppSettings
    var people: [Person]
    var tagWhitelist: [String]
    /// Conversation-mode diarizer (Sortformer + voiceprint match). nil in tests / when
    /// engines are stubbed; the real `DiarizationService` is injected in the app + runfile.
    var diarizer: Diarizing? = nil

    /// Run the pipeline on one file, mutating it in place. `audioURL` is nil for
    /// notes/captures whose transcript is already present.
    func run(_ pf: PipelineFile, audioURL: URL?, imageManifest: [ImageManifestEntry] = []) async throws {
        // Captures (C3) never transcribe or diarize — their annotation is already text.
        // Enhancement-lite runs on the annotation: title + tags + summary, NO copy-edit
        // (the annotation is intentional prose, not speech artifacts). Sanitise runs as normal.
        if pf.sourceType == .capture {
            try await runCapture(pf)
            return
        }

        // 1. Transcribe — skipped when already done (trusted phone transcript / note).
        // `didTranscribe` = the Mac ran its OWN ASR this run (so the word-timings are the
        // Mac's). A trusted phone memo skips this → didTranscribe stays false even though
        // pf.wordTimings may be present (the phone now uploads them for karaoke), which is
        // exactly what gates the re-diarize below off a phone transcript.
        var didTranscribe = false
        if pf.transcribeStatus != .done {
            pf.transcribeStatus = .processing
            if let audioURL {
                let result = try await transcriber.transcribe(audioURL: audioURL, imageManifest: imageManifest)
                pf.transcript = result.text
                pf.wordTimings = result.wordTimings   // persist for karaoke (was discarded)
                didTranscribe = true
            }
            pf.transcribeStatus = .done
        }

        // 1b. Conversation mode: when the Mac transcribed this itself (so we have word
        // timings) and it isn't already speaker-attributed, diarize + re-emit as
        // `**[[Person]]:**` (matched) / `**Speaker N:**` turns. A monologue (<2 speakers)
        // is left as plain prose. The Sanitiser then links any remaining plain aliases;
        // matched speakers already carry the canonical `[[ ]]` so they're skipped.
        if let diarizer, settings.conversationModeEnabled, let audioURL, didTranscribe,
           !(pf.transcript ?? "").isEmpty, !pf.wordTimings.isEmpty,
           !SpeakerTranscript.isAttributed(pf.transcript),
           let out = try? await diarizer.diarize(audioURL: audioURL),
           Set(out.segments.map(\.speaker)).count >= 2 {
            // Emit PLAIN speaker labels (matched person's name or "Speaker N"), like the
            // phone — `processConversation` (below) owns all `[[ ]]` linking + the
            // first-mention-canonical/rest-short header policy, so both the phone-synced
            // and Mac-diarized paths render identically.
            pf.transcript = SpeakerFusion.attributedTranscript(words: pf.wordTimings, segments: out.segments) { slot in
                out.slotNames[slot] ?? "Speaker \(slot + 1)"
            }
            // Retain the diarization so a speaker's voice can be enrolled later from the
            // review screen (slice their audio by these segments → embedSpeaker) without
            // re-diarizing. Persist BOTH on the PipelineFile (survives SwiftData) AND as a
            // `diar_<id>.json` sidecar next to the audio (byte-mirrors the phone, keeps the
            // segments with the recording for portability). Was discarded before.
            pf.diarizationSegments = out.segments
            if !pf.path.isEmpty {
                DiarizationSidecar().write(DiarizationData(out),
                                           in: DiarizationSidecar.workingFolder(for: pf), id: pf.id)
            }
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

        // A speaker-attributed (conversation) transcript SKIPS copy-edit: the LLM strips
        // the `**Name:**` turn prefixes (verified on the real fixture), destroying the
        // structure diarization just produced. Conversations stay verbatim — consistent
        // with the phone, which never copy-edits — so the turns survive into the export.
        // Title/summary still run (they read fine on the turns), and name-linking below
        // still links any plain names spoken inside the turns.
        // ONLY an audio memo can be a diarized conversation — an Apple Note that happens
        // to contain ≥2 line-start bold headings (**Introduction:** / **Conclusion:**)
        // must NOT be routed to the turn linker (it would drop the note's preamble and
        // skip copy-edit). Notes/captures always take the monologue path.
        let isConversation = pf.sourceType == .audio && SpeakerTranscript.isAttributed(transcript)
        var copyedit = isConversation
            ? transcript
            : try await enhancer.copyEdit(transcript, prompts: prompts, modelRepo: repo)
        // Audiobook quote protection — the outer byte-assert (backlog spec 8): an
        // audiobook capture opens with a "> " quote block (contract C1) that must
        // survive copy-edit byte-identical. The enhancer protects it internally; if
        // it still comes back mutated (ANY mismatch), fall back to the fully-unedited
        // transcript — skip-all, the conversation-mode precedent above.
        if !QuoteProtection.leadingQuoteIntact(original: transcript, edited: copyedit) {
            Self.log.warning("file \(pf.id, privacy: .public): quote block mutated by copy-edit — keeping the unedited transcript")
            copyedit = transcript
        }
        pf.enhancedCopyedit = copyedit
        let suggestedTitle = try await enhancer.title(transcript, prompts: prompts, modelRepo: repo)
        pf.titleSuggested = suggestedTitle
        // Keep a title the user/phone already set; only fill from the LLM if empty.
        if (pf.enhancedTitle ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
            pf.enhancedTitle = suggestedTitle
        }
        // Skip the summary on SHORT notes (user 2026-06-15) — a brief memo doesn't need
        // one. A manual "Redo summary" still generates it regardless (deliberate override).
        let bodyWordCount = transcript.split(whereSeparator: \.isWhitespace).count
        pf.enhancedSummary = bodyWordCount >= settings.effectiveSummaryMinWords
            ? try await enhancer.summary(transcript, prompts: prompts, modelRepo: repo)
            : ""

        // Deterministic steps work on the cleaned copy-edit (fall back to transcript).
        let working = copyedit.isEmpty ? transcript : copyedit

        // 3. Deterministic tag candidates (review-time selection). For a conversation,
        // tag over the SPOKEN bodies only — strip the `**Name:**` turn headers first so a
        // speaker's name (repeated on every turn) can't be counted as a topic word and
        // push a vault tag past the occurrence gate (over-eager conversation tagging).
        let tagText = isConversation ? (SpeakerTranscript.flattened(working) ?? working) : working
        let suggestions = TagMatcher.suggest(text: tagText, whitelist: tagWhitelist)
        pf.tagSuggestions = suggestions.matched + suggestions.spoken

        // 4. Name-link — last deterministic step, non-blocking. The note's persisted
        // "unlink all mentions" choices keep those people plain on a re-run. A
        // conversation uses the turn-aware linker (merge same-speaker turns, first
        // header → [[Canonical]] / rest short, inline mentions → [[Canonical|spoken]]);
        // a monologue uses the ordinary first-mention linker.
        // OPT-OUT (NAMING_MODEL.md): every known person is auto-linked by default (first
        // mention, risk-tiered — FP-prone/ambiguous names surface as dotted suggestions);
        // the user prunes stray subjects via `unlinkedNames`.
        let san = isConversation
            ? Sanitiser.processConversation(text: working, people: people, neverLink: Set(pf.unlinkedNames), namePicks: pf.namePicks)
            : Sanitiser.process(text: working, people: people, neverLink: Set(pf.unlinkedNames), namePicks: pf.namePicks)
        pf.sanitised = san.sanitised
        pf.ambiguousNames = san.ambiguous.isEmpty ? nil : san.ambiguous

        pf.enhanceStatus = .done

        // 5. Compile the review draft (body precedence: sanitised → copy-edit → transcript).
        pf.compiledText = Compiler.compile(file: pf, author: settings.authorName, knownPeople: people)
    }

    // MARK: Capture pipeline (C3 enhancement-lite)

    /// Enhancement-lite for captures: title + summary + tags on the annotation; NO
    /// copy-edit (the annotation is written text, not speech); sanitise (name-link) runs.
    /// Empty annotation: skip all LLM steps, fall back to a title from sharedContent
    /// (urlTitle → first words of text → image filename — all from the metadata blob).
    private func runCapture(_ pf: PipelineFile) async throws {
        // transcribeStatus is already .done from UploadService; never run ASR here.
        let annotation = (pf.transcript ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let sc = SharedContent.decode(from: pf.audioMetadataJSON)
        pf.enhanceStatus = .processing
        let prompts = settings.prompts
        let repo = settings.enhancementModelRepo

        if annotation.isEmpty {
            // No annotation → skip all LLM steps; derive a title from sharedContent.
            pf.enhancedTitle = Self.captureFallbackTitle(sc, existingTitle: pf.enhancedTitle)
            pf.titleSuggested = pf.enhancedTitle
        } else {
            // Run title + summary on the annotation text. NO copy-edit — the annotation
            // is intentional prose (skip the "remove fillers" pass that only makes sense
            // for spontaneous speech).
            let suggestedTitle = try await enhancer.title(annotation, prompts: prompts, modelRepo: repo)
            pf.titleSuggested = suggestedTitle
            if (pf.enhancedTitle ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
                pf.enhancedTitle = suggestedTitle
            }
            pf.enhancedSummary = try await enhancer.summary(annotation, prompts: prompts, modelRepo: repo)
        }

        // Deterministic tags + name-link run on the annotation directly (no copy-edit layer).
        if !annotation.isEmpty {
            let suggestions = TagMatcher.suggest(text: annotation, whitelist: tagWhitelist)
            pf.tagSuggestions = suggestions.matched + suggestions.spoken
            // Opt-out naming applies to captures too — known people auto-link by default.
            let san = Sanitiser.process(text: annotation, people: people, neverLink: Set(pf.unlinkedNames), namePicks: pf.namePicks)
            pf.sanitised = san.sanitised
            pf.ambiguousNames = san.ambiguous.isEmpty ? nil : san.ambiguous
        }

        pf.enhanceStatus = .done
        pf.compiledText = Compiler.compile(file: pf, author: settings.authorName, knownPeople: people)
    }

    /// Title fallback chain for an empty-annotation capture:
    /// urlTitle → first 8 words of text snippet → image filename → "Capture".
    /// Only used when the user typed no annotation in the share sheet.
    static func captureFallbackTitle(_ sc: SharedContent?, existingTitle: String?) -> String {
        // Honor a title the phone pre-set (unlikely for captures, but consistent).
        if let t = existingTitle?.trimmingCharacters(in: .whitespaces), !t.isEmpty { return t }
        if let title = sc?.urlTitle?.trimmingCharacters(in: .whitespaces), !title.isEmpty { return title }
        if let text = sc?.text?.trimmingCharacters(in: .whitespaces), !text.isEmpty {
            let words = text.split(separator: " ").prefix(8).joined(separator: " ")
            return words.isEmpty ? text : words + (text.split(separator: " ").count > 8 ? "…" : "")
        }
        if let fileName = sc?.fileName?.trimmingCharacters(in: .whitespaces), !fileName.isEmpty { return fileName }
        return "Capture"
    }
}
