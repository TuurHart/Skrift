import Foundation

/// Q424: copy-edit v2 on a Mac row — the `PipelineFile` side of `CopyEditV2.runPass` and its
/// deterministic tail. NOT wired into Process (C2: the app keeps running v1's `BatchRunner`);
/// the copy-edit harness and the DEBUG `-recordcopyeditv2` recorder run it over the corpus.
@MainActor
enum CopyEditV2Mac {
    static func source(of pf: PipelineFile) -> CopyEditV2.Source {
        if pf.sourceType == .capture { return .share }
        if SpeakerTranscript.isConversation(pf.transcript, source: pf.noteSource) { return .conversation }
        return pf.sourceType == .note ? .typed : .spoken
    }

    /// The enhance half of Process on one row whose transcript exists.
    static func process(_ pf: PipelineFile, settings: AppSettings, people: [Person], tagWhitelist: [String],
                        generate: @escaping CopyEditV2.Generate) async throws {
        let src = source(of: pf)
        let body = src == .share ? (pf.transcript ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                                 : (pf.transcript ?? "")
        if src != .share, body.isEmpty { pf.enhanceStatus = .done; return }   // nothing to enhance
        pf.enhanceStatus = .processing
        let snapshot = pf.sanitised ?? pf.enhancedCopyedit ?? pf.transcript
        let p = settings.prompts
        var input = CopyEditV2.PassInput(
            body: body, source: src,
            prompts: .init(copyEdit: p.effectiveCopyEdit, title: p.effectiveTitle, summary: p.effectiveSummary),
            currentTitle: pf.enhancedTitle, summaryMinWords: settings.effectiveSummaryMinWords)
        if src == .share {
            input.fallbackTitle = BatchRunner.captureFallbackTitle(SharedContent.decode(from: pf.audioMetadataJSON),
                                                                   existingTitle: pf.enhancedTitle)
        }
        let pass = try await CopyEditV2.runPass(input, generate: generate) {
            (pf.sanitised ?? pf.enhancedCopyedit ?? pf.transcript) != snapshot
        }
        if pass.discarded { pf.enhanceStatus = .pending; return }   // C38: an edit during the run wins
        if src != .share { pf.enhancedCopyedit = pass.copyedit }
        if !pass.titleSuggested.isEmpty {   // no words → no model title; the row keeps what it had
            pf.titleSuggested = pass.titleSuggested
            pf.enhancedTitle = pass.title
        }
        if src != .share || !body.isEmpty { pf.enhancedSummary = pass.summary }

        let working = pass.working(body: body)
        let isConversation = src == .conversation
        let hasText = !body.isEmpty
        CopyEditV2.runTail(working: working,
                           tagText: isConversation ? (SpeakerTranscript.flattened(working) ?? working) : working,
                           .init(tags: { text in
                                     guard hasText else { return pf.tagSuggestions ?? [] }
                                     let s = TagMatcher.suggest(text: text, whitelist: tagWhitelist)
                                     pf.tagSuggestions = s.matched + s.spoken
                                     return s.matched + s.spoken
                                 },
                                 nameLink: { text in
                                     if hasText { pf.relinkNames(working: text, isConversation: isConversation, people: people) }
                                 },
                                 compile: {
                                     pf.enhanceStatus = .done
                                     pf.compiledText = Compiler.compile(file: pf, author: settings.authorName,
                                                                        knownPeople: people)
                                 }))
    }

    #if DEBUG
    /// The corpus driver's per-row step for v2: v1's transcription only (ASR is not the subject;
    /// a capture never transcribes), then the v2 pass.
    static func corpusStep(generate: @escaping CopyEditV2.Generate) -> CopyEditCorpusRun.RowStep {
        { pf, runner, audioURL, manifest, clipStarts in
            if pf.sourceType != .capture {
                try await runner.run(pf, audioURL: audioURL, imageManifest: manifest, clipStarts: clipStarts,
                                     stopAfterTranscribe: true)
            }
            try await process(pf, settings: runner.settings, people: runner.people,
                              tagWhitelist: runner.tagWhitelist, generate: generate)
        }
    }
    #endif
}
