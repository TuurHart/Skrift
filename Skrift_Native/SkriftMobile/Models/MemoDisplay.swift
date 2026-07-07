import Foundation

/// Display helpers shared by the memos list + memo detail. Kept off the `@Model`
/// so they don't touch SwiftData storage.
extension Memo {
    /// What to show as the heading: the phone-set title, else the transcript's
    /// first line (markers stripped), else the capture title (C3 captures), else
    /// a generic fallback.
    var displayTitle: String {
        if let t = title?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { return t }
        if let line = firstTranscriptLine { return line }
        // C3 captures: derive title from sharedContent (urlTitle / text head / "Image")
        if isShareCapture { return shareCaptureTitle }
        return "Voice note"
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
        return String(line.prefix(80))
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
    /// the next purge. Nil when the memo isn't in the trash. `now` injectable
    /// for tests.
    func trashDaysRemaining(now: Date = Date()) -> Int? {
        guard let deletedAt else { return nil }
        let remaining = TrashPolicy.retention - now.timeIntervalSince(deletedAt)
        return max(0, Int(ceil(remaining / 86_400)))
    }

    /// Countdown caption for Recently Deleted rows: "13 days left" / "1 day left"
    /// / "Deleting soon" (already past retention, gone at next launch).
    func trashCountdownLabel(now: Date = Date()) -> String? {
        guard let days = trashDaysRemaining(now: now) else { return nil }
        if days <= 0 { return "Deleting soon" }
        return days == 1 ? "1 day left" : "\(days) days left"
    }

    /// Resolve a `[[img_NNN]]` transcript marker (1-based) to its photo file in
    /// the recordings directory, via the metadata image manifest. Shared by
    /// every transcript renderer (editor, karaoke view, speaker turns).
    func imageURL(markerIndex n: Int) -> URL? {
        guard let manifest = metadata?.imageManifest, n >= 1, n <= manifest.count else { return nil }
        return AppPaths.recordingsDirectory.appendingPathComponent(manifest[n - 1].filename)
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
            return String(line.prefix(80))
        }
        return nil
    }

    /// The C1 quote block split for the DETAIL screen, gated on the C2 book
    /// metadata (a bare blockquote in an ordinary memo stays plain text). Nil
    /// when there's no leading "> " block to style.
    var captureQuote: CaptureQuote? {
        guard isBookCapture else { return nil }
        return CaptureQuote.split(transcript)
    }


    /// Plain-text attribution caption under the styled quote, from the C2
    /// metadata: "— Author, Book · ch. N". A non-numeric chapter (an m4b
    /// chapter *name*) passes through as-is, matching `bookCaptionLabel`.
    /// NO `[[..]]` — the wikilinked attribution stays Mac-export-side.
    var quoteAttributionLabel: String? {
        guard let book = metadata?.bookTitle?.trimmingCharacters(in: .whitespaces),
              !book.isEmpty else { return nil }
        var label = "— "
        if let author = metadata?.bookAuthor?.trimmingCharacters(in: .whitespaces),
           !author.isEmpty {
            label += "\(author), "
        }
        label += book
        if let chapter = metadata?.bookChapter?.trimmingCharacters(in: .whitespaces),
           !chapter.isEmpty {
            label += " · " + (chapter.allSatisfy(\.isNumber) ? "ch. \(chapter)" : chapter)
        }
        return label
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
                return String(text.prefix(80))
            }
            return "Text snippet"
        case .image:
            if let ann = annotationText?.trimmingCharacters(in: .whitespaces), !ann.isEmpty {
                return String(ann.prefix(80))
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

/// PRESENTATION-ONLY split of a capture transcript into its leading C1 "> "
/// blockquote and the ramble below. The stored transcript keeps its raw "> "
/// lines — this type carries the exact leading substring (`rawBlock`) so the
/// editor can re-prepend it verbatim and edits can never corrupt the quote.
///
/// Round trip: for the C1 shape the app writes (quote block, blank line,
/// ramble) `split(t)!.transcript(withRamble: split(t)!.ramble) == t` byte for
/// byte. A degenerate input missing the blank separator keeps the quote and
/// ramble bytes intact but normalises the separator to one blank line.
struct CaptureQuote: Equatable {
    /// The quote with the "> " markers stripped, for styled display. Bare ">"
    /// spacer lines inside the block become empty lines (paragraph breaks).
    let displayText: String
    /// The exact leading substring of the transcript covering the quote block,
    /// including any leading blanks and the blank separator line(s) after it.
    let rawBlock: String
    /// The exact remainder below the quote block (empty = no ramble yet).
    let ramble: String

    /// Spoken words in the quote (">" markers are not words). The word-timings
    /// sidecar holds the quote's spoken words first, then the appended ramble's
    /// — so this is the ramble's base index into the global karaoke timings.
    var spokenWordCount: Int {
        displayText.split(whereSeparator: \.isWhitespace).count
    }

    /// Parse the transcript's leading blockquote. Tolerates blank lines above
    /// the quote and bare/padded ">" markers (same rules as `quoteSnippet`);
    /// nil when the transcript doesn't open with a non-empty "> " block.
    static func split(_ transcript: String?) -> CaptureQuote? {
        guard let transcript, !transcript.isEmpty else { return nil }
        let lines = transcript.components(separatedBy: "\n")
        var i = 0
        while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).isEmpty { i += 1 }
        var quoteLines: [String] = []
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix(">") else { break }
            quoteLines.append(String(line.dropFirst()).trimmingCharacters(in: .whitespaces))
            i += 1
        }
        guard quoteLines.contains(where: { !$0.isEmpty }) else { return nil }
        // The blank separator after the quote belongs to the raw block, so the
        // ramble starts at its first real line.
        while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).isEmpty { i += 1 }
        while quoteLines.first?.isEmpty == true { quoteLines.removeFirst() }
        while quoteLines.last?.isEmpty == true { quoteLines.removeLast() }
        return CaptureQuote(
            displayText: quoteLines.joined(separator: "\n"),
            rawBlock: lines[0..<i].joined(separator: "\n"),
            ramble: lines[i...].joined(separator: "\n")
        )
    }

    /// Reassemble the stored transcript from an edited ramble: the raw quote
    /// block verbatim + a blank-line separator (kept byte-exact when the block
    /// already carries one) + the ramble. An emptied ramble leaves a quote-only
    /// capture — never a nil transcript.
    func transcript(withRamble newRamble: String) -> String {
        guard !newRamble.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return rawBlock
        }
        let separator = rawBlock.hasSuffix("\n") ? "\n" : "\n\n"
        return rawBlock + separator + newRamble
    }
}

