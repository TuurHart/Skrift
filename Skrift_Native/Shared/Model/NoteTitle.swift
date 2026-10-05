import Foundation

/// The derived-title cut: what a note shows when it has no title of its own and
/// falls back to its opening words.
///
/// Breaks on a WORD boundary and marks the cut with an ellipsis. The rule used to
/// be a bare `prefix(80)`, which ends mid-word — *"…once I click the record button,
/// it s"* — and reads as a rendering fault rather than a truncation (Tuur,
/// 2026-07-26). It surfaced on an unrated note, where there is never a real title
/// to fall back FROM, so the derived one is always what you see.
///
/// SHARED on purpose: the same slice had been pasted into seven display sites
/// across both apps, so tuning one would have drifted it from the rest.
///
/// Deliberately NOT used by `MemoExporter.exportTitle` — that feeds the vault
/// FILENAME through `ObsidianPublisher.sanitizeFilename`, where an ellipsis would
/// rename notes on disk. A filename stem wants the plain hard cut.
enum NoteTitle {
    /// Longest derived title shown, in characters.
    static let limit = 80

    /// Clip `line` to `limit` on a word boundary, appending "…". Returned unchanged
    /// when it already fits.
    static func clip(_ line: String) -> String {
        guard line.count > limit else { return line }
        let head = line.prefix(limit)
        // Break at the last space so a word is never sliced in half. A single word
        // longer than the whole limit has no boundary to find — cut that one hard
        // rather than return an empty title.
        if let space = head.lastIndex(where: { $0.isWhitespace }) {
            let trimmed = head[..<space].trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return trimmed + "…" }
        }
        return head.trimmingCharacters(in: .whitespaces) + "…"
    }

    // MARK: - The one display ladder (C25)

    /// Longest derived title (first body line), in characters — one number for display and
    /// the vault filename (C25, C165).
    static let derivedLimit = 120

    /// The C25 ladder, ONE rule for both apps and the exporters: user title → suggested
    /// title → first body line (markers stripped, clipped at 120 on a word boundary) →
    /// share title. nil when the note has none of them (the caller's fallback decides:
    /// "Note" / "Voice note" for a row, the "Add a title" prompt for the header).
    /// For a share capture `body` is its annotation (the user's words on the shared thing).
    static func derived(userTitle: String?, suggestedTitle: String?, body: String?,
                        shared: SharedContent?) -> String? {
        if let t = trimmed(userTitle) { return t }
        if let t = trimmed(suggestedTitle) { return t }
        if let line = firstLine(body) { return line }
        if shared != nil { return captureTitle(shared) }
        return nil
    }

    /// `derived`, never empty: then the import's real file name (D176: shown until the note
    /// has words), last `emptyFallback` ("Note" for a typed note, "Voice note" otherwise —
    /// `SourceKind.emptyTitleFallback`). `importName` is a RAW file name; the generic-name
    /// filter (`importName(_:)`) runs here so every caller gets the same rule.
    static func display(userTitle: String?, suggestedTitle: String?, body: String?,
                        shared: SharedContent?, importFileName: @autoclosure () -> String? = nil,
                        emptyFallback: @autoclosure () -> String) -> String {
        // Q320: both lower rungs are lazy. A note with words never reads its import name or its
        // source kind (`SourceKind.of` parses two blobs), which is every note in the "[[" picker.
        derived(userTitle: userTitle, suggestedTitle: suggestedTitle, body: body, shared: shared)
            ?? importName(importFileName())
            ?? emptyFallback()
    }

    /// D176 (amends C25): an imported audio's REAL file name, extension stripped, or nil when
    /// the name is no name: empty, a synthetic `memo_<uuid>`, a bare UUID, or a generic
    /// default ("New Recording 22", "Audio 3", "Recording", "Voice Memo 4", "Untitled").
    /// Those fall back to "Voice note". Shown only until the note has words (the rung sits
    /// below the first body line). One rule for the phone (stored `importFileName`) and the
    /// Mac (the working file's own name).
    static func importName(_ fileName: String?) -> String? {
        guard var name = fileName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        if let dot = name.lastIndex(of: "."), !name[name.index(after: dot)...].contains("/"),
           name[name.index(after: dot)...].count <= 5, dot != name.startIndex {
            name = String(name[..<dot]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !name.isEmpty, !name.lowercased().hasPrefix("memo_"), UUID(uuidString: name) == nil else { return nil }
        let generic = #"^(new recording|recording|audio|audio file|voice memo|voice note|untitled|new audio)[\s_-]*\d*$"#
        if name.range(of: generic, options: [.regularExpression, .caseInsensitive]) != nil { return nil }
        return name
    }

    /// The capture rung: urlTitle → (a link) its host → first 8 words of the shared text → file
    /// name → "Capture". A link with no page title is titled by its HOST (C72, `LinkCard.hostTitle`,
    /// the rule the Mac's link door stores), never by its search-only article text or the raw URL.
    static func captureTitle(_ sc: SharedContent?) -> String {
        if let title = sc?.urlTitle?.trimmingCharacters(in: .whitespaces), !title.isEmpty { return title }
        if let host = linkHost(sc) { return host }
        if let text = sc?.text?.trimmingCharacters(in: .whitespaces), !text.isEmpty {
            let words = text.split(separator: " ")
            let head = words.prefix(8).joined(separator: " ")
            return head.isEmpty ? text : head + (words.count > 8 ? "…" : "")
        }
        if let fileName = sc?.fileName?.trimmingCharacters(in: .whitespaces), !fileName.isEmpty { return fileName }
        return "Capture"
    }

    /// A link capture's host title (`www.` dropped), or nil for any other capture / no host.
    static func linkHost(_ sc: SharedContent?) -> String? {
        guard sc?.type == .url,
              let raw = sc?.url?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: raw) else { return nil }
        return LinkCard.hostTitle(url)
    }

    /// The raw file name a Mac row offers the ladder (D176): a phone import's stored
    /// `importFileName` (its working file is `memo_<uuid>.m4a`, never the name), else the
    /// working file's own name (a Mac-local import keeps the user's name). `importName(_:)`
    /// then rejects anything generic. nil for a capture (its name is the capture rung's).
    static func importFileName(metadataJSON: Data?, workingFilename: String, isCapture: Bool) -> String? {
        guard !isCapture else { return nil }
        return MemoMetadata.lenient(from: metadataJSON)?.importFileName ?? workingFilename
    }

    /// The first non-empty line of `body` with markers stripped (`[[img_NNN]]`, name and
    /// memo links, `**Name:**`), clipped at `derivedLimit` on a word boundary. No ellipsis:
    /// the line also names the file, and a filename wants the plain cut.
    static func firstLine(_ body: String?) -> String? {
        guard let body, !body.isEmpty else { return nil }
        let first = NoteSnippet.plain(body)
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first(where: { !$0.isEmpty })
        // A leading `> ` is a book capture's quote marker, not part of the words.
        guard let line = first?.replacingOccurrences(of: #"^>\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces), !line.isEmpty else { return nil }
        guard line.count > derivedLimit else { return line }
        let head = line.prefix(derivedLimit)
        if let space = head.lastIndex(where: { $0.isWhitespace }) {
            let cut = head[..<space].trimmingCharacters(in: .whitespaces)
            if !cut.isEmpty { return cut }
        }
        return String(head).trimmingCharacters(in: .whitespaces)
    }

    private static func trimmed(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }

    /// Longest "From the recording" title option, in characters.
    static let recordingLimit = 60

    /// The "From the recording" title option, ONE rule for both apps (C181/C25): the first
    /// non-empty line of the RAW transcript (markers / speaker prefixes stripped), cut to 60.
    /// nil when there is no transcript text. Never reads a filename — a phone memo's file is
    /// `memo_<uuid>.m4a`, which must never be offered as a title.
    static func recordingLine(transcript: String?) -> String? {
        guard let transcript else { return nil }
        let line = NoteSnippet.plain(transcript)
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first(where: { !$0.isEmpty })
        guard let line else { return nil }
        let cut = String(clip(line).prefix(recordingLimit)).trimmingCharacters(in: .whitespaces)
        return cut.isEmpty ? nil : cut
    }
}

/// A note's title inputs as plain values (Q320): everything `Memo.ladderTitle` reads, copied on the
/// main actor so the title itself can be built off it. `title(suggestedTitle:)` IS the C25 ladder
/// for a memo; `Memo.ladderTitle` calls it, so the two cannot drift.
struct LadderSnapshot: Sendable {
    let userTitle: String?
    let transcript: String?
    let annotationText: String?
    let metadataData: Data?
    let sharedContentData: Data?
    let hasAudio: Bool

    init(_ memo: Memo) {
        userTitle = memo.title
        transcript = memo.transcript
        annotationText = memo.annotationText
        metadataData = memo.metadataData
        sharedContentData = memo.sharedContentData
        hasAudio = !memo.audioFilename.isEmpty
    }

    func title(suggestedTitle: String? = nil) -> String {
        // A share capture: no audio, a shared thing. Its body for the ladder is the annotation.
        let shared: SharedContent? = sharedContentData == nil ? nil : Memo.decodeJSON(sharedContentData)
        let isCapture = !hasAudio && shared != nil
        return NoteTitle.display(userTitle: userTitle, suggestedTitle: suggestedTitle,
                                 body: isCapture ? annotationText : transcript,
                                 shared: isCapture ? shared : nil,
                                 importFileName: isCapture ? nil : Memo.metadata(from: metadataData)?.importFileName,
                                 emptyFallback: SourceKind.of(metadataData: metadataData,
                                                              sharedContentData: sharedContentData,
                                                              hasAudio: hasAudio).emptyTitleFallback)
    }
}

extension Memo {
    /// A share capture: no audio, a shared thing. Its body for the ladder is the annotation.
    private var ladderIsCapture: Bool { audioFilename.isEmpty && sharedContent != nil }

    /// This memo's C25 title (list row, header prompt, link rows). `suggestedTitle` is the
    /// Mac's `MemoEnhancement.title` when the caller has it. Display-only: never writes
    /// `title` (choosing stays the user's).
    func ladderTitle(suggestedTitle: String? = nil) -> String {
        LadderSnapshot(self).title(suggestedTitle: suggestedTitle)
    }

    /// What the header's empty title field ghosts: the ladder minus the user's own title.
    /// nil when the note has nothing to derive from (the field then shows "Add a title").
    func ladderGhost(suggestedTitle: String? = nil, withUserTitle: Bool = false) -> String? {
        NoteTitle.derived(userTitle: withUserTitle ? title : nil, suggestedTitle: suggestedTitle,
                          body: ladderIsCapture ? annotationText : transcript,
                          shared: ladderIsCapture ? sharedContent : nil)
    }
}
