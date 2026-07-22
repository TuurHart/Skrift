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
}
