import Foundation

/// Display helpers shared by the memos list + memo detail. Kept off the `@Model`
/// so they don't touch SwiftData storage.
extension Memo {
    /// What to show as the heading: the phone-set title, else the transcript's
    /// first line (markers stripped), else the capture title (C3 captures), else
    /// a generic fallback.
    var displayTitle: String { displayTitle(enhancedTitle: nil) }

    /// Title precedence, with the Mac's GENERATED title as the middle tier.
    ///
    /// `enhancedTitle` is `MemoEnhancement.title` — the Mac's suggestion, which is
    /// deliberately never auto-applied to `Memo.title` (choosing stays the user's).
    /// Without it here the detail screen and the LIST disagreed on the same note: detail
    /// read the enhancement and showed a real title, the list fell through to the
    /// transcript's first line and showed the body (Tuur, 2026-07-27). A chosen title
    /// still wins; this only fills the gap where nobody has chosen yet.
    ///
    /// Display-only — it never writes `Memo.title`, so the choice you haven't made yet
    /// stays unmade.
    func displayTitle(enhancedTitle: String?) -> String {
        ladderTitle(suggestedTitle: enhancedTitle)   // C25: the ONE ladder (`NoteTitle.display`)
    }

    /// First non-empty line of the transcript with `[[img_NNN]]` markers removed.
    var firstTranscriptLine: String? { NoteCardBuilder.firstLine(of: transcript) }   // C115: one rule, both apps

    var durationLabel: String { DurationFormat.label(seconds: duration) }

    /// True when this memo was imported from a VIDEO (audio extracted + one frame).
    /// Drives the video source glyph in the list row + the "Video" chip in detail.
    /// A video import is an ordinary audio memo otherwise (not a share/book capture),
    /// so it needs its own source marker (`metadata.sourceType`).
    var isVideoImport: Bool {
        SourceKind.of(self) == .video
    }

    /// Full-text search — the ONE shared matcher (`NoteSearch`, Q103/C236): title, generated
    /// title, transcript, summary, tags, place, annotation, shared-capture text, photo OCR.
    /// `enhancedTitle` / `summary` are the note's `MemoEnhancement` fields when the caller has
    /// them. A locked note's body stays out until unlocked this session (Q101).
    func matches(query: String, unlockedThisSession: Bool = false,
                 enhancedTitle: String? = nil, summary: String? = nil) -> Bool {
        // No query matches everything: don't decode a snapshot just to say yes (Q315).
        guard NotesListModel.isSearching(query) else { return true }
        return NoteSearch.matches(query: query, noteSearchSnapshot(unlockedThisSession: unlockedThisSession,
                                                            enhancedTitle: enhancedTitle, summary: summary))
    }

    /// Resolve a `[[img_NNN]]` transcript marker (1-based) to its photo file in
    /// the recordings directory, via the metadata image manifest. Shared by
    /// every transcript renderer (editor, karaoke view, speaker turns).
    func imageURL(markerIndex n: Int) -> URL? {
        guard let manifest = metadata?.imageManifest, n >= 1, n <= manifest.count else { return nil }
        return AppPaths.recordingsDirectory.appendingPathComponent(manifest[n - 1].filename)
    }


    /// The photo the LIST ROW thumbnails — the note's first VISIBLE photo, not
    /// blindly the first manifest entry. Deleting a photo in the editor removes
    /// its `[[img_NNN]]` marker from the body but NEVER its manifest entry
    /// (markers are 1-based indexes into the manifest, so pruning an entry would
    /// renumber every later marker on both apps) — so visibility comes from the
    /// body:
    /// - Body carries markers → the first marker in body order that resolves.
    /// - Markers were injected but none survive → every photo was deleted from
    ///   the note → no thumbnail.
    /// - A marker-less body: share captures keep the first manifest entry (their
    ///   photos render straight off the manifest, no markers), as does a memo
    ///   with no body yet (pending/failed transcription — the photo taken while
    ///   recording should thumbnail immediately). A TYPED body without markers
    ///   shows no photos, so no thumbnail.
    var thumbnailPhotoFilename: String? {
        guard let manifest = metadata?.imageManifest, !manifest.isEmpty else { return nil }
        let body = (isShareCapture ? annotationText : transcript) ?? ""
        // A recording whose body hasn't landed yet thumbnails the photo taken while
        // recording — the thumb must not wait for the body.
        if !isShareCapture, !transcriptMarkersInjected,
           body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return manifest.first?.filename
        }
        // C170 via body v2's one rule. A typed body passes as `.speech`: v2 never gives a
        // typed note a marker it doesn't have, so a marker there is an editor photo and
        // drives the thumb like any other.
        let source: BodyV2.Source = isShareCapture ? .shareCapture : .speech
        guard let n = BodyV2Thumbnail.pick(body: body, manifestCount: manifest.count,
                                           source: source, resolves: { _ in true })
        else { return nil }
        return manifest[n - 1].filename
    }

    /// Honest status for the list pill, or `nil` when no pill should show.
    ///
    /// Only the transcript states (`transcribing` / `error`) drive a per-memo pill.
    /// There is no per-memo *sync* pill: under CloudKit every memo mirrors to iCloud
    /// automatically, so a "Waiting"/"Synced" badge would either lie or be noise —
    /// sync visibility comes from the global "Syncing with iCloud…" chip instead.
    var statusKind: MemoStatusKind? {
        if transcriptStatus == .transcribing { return .transcribing }
        if transcriptStatus == .failed { return .error }
        return nil
    }
}

