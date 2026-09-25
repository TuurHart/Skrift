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
        if let t = title?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { return t }
        if let e = enhancedTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !e.isEmpty {
            return NoteTitle.clip(e)
        }
        if let line = firstTranscriptLine { return line }
        // C3 captures: derive title from sharedContent (urlTitle / text head / "Image")
        if isShareCapture { return shareCaptureTitle }
        return SourceKind.of(self).emptyTitleFallback   // typed → "Note", else "Voice note"
    }

    /// First non-empty line of the transcript with `[[img_NNN]]` markers removed.
    var firstTranscriptLine: String? {
        guard let transcript else { return nil }
        let cleaned = transcript.replacingOccurrences(
            of: #"\[\[img_\d+\]\]"#, with: "", options: .regularExpression
        )
        let line = cleaned
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first(where: { !$0.isEmpty })
        guard let line, !line.isEmpty else { return nil }
        return NoteTitle.clip(line)
    }

    var durationLabel: String {
        let total = Int(duration.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// True when this memo was imported from a VIDEO (audio extracted + one frame).
    /// Drives the video source glyph in the list row + the "Video" chip in detail.
    /// A video import is an ordinary audio memo otherwise (not a share/book capture),
    /// so it needs its own source marker (`metadata.sourceType`).
    var isVideoImport: Bool {
        metadata?.sourceType == MemoMetadata.Source.video
    }

    /// Whole days until the startup purge permanently removes this trashed memo
    /// (ceiling — a memo deleted an hour ago shows the full 14). 0 = expires on
    /// the next purge. Nil when the memo isn't in the trash. v3 (2026-07-23):
    /// counts from the trash SIGHTING (`MemoLifecycle.goneAt`), matching the
    /// purge gate — an unseen synced-in deletion shows the full window, because
    /// that's what it truly has. `now` injectable for tests.
    func trashDaysRemaining(now: Date = Date()) -> Int? {
        guard deletedAt != nil else { return nil }
        let remaining = MemoLifecycle.goneAt(self, now: now).timeIntervalSince(now)
        return max(0, Int(ceil(remaining / 86_400)))
    }

    /// Countdown caption for Recently Deleted rows: "13 days left" / "1 day left"
    /// / "Deleting soon" (already past retention, gone at next launch).
    func trashCountdownLabel(now: Date = Date()) -> String? {
        guard let days = trashDaysRemaining(now: now) else { return nil }
        if days <= 0 { return "Deleting soon" }
        return days == 1 ? "1 day left" : "\(days) days left"
    }

    /// Full-text search over everything the memo knows: title, transcript,
    /// tags, place, capture fields — and the photos' OCR text (chunk 6).
    /// Extracted from the list so it's testable and single-sourced.
    func matches(query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return true }
        if title?.lowercased().contains(q) == true { return true }
        if transcript?.lowercased().contains(q) == true { return true }
        if tags.contains(where: { $0.lowercased().contains(q) }) { return true }
        if metadata?.location?.placeName?.lowercased().contains(q) == true { return true }
        // C3 capture items: search annotation + urlTitle + text snippet
        if annotationText?.lowercased().contains(q) == true { return true }
        if sharedContent?.urlTitle?.lowercased().contains(q) == true { return true }
        if sharedContent?.text?.lowercased().contains(q) == true { return true }
        // Photo OCR (on-device Vision → synced manifest text).
        if metadata?.imageManifest?.contains(where: { $0.text?.lowercased().contains(q) == true }) == true {
            return true
        }
        return false
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
        guard let book = metadata?.bookTitle?.trimmingCharacters(in: .whitespaces),
              !book.isEmpty else { return nil }
        guard let chapter = metadata?.bookChapter?.trimmingCharacters(in: .whitespaces),
              !chapter.isEmpty else { return book }
        let label = chapter.allSatisfy(\.isNumber) ? "ch. \(chapter)" : chapter
        return "\(book) · \(label)"
    }

    /// The C1 quote block — the transcript's leading "> " blockquote lines,
    /// stripped of the markers and joined into one row-sized snippet. Nil when
    /// the transcript doesn't open with a blockquote (or doesn't exist yet).
    var quoteSnippet: String? {
        guard let transcript else { return nil }
        var lines: [String] = []
        for raw in transcript.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix(">") {
                let text = line.dropFirst().trimmingCharacters(in: .whitespaces)
                if !text.isEmpty { lines.append(text) }
            } else if lines.isEmpty && line.isEmpty {
                continue            // tolerate leading blank lines
            } else {
                break               // the quote block is the TOP — stop at the first non-quote line
            }
        }
        guard !lines.isEmpty else { return nil }
        return String(lines.joined(separator: " ").prefix(120))
    }

    /// First line of the ramble below the C1 quote block (markers stripped) —
    /// the capture row's secondary text. Nil while the capture has no ramble
    /// yet ("Save & keep listening" without recording thoughts).
    var rambleSnippet: String? {
        guard let transcript else { return nil }
        let cleaned = transcript.replacingOccurrences(
            of: #"\[\[img_\d+\]\]"#, with: "", options: .regularExpression
        )
        // Quote lines only legally appear at the top (C1), so skipping every
        // "> " line is equivalent to skipping the head block — and simpler.
        for raw in cleaned.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix(">") { continue }
            return NoteTitle.clip(line)
        }
        return nil
    }

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

    /// Body v2's source for this note (C10, C170): a share capture, a typed note (no
    /// audio), or speech.
    var bodyV2Source: BodyV2.Source {
        isShareCapture ? .shareCapture : audioFilename.isEmpty ? .typed : .speech
    }

    /// SF Symbol glyph for the list row icon, keyed off `sharedContent.type`.
    var shareCaptureGlyph: String {
        switch sharedContent?.type {
        case .url:   return "link"
        case .text:  return "text.quote"
        case .image: return "photo"
        case .file:  return "doc"
        case nil:    return "link"
        }
    }

    /// Primary title for a capture row: urlTitle (URL), first words of text (text),
    /// annotation-or-"Image" (image). Falls back through annotationText → generic.
    var shareCaptureTitle: String {
        guard let sc = sharedContent else { return "Capture" }
        switch sc.type {
        case .url:
            if let t = sc.urlTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { return t }
            if let u = sc.url, let host = URL(string: u)?.host { return host }
            return "Link"
        case .text:
            if let text = sc.text?.trimmingCharacters(in: .whitespaces), !text.isEmpty {
                return NoteTitle.clip(text)
            }
            return "Text snippet"
        case .image:
            if let ann = annotationText?.trimmingCharacters(in: .whitespaces), !ann.isEmpty {
                return NoteTitle.clip(ann)
            }
            return "Image"
        case .file:
            return sc.fileName ?? "File"
        }
    }

    /// Snippet / secondary line: annotationText for all types; domain for URLs as fallback.
    var shareCaptureSnippet: String? {
        if let ann = annotationText?.trimmingCharacters(in: .whitespacesAndNewlines), !ann.isEmpty {
            return String(ann.prefix(120))
        }
        // For URL captures with no annotation, show the domain as the snippet.
        if sharedContent?.type == .url,
           let urlStr = sharedContent?.url,
           let host = URL(string: urlStr)?.host {
            return host.replacingOccurrences(of: "www.", with: "")
        }
        return nil
    }

    /// "Link", "Text", or "Image" chip label for the detail header chips.
    var shareCaptureTypeLabel: String {
        switch sharedContent?.type {
        case .url:   return "Shared link"
        case .text:  return "Shared text"
        case .image: return "Shared image"
        case .file:  return "Shared file"
        case nil:    return "Capture"
        }
    }

    /// Domain label for URL captures, e.g. "swiftwithmajid.com".
    var shareCaptureURLDomain: String? {
        guard sharedContent?.type == .url,
              let urlStr = sharedContent?.url,
              let host = URL(string: urlStr)?.host else { return nil }
        return host.replacingOccurrences(of: "www.", with: "")
    }
}

// `CaptureQuote` (the leading `> ` block split + the attribution caption) moved to
// Shared/Model/CaptureQuote.swift on 2026-07-27 — the Mac had a second copy of the same
// rule, and a quote has to look identical on every app.

enum MemoStatusKind: Equatable {
    case synced, waiting, transcribing, error

    var label: String {
        switch self {
        case .synced: return "Synced"
        case .waiting: return "Waiting"
        case .transcribing: return "Transcribing"
        case .error: return "Error"
        }
    }
}

// `MemoDate` moved to `Shared/Model/MemoDate.swift` (Q26, D135/D136 — the unified
// notes list): the Mac's queue rows now stamp with the same clock word + day group.

/// Map a captured `DayPeriod` to an SF Symbol for the context chips.
// DayPeriod.symbol / .label moved to the SHARED model (Shared/Model/MemoMetadata.swift)
// so the phone header and the Mac properties share one definition.
