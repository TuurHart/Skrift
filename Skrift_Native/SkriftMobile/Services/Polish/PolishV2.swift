import Foundation

/// Q426 (C2, C28): the iPad's polish through copy-edit v2 — the same `CopyEditV2.runPass` and
/// `CopyEditV2.turn` the Mac runs, so a note reads alike whichever device polished it. Pure
/// (the model is a closure), so the phone tests drive it without MLX.
enum PolishV2 {
    /// The three prompts from the iPad's ONE source (`PolishPromptsStore`: the synced blob or
    /// the shared default, C39).
    static func prompts(defaults: UserDefaults = .standard) -> CopyEditV2.Prompts {
        CopyEditV2.Prompts(copyEdit: PolishPromptsStore.copyEdit(defaults: defaults),
                           title: PolishPromptsStore.title(defaults: defaults),
                           summary: PolishPromptsStore.summary(defaults: defaults))
    }

    /// One full pass → the three pieces. `onStep` moves at the real call boundaries
    /// (copy-edit is by far the longest call, so the bar moves in proportion to the work).
    static func polish(transcript: String, source: CopyEditV2.Source, prompts: CopyEditV2.Prompts,
                       generate: @escaping CopyEditV2.Generate,
                       onStep: @escaping @Sendable (PolishStep, Double) -> Void) async throws -> PolishResult {
        let stepped: CopyEditV2.Generate = { prompt, text, cap in
            switch prompt {
            case prompts.title: onStep(.title, 0.55)
            case prompts.summary: onStep(.summary, 0.75)
            default: onStep(.copyEdit, 0.10)
            }
            return try await generate(prompt, text, cap)
        }
        let pass = try await CopyEditV2.runPass(
            CopyEditV2.PassInput(body: transcript, source: source, prompts: prompts,
                                 summaryMinWords: SummaryRule.defaultMinWords),
            generate: stepped)
        onStep(.summary, 1.0)
        // A share capture gets no copy-edit body (C36); every other source ships the pass's body.
        return PolishResult(copyedit: pass.copyedit, title: pass.titleSuggested, summary: pass.summary)
    }

    /// Re-run ONE part (the Mac's Redo). A conversation's turns and a share capture are never
    /// copy-edited (C36); a redone summary ignores the word threshold (a manual redo overrides).
    static func redo(_ part: NoteRedoItem, transcript: String, source: CopyEditV2.Source,
                     prompts: CopyEditV2.Prompts, generate: @escaping CopyEditV2.Generate) async throws -> String {
        switch part {
        case .copyEdit:
            guard source == .spoken || source == .typed else { return transcript }
            return try await CopyEditV2.copyEdit(transcript, spoken: source == .spoken,
                                                 prompt: prompts.copyEdit, generate: generate).text
        case .title:
            return try await CopyEditV2.turn(prompt: prompts.title, body: transcript, maxTokens: 64, generate: generate)
        case .summary:
            return try await CopyEditV2.turn(prompt: prompts.summary, body: transcript, maxTokens: 256, generate: generate)
        }
    }
}