// MARK: - Audiobook captures

/// Display helpers for audiobook quote-capture memos. Detection rides the C2
/// contract: `MemoMetadata.bookTitle` (set by the capture flow, defined in
/// `Models/MemoMetadata.swift`) marks a memo as a book capture. The transcript
/// shape is the C1 contract: markdown blockquote lines ("> ") holding the quote
/// at the TOP, a blank line, then the ramble.
extension Memo {
    /// True when this memo is an audiobook quote capture (C2 book metadata
    /// present). Drives the book glyph + quote-styled row in the memos list.
    var isBookCapture: Bool {
        !(metadata?.bookTitle?.trimmingCharacters(in: .whitespaces).isEmpty ?? true)
    }

    /// "Book · ch. N" caption for capture rows. A purely numeric chapter gets
    /// the "ch. " prefix (matching the export attribution); anything else (e.g.
    /// an m4b chapter *name*) is shown as-is. Nil for non-capture memos.
    var bookCaptionLabel: String? {
        CaptureQuote.caption(book: metadata?.bookTitle, chapter: metadata?.bookChapter)
    }

    /// The C1 quote block — the transcript's leading "> " blockquote lines,
    /// stripped of the markers and joined into one row-sized snippet. Nil when
    /// the transcript doesn't open with a blockquote (or doesn't exist yet).
    /// Q106: the one shared builder (`NoteCardBuilder.quoteLine`, over `CaptureQuote.split`).
    var quoteSnippet: String? { NoteCardBuilder.quoteLine(in: transcript) }

    /// The leading `> ` quote block split for the DETAIL screen. Nil when the body doesn't
    /// open with one.
    ///
    /// NOT gated on the C2 book metadata any more (2026-07-27). It was — "a bare blockquote
    /// in an ordinary memo stays plain text" — and that gate was wrong for a reason design
    /// alone wouldn't have caught: the metadata is a synced blob that can be missing, so the
    /// same capture rendered as a styled quote here and as a raw `> ` wall on the Mac. The
    /// text is what makes it a quote; only the attribution caption needs the metadata.
    var captureQuote: CaptureQuote? { CaptureQuote.split(transcript) }


    /// Plain-text attribution caption under the styled quote, from the C2
    /// metadata: "— Author, Book · ch. N". A non-numeric chapter (an m4b
    /// chapter *name*) passes through as-is, matching `bookCaptionLabel`.
    /// NO `[[..]]` — the wikilinked attribution stays Mac-export-side.
    var quoteAttributionLabel: String? {
        CaptureQuote.attribution(book: metadata?.bookTitle,
                                 author: metadata?.bookAuthor,
                                 chapter: metadata?.bookChapter)
    }
}

// MARK: - C3 share-item captures

/// Display helpers for C3 capture-item memos (URL / text / image shared via the
/// SkriftShare extension). Detection: `audioFilename == "" && sharedContent != nil`.
/// Pattern mirrors the C2 audiobook-capture helpers above.
extension Memo {
    /// True when this memo is a C3 capture item (no audio, has sharedContent).
    var isShareCapture: Bool {
        audioFilename.isEmpty && sharedContent != nil
    }

    /// The source type the shared rules read (`SpeakerTranscript.isConversation(_:source:)`, D178):
    /// a recording has audio; a typed note has none; a share capture has a payload instead.
    var linkSource: NoteSourceType {
        isShareCapture ? .capture : audioFilename.isEmpty ? .note : .audio
    }

    /// Body v2's source for this note (C10, C170): a share capture, a typed note (no
    /// audio), or speech.
    var bodyV2Source: BodyV2.Source {
        isShareCapture ? .shareCapture : audioFilename.isEmpty ? .typed : .speech
    }

    /// SF Symbol glyph for the list row icon, keyed off `sharedContent.type`.
    var shareCaptureGlyph: String {
        sharedContent == nil ? SourceKind.captureURL.glyph : SourceKind.of(self).glyph
    }

    /// Primary title for a capture row: urlTitle (URL), first words of text (text),
    /// annotation-or-"Image" (image). Falls back through annotationText → generic.
    var shareCaptureTitle: String {
        guard let sc = sharedContent else { return "Capture" }
        return NoteCardBuilder.captureTitle(shared: sc, annotation: annotationText)
    }

    /// Snippet / secondary line: annotationText for all types; domain for URLs as fallback.
    var shareCaptureSnippet: String? {
        guard let sc = sharedContent else { return nil }
        return NoteCardBuilder.captureSnippet(shared: sc, annotation: annotationText)
    }

    /// Domain label for URL captures, e.g. "swiftwithmajid.com".
    var shareCaptureURLDomain: String? {
        sharedContent.flatMap { NoteCardBuilder.domain(of: $0) }
    }
}

enum MemoStatusKind: Equatable {
    case transcribing, error

    var label: String {
        switch self {
        case .transcribing: return "Transcribing"
        case .error: return "Error"
        }
    }
}
