import Foundation

/// THE polish contract both polishers share (iPad wave 1, 2026-07-22). The Mac's
/// batch enhancement and the iPad's on-demand Polish run the SAME model with the
/// SAME prompts, so a note reads identically no matter which device polished it —
/// single-sourced here for the same reason the Palette is (twin copies drift).
///
/// The desktop's `AppSettings.Prompts` defaults forward to these (user-tuned
/// prompt overrides in the Mac's settings.json still win there); the iPad engine
/// reads them directly (no prompt UI on the pad — the Mac is the tuning bench).
enum PolishPrompts {
    /// The model both polishers load. mlx-community repo id, resolved by
    /// mlx-swift-lm's HF downloader on first use.
    static let defaultModelRepo = "mlx-community/gemma-4-e4b-it-8bit"

    /// **PIN THE MODEL LIKE ANY OTHER DEPENDENCY** (2026-08-12). `ModelConfiguration`
    /// defaults `revision:` to `"main"`, so before this every device permanently
    /// inherited whatever `main` was on the day IT downloaded — and that bit us:
    /// mlx-community re-uploaded this repo with the redundant K/V tensors of the 18
    /// KV-shared layers removed, so the Mac (cached 2026-06-07, revision `d8a1725b`,
    /// 42/42 layers carrying `k_proj`) kept working while the iPad (2026-07-23,
    /// revision `4255b21b`, 24/42) could not load at all. Same repo id, same app,
    /// two different models.
    ///
    /// Pinned to the CURRENT upload — the smaller one — because the two are the same
    /// model: identical `config.json`, both declaring `num_kv_shared_layers: 18`. The
    /// 126 tensors it drops (`k_proj`/`v_proj`/`k_norm` × 18 shared layers, ~84 MB)
    /// were never read by those layers; they reuse an earlier layer's K/V by design.
    /// No quality difference, less to download.
    ///
    /// ⚠️ Requires mlx-swift-lm ≥ `e6e3de75` (2026-07-21), where `Gemma4Text`'s
    /// `kProj`/`vProj` became OPTIONAL for KV-shared layers. The previous pin
    /// (`a47894a1`, two days earlier) declared them required and threw
    /// *"Key language_model.model.layers.24.self_attn.k_proj.weight not found"*.
    /// That library also `sanitize`s the redundant tensors out of the OLD upload, so
    /// it loads either revision — change this pin freely, but not the library floor.
    static let defaultModelRevision = "4255b21bd9a9d3fc807ef7abd80373f5e3a52a73"

    /// The revision to request for `repo`. The pin belongs to `defaultModelRepo` and to
    /// nothing else — the Mac's model is a user-editable Settings field, so asking a
    /// DIFFERENT repo for this exact sha would ask for a commit that doesn't exist there.
    /// Anything off the default tracks `main`, which is the right answer for a repo we
    /// have not vetted.
    static func revision(for repo: String) -> String {
        repo == defaultModelRepo ? defaultModelRevision : "main"
    }

    // MARK: - Copy-edit token budget (restored 2026-08-18)

    /// Output-token ceiling for ONE copy-edit, sized from its input. The old Python
    /// backend sized this per memo (`_effective_max_tokens`: input × 1.2, floor 256);
    /// the native ports flattened it to a fixed 1024, and a long note generated
    /// straight into the wall — the output came back cut mid-text, the memo-link
    /// escrow then (rightly) refused the loss and silently shipped the RAW body, and
    /// copy-edit read as "does nothing" (Tuur, 2026-08-18: a massive note, no
    /// paragraphs, redo no different — deterministic at temperature 0, so every retry
    /// failed identically).
    ///
    /// Sizing: ~4 chars/token estimate (the Python fallback), ×1.5 headroom (a
    /// copy-edit only ever deletes, but token boundaries shift), floor 1024 (short
    /// notes lose nothing — generation stops at end-of-text on its own; the cap is a
    /// ceiling, not a target), hard ceiling 8192 (~6000 words out — bounds a runaway
    /// generation and the KV cache on the iPad).
    static func copyEditTokenBudget(forInput text: String) -> Int {
        min(8192, max(1024, (estimatedTokens(text) * 3) / 2))
    }

    /// ~4 chars/token — the old backend's tokenizer-free fallback. Both engines use
    /// this for budget sizing only; nothing user-visible reads it.
    static func estimatedTokens(_ text: String) -> Int {
        max(1, text.count / 4)
    }

