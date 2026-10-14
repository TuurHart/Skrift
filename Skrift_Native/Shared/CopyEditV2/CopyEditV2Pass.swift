import Foundation

extension CopyEditV2 {
    /// What the words are, which decides the verbs (C36).
    enum Source: Sendable, Equatable {
        /// Spoken: copy-edited, a wall is broken (C34). A quote capture's ramble is spoken.
        case spoken
        /// Typed: copy-edited, never re-paragraphed (C34, D7).
        case typed
        /// A share capture (url / text / image / file): title + summary on its annotation, no copy-edit.
        case share
        /// Speaker turns: no copy-edit (the turns are the diarization).
        case conversation
    }

    /// The three prompts, read from the ONE source (`PolishPrompts`, or the synced override
    /// blob the caller resolved) — v2 owns no prompt text of its own (C39).
    struct Prompts: Sendable, Equatable {
        var copyEdit: String, title: String, summary: String
        static let standard = Prompts(copyEdit: PolishPrompts.copyEdit, title: PolishPrompts.title,
                                      summary: PolishPrompts.summary)
    }

    struct PassInput: Sendable {
        /// The RAW body: the phone's transcript or the share annotation (never `sanitised`).
        var body: String
        var source: Source
        var prompts: Prompts = .standard
        /// A title the phone or the user already set wins over the model's (it stays the suggestion).
        var currentTitle: String? = nil
        /// An unannotated share capture's derived title (URL title → first words → file → "Capture").
        var fallbackTitle: String? = nil
        /// Manual Redo: the summary runs below the word threshold (C36).
        var forceSummary = false
        var summaryMinWords = SummaryRule.defaultMinWords
    }

    /// One pass's output. Every pass writes exactly one `Enhancement` from it (C37).
    struct Pass: Sendable, Equatable {
        /// The shipped body before name-linking; "" when this source gets no copy-edit body.
        var copyedit = ""
        var titleSuggested = ""
        var title = ""
        var summary = ""
        /// The copy-edit's own report (fallback reason, paragraph ledger); nil = not copy-edited.
        var edit: Result? = nil
        /// The body changed while the model ran: the run is discarded, nothing is written (C38).
        var discarded = false

        /// The text the deterministic tail works on.
        func working(body: String) -> String { copyedit.isEmpty ? body : copyedit }
    }

    /// Process one note (C36): the verbs its source gets, one model call each, title and
    /// summary over the same prose the copy-edit reads (C29, C178). `bodyChanged` is asked after
    /// every model call; true discards the run (C38).
    @MainActor
    static func runPass(_ input: PassInput, generate: Generate,
                        bodyChanged: () -> Bool = { false }) async throws -> Pass {
        var pass = Pass()
        let body = input.body
        func adopt(_ suggested: String) {
            pass.titleSuggested = suggested
            let current = (input.currentTitle ?? "").trimmingCharacters(in: .whitespaces)
            pass.title = current.isEmpty ? suggested : current
        }
        let prose = Self.prose(input.source == .share ? body.trimmingCharacters(in: .whitespacesAndNewlines) : body)
        guard !prose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            // No words (blank, or pictures only): no model call — a model given nothing invents
            // a note (C177). A share capture still gets its derived title.
            if input.source == .share { adopt(input.fallbackTitle ?? "Capture") }
            else { pass.title = input.currentTitle ?? "" }
            return pass
        }
        switch input.source {
        case .spoken, .typed:
            let edit = try await copyEdit(body, spoken: input.source == .spoken,
                                          prompt: input.prompts.copyEdit, generate: generate)
            pass.edit = edit
            pass.copyedit = edit.text
        case .conversation:
            pass.copyedit = body
        case .share:
            break
        }
        if bodyChanged() { pass.discarded = true; return pass }
        adopt(try await generate(input.prompts.title, prose, 64).trimmingCharacters(in: .whitespacesAndNewlines))
        // Summary only at ≥ 75 words unless forced; a share capture's annotation always gets one.
        if input.source == .share || input.forceSummary
            || SummaryRule.meetsThreshold(prose, minWords: input.summaryMinWords) {
            pass.summary = try await generate(input.prompts.summary, prose, 256)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if bodyChanged() { pass.discarded = true }
        return pass
    }

    // MARK: - one MemoEnhancement per pass (C37)

    /// The `MemoEnhancement` a pass writes — always one, always stamped `processedAt`, even when
    /// the model had nothing to say. The copy-edit carries raw names; the Mac links them.
    struct Enhancement: Sendable, Equatable {
        var copyedit: String, title: String, summary: String
        var enhancedByDeviceID: String
        var enhancedAt: Date
        var processedAt: Date
        /// `isProcessed` = stamped, or all three parts present.
        var isProcessed: Bool {
            MemoEnhancement.isProcessed(processedAt: processedAt, copyedit: copyedit, title: title, summary: summary)
        }
    }

    static func enhancement(of pass: Pass, deviceID: String, now: Date) -> Enhancement? {
        guard !pass.discarded else { return nil }
        return Enhancement(copyedit: pass.copyedit, title: pass.title, summary: pass.summary,
                           enhancedByDeviceID: deviceID, enhancedAt: now, processedAt: now)
    }

    // MARK: - when a note is polished (C38)

    enum Trigger: Sendable { case process, phoneEdit }
    enum Work: Sendable, Equatable { case polish, relinkAndCompile, nothing }

    /// Process polishes only a note that is not done; a phone edit to a polished note re-links
    /// and recompiles; nothing ever re-polishes a polished note on its own.
    static func work(for trigger: Trigger, polished: Bool) -> Work {
        switch (trigger, polished) {
        case (.process, false): return .polish
        case (.phoneEdit, true): return .relinkAndCompile
        default: return .nothing
        }
    }

    // MARK: - the deterministic tail (C178)

    /// After the model: tag candidates → name-link (the last step on the text) → compile.
    /// Tags are suggestions the user accepts; for a conversation they read the spoken words only.
    struct Tail {
        var tags: (String) -> [String]
        var nameLink: (String) -> Void
        var compile: () -> Void
    }

    @discardableResult
    static func runTail(working: String, tagText: String, _ tail: Tail) -> [String] {
        let tags = tail.tags(tagText)
        tail.nameLink(working)
        tail.compile()
        return tags
    }
}