enum MemoStatusKind: Equatable {
    case synced, waiting, transcribing, error

    var pillStyle: PillStyle {
        switch self {
        case .synced: return .synced
        case .waiting: return .waiting
        case .transcribing: return .working
        case .error: return .error
        }
    }

    var label: String {
        switch self {
        case .synced: return "Synced"
        case .waiting: return "Waiting"
        case .transcribing: return "Transcribing"
        case .error: return "Error"
        }
    }
}

/// Relative date labels matching the mockups ("Today · 09:41", "Yesterday · 21:12",
/// "Mon · 14:03").
enum MemoDate {
    static func label(_ date: Date, now: Date = Date()) -> String {
        let cal = Calendar.current
        let time = timeFormatter.string(from: date)
        // Day delta against the INJECTED `now` (not `isDateInToday`, which ignores `now` and
        // checks the wall clock — making these labels non-deterministic across midnight).
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date),
                                      to: cal.startOfDay(for: now)).day ?? 0
        if days <= 0 { return "Today · \(time)" }
        if days == 1 { return "Yesterday · \(time)" }
        // This week → weekday ("Fri · 14:29"). Older than a week, the weekday alone is
        // misleading — a memo from last year read identically to last Friday — so degrade to
        // a real date: same year → "19 Jun · 14:29", a different year → ISO "2025-06-19 · 14:29".
        if days < 7 { return "\(weekdayFormatter.string(from: date)) · \(time)" }
        if cal.component(.year, from: date) == cal.component(.year, from: now) {
            return "\(monthDayFormatter.string(from: date)) · \(time)"
        }
        return "\(isoDateFormatter.string(from: date)) · \(time)"
    }

    /// Day-group header key for the list ("Today" / "Yesterday" / "Mon 3 Jun").
    static func group(_ date: Date, now: Date = Date()) -> String {
        let cal = Calendar.current
        // Day delta against the injected `now` (deterministic across midnight — see `label`).
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date),
                                      to: cal.startOfDay(for: now)).day ?? 0
        if days <= 0 { return "Today" }
        if days == 1 { return "Yesterday" }
        // Carry the year on a different-year group so old day-groups aren't ambiguous.
        if cal.component(.year, from: date) == cal.component(.year, from: now) {
            return groupFormatter.string(from: date)
        }
        return groupYearFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE"; return f
    }()
    private static let groupFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE d MMM"; return f
    }()
    private static let monthDayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "d MMM"; return f
    }()
    private static let isoDateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    private static let groupYearFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE d MMM yyyy"; return f
    }()
}

/// Map a captured `DayPeriod` to an SF Symbol for the context chips.
extension DayPeriod {
    var symbol: String {
        switch self {
        case .morning: return "sunrise.fill"
        case .afternoon: return "sun.max.fill"
        case .evening: return "sunset.fill"
        case .night: return "moon.stars.fill"
        }
    }
    var label: String { rawValue.capitalized }
}