    /// THE paragraph cure (2026-08-19). Gemma at temperature 0 will not add
    /// paragraph breaks to long Dutch/mixed text — proven on Tuur's own note and
    /// fx5, and the prompt-reword A/B refuted wording as the cause — so the break
    /// rule cannot live in the model. If a copy-edit comes back as a wall (fewer
    /// than 2 newlines on a long text), split it deterministically: sentence
    /// boundaries, grouped ~4 sentences or ~600 chars per paragraph. Applied to
    /// the model's OUTPUT only, before marker reinsert; already-paragraphed text
    /// passes through untouched.
    static func ensureParagraphs(_ text: String) -> String {
        guard text.count > 600, text.filter({ $0 == "\n" }).count < 2 else { return text }
        var sentences: [String] = []
        var current = ""
        var i = text.startIndex
        while i < text.endIndex {
            let ch = text[i]
            current.append(ch)
            if ".!?".contains(ch) {
                let next = text.index(after: i)
                if next == text.endIndex || text[next] == " " {
                    sentences.append(current.trimmingCharacters(in: .whitespaces))
                    current = ""
                    if next < text.endIndex { i = next }   // swallow the space
                }
            }
            i = text.index(after: i)
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty {
            sentences.append(current.trimmingCharacters(in: .whitespaces))
        }
        guard sentences.count > 4 else { return text }
        var paragraphs: [String] = []
        var buf: [String] = []
        var bufChars = 0
        for s in sentences {
            buf.append(s); bufChars += s.count
            if buf.count >= 4 || bufChars >= 600 {
                paragraphs.append(buf.joined(separator: " ")); buf = []; bufChars = 0
            }
        }
        if !buf.isEmpty { paragraphs.append(buf.joined(separator: " ")) }
        return paragraphs.joined(separator: "\n\n")
    }

    /// Did the model EAT the note? A copy-edit deletes fillers and collapses true
    /// rephrasings — a third, at the outside. An output below this fraction of the
    /// input's words lost real content (the fx5 class, 2026-08-19: a repetitive
    /// Dutch wall came back 7% of its size; Tuur's own note was once shrunk to
    /// 53%). Callers keep the unedited body — a raw note is honest, a bitten one
    /// is silent data loss.
    static func lostTooMuch(input: String, output: String) -> Bool {
        let inWords = input.split(whereSeparator: \.isWhitespace).count
        let outWords = output.split(whereSeparator: \.isWhitespace).count
        guard inWords > 40 else { return false }   // tiny notes legitimately compress hard
        return outWords < (inWords * 55) / 100
    }

    /// Did a generation most likely stop at the cap rather than at end-of-text?
    /// Estimate-based (no token count comes back from the session): output within ~5%
    /// of the cap. Callers fall back to the UNEDITED body — a raw note is honest, a
    /// half note is silent data loss ("better no info than bad info", 2026-07-12).
    static func looksTruncated(output: String, cap: Int) -> Bool {
        estimatedTokens(output) >= (cap * 95) / 100
    }

    static let copyEdit = """
    Clean up this transcript. The author may switch between English and Dutch mid-sentence — this is intentional, keep it exactly as-is.

    Do:
    - Remove filler words (um, uh, like, you know, so basically, I mean, yeah so).
    - Fix spelling and grammar.
    - Add punctuation and paragraph breaks at natural pauses.
    - When the speaker immediately rephrases the same thought (e.g. saying a sentence then saying it again slightly differently), collapse into the final version.
    - Remove false starts and repeated words from thinking out loud.

    Do not:
    - Rephrase, rewrite, or restructure sentences.
    - Translate anything between languages.
    - Add formality — it should still sound like the person speaking.
    - Add any preamble, heading, or explanation.

    Output only the cleaned text.
    """

    static let summary = """
    Summarize this in 1–3 sentences (30–60 words) as personal notes — the kind of thing you'd jot in a journal, not a report.

    - Use implied first person via present participles: "reflecting on…", "trying to figure out…", "collaborating with…". Avoid "The speaker", "They", "He/She".
    - Drop articles where natural ("importance of X" not "the importance of X").
    - Capture the main point and any decision or action item. If multiple topics, mention each briefly.
    - Use proper spelling and capitalization. Keep names capitalized.
    - IMPORTANT: Write the summary in the SAME language as the input text — if the text is in English, the summary MUST be in English.

    Output only the summary.
    """

    static let title = """
    Generate a short, descriptive title for this text (5–15 words). If the speaker explicitly names the topic, use their words. Match the primary language of the text. Return ONLY the title, nothing else.
    """

    // MARK: - The blank rule (Q157, C28)

    /// ONE rule for every device: a prompt that is blank (empty or whitespace only) is
    /// the shared default. The iPad's `PolishPromptsStore` and the Mac's polisher +
    /// sync both route through this, so a blanked prompt can never polish with an
    /// empty prompt on one device and the default on the other.
    static func effective(_ text: String, fallback: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    /// What a store persists for `text`: nil (store nothing, the default rules) when it
    /// is blank or byte-identical to `fallback`, else the trimmed text.
    static func storable(_ text: String, fallback: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed.isEmpty || trimmed == fallback) ? nil : trimmed
    }
}

/// The three prompt knobs, in the ONE order both apps list them (Q187, row setexp-47:
/// Copy-edit, Summary, Title — the phone's order) with the one label each.
enum PolishPromptKind: CaseIterable {
    case copyEdit, summary, title

    var label: String {
        switch self {
        case .copyEdit: return "Copy-edit prompt"
        case .summary: return "Summary prompt"
        case .title: return "Title prompt"
        }
    }

    var defaultText: String {
        switch self {
        case .copyEdit: return PolishPrompts.copyEdit
        case .summary: return PolishPrompts.summary
        case .title: return PolishPrompts.title
        }
    }
}
