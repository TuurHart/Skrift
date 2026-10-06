import SwiftUI
import SwiftData

/// The note body. Three states sharing the same typography so swapping never
/// reflows (the web's karaoke-jump fix):
///  - playing      → karaoke highlight over the body words
///  - interactive  → editable TextEditor (literal [[brackets]], like the web's
///                   contenteditable)
///  - snapshot/read→ styled Text with accent-colored [[links]] (WYSIWYG preview)
///
/// Body precedence + write-back target match the web `getBestText`:
/// sanitised → copy-edit → transcript.
struct NoteBody: View {
    @Bindable var file: PipelineFile
    @Bindable var audio: AudioController
    var interactive: Bool = true
    var onAddName: (String) -> Void = { _ in }
    /// Add the selection as an alias of an existing person (word, canonical).
    var onAddAlias: (String, String) -> Void = { _, _ in }
    /// Naming-review callbacks (mocks/naming-review.html); nil on read-only hosts.
    var onSuggestionPick: ((String, String) -> Void)? = nil
    var onSuggestionPlain: ((String) -> Void)? = nil
    var onLinkedUnlink: ((String) -> Void)? = nil
    var onLinkedChange: ((String, String) -> Void)? = nil
    var onOpenNote: ((String) -> Void)? = nil
    /// Q87: a click on a speaker's gutter name → who is this (nil = inert).
    var speakerAssign: SpeakerAssign? = nil
    /// Memo↔memo link chip clicked → open that memo (nil = inert chips).
    var onOpenMemoLink: ((UUID) -> Void)? = nil
    /// The `[[` picker's link targets (lazily evaluated; empty = picker disabled).
    var linkCandidates: () -> [MemoLinkCandidate] = { [] }
    /// Resolve a link target's CURRENT title so chips don't show a stale snapshot.
    var linkTitle: (UUID) -> String? = { _ in nil }
    /// Note opened from an active sidebar search → scroll to + flash the first
    /// match (phone parity). nil/empty = no jump.
    var searchJumpToken: String? = nil
    /// A new note: put the cursor in the body once for this token.
    var focusToken: String? = nil
    /// Q183/Q124: a Split speakers run is rewriting this note's words — read-only like a
    /// transcription in flight.
    var splitting: Bool = false

    private static let bodyFont = Font.system(size: 16)
    @State private var trackCache = KaraokeTrackCache()
    private static let bodyLineSpacing: CGFloat = 6

    /// The real loaded duration when available (locally-ingested audio has no phone
    /// metadata), then the metadata hint, then the last word-timing's end — so karaoke
    /// activates for any playable note, not just phone memos.
    private var effectiveDuration: Double {
        if audio.duration > 0 { return audio.duration }
        if file.durationSeconds > 0 { return file.durationSeconds }
        return file.wordTimings.last?.end ?? 0
    }

    private var karaokeActive: Bool {
        audio.isPlaying && effectiveDuration > 0 && file.steps.transcribe == .done
    }

    /// Q124 (C173): playing / read-only (transcribing or splitting) / editing — the phone's
    /// `NoteBody.mode` on the Mac's step columns.
    private var editState: MacBodyEditableState {
        MacBodyEditableState.of(isPlaying: karaokeActive, transcribe: file.steps.transcribe, splitting: splitting)
    }

    var body: some View {
        Group {
            if interactive {
                // The real app ALWAYS uses the NSTextView — even during karaoke — so
                // play never swaps renderers (no reflow / size change). Karaoke is
                // applied as a recolor + click-to-seek on the same view.
                editor
            } else if karaokeActive {
                karaoke   // snapshot/read-only path (ImageRenderer can't host NSTextView)
            } else {
                readBody
            }
        }
        // Q143 (note-capture-06): an empty capture annotation reads as an invitation, the
        // phone's own words (`CaptureAnnotationEditor`). The text view keeps a 5 pt line
        // fragment padding, so the prompt sits on the caret.
        .overlay(alignment: .topLeading) {
            if interactive, file.sourceType == .capture, file.bestBodyText.isEmpty {
                Text(NoteBody.capturePlaceholder)
                    .font(Self.bodyFont)
                    .foregroundStyle(Theme.textMuted)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }
        }
    }

    /// The prompt on an empty capture annotation — the phone's wording, one string.
    static let capturePlaceholder = "Add a note about this…"

    /// Read/snapshot body. A leading `> ` block renders styled (italic + accent bar, plus the
    /// attribution caption when the C2 book fields are known) above the ramble — presentation
    /// only, the stored text keeps its raw `> ` lines (and the real `[[Author]]` stays
    /// export-time in the Compiler). The quote look rides on the TEXT, not on the metadata:
    /// that blob can be missing on a synced note, and a quote is still a quote.
    @ViewBuilder private var readBody: some View {
        if let split = CaptureQuote.split(file.bestBodyText) {
            VStack(alignment: .leading, spacing: 18) {
                quoteCard(split.displayText, attribution: file.bookCapture?.attribution)
                if !split.ramble.isEmpty {
                    BodyText.styled(split.ramble)
                        .font(Self.bodyFont)
                        .lineSpacing(Self.bodyLineSpacing)
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } else {
            BodyText.styled(file.bestBodyText)
                .font(Self.bodyFont)
                .lineSpacing(Self.bodyLineSpacing)
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The styled quote block — the phone's `CaptureQuoteFrame`, drawn with Mac types:
    /// italic dimmed quote lines behind a 3pt accent capsule, attribution caption underneath
    /// when it's known. Takes the `> `-stripped `displayText`, so the markers don't show
    /// (the model keeps them — the reader just shouldn't have to read syntax).
    private func quoteCard(_ quote: String, attribution: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            BodyText.styled(quote)
                .font(Self.bodyFont.italic())
                .lineSpacing(Self.bodyLineSpacing)
                .foregroundStyle(Theme.textPrimary.opacity(0.78))
            if let attribution {
                Text(attribution)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 14)
        .overlay(alignment: .leading) {
            Capsule()
                .fill(Theme.accent.opacity(0.65))
                .frame(width: 3)
        }
    }

    private var editor: some View {
        // NSTextView bridge: self-sizing + live [[link]] accent styling + inline
        // image thumbnails + the click-a-linked-name unlink popover + in-place karaoke
        // (recolor the same view + click a word to seek — no reflow, no renderer swap).
        BodyTextView(
            text: bodyBinding, imageURL: imageURL, onAddName: onAddName, onAddAlias: onAddAlias,
            suggested: karaokeActive ? [] : (file.ambiguousNames ?? []),
            onSuggestionPick: karaokeActive ? nil : onSuggestionPick,
            onSuggestionPlain: karaokeActive ? nil : onSuggestionPlain,
            onLinkedUnlink: karaokeActive ? nil : onLinkedUnlink,
            onLinkedChange: karaokeActive ? nil : onLinkedChange,
            onOpenNote: karaokeActive ? nil : onOpenNote,
            speakerAssign: karaokeActive ? nil : speakerAssign,
            onOpenMemoLink: karaokeActive ? nil : onOpenMemoLink,
            linkCandidates: karaokeActive ? { [] } : linkCandidates,
            linkTitle: linkTitle,
            tagCandidates: karaokeActive ? { [] } : tagCandidates,
            onInlineTag: onInlineTag,
            karaoke: karaokeActive ? karaokePlayback : nil,
            quoteAttribution: file.bookCapture?.attribution,
            searchJumpToken: searchJumpToken,
            focusToken: focusToken,
            readOnly: editState == .reading,
            quoteLocked: file.hasLockedQuote,
            photoSlot: photoSlot,
            onAddPhoto: addPhoto,
            onPhotoMarkup: photoMarkedUp,
            photoToken: file.lastActivityAt
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Inline `#` completion source: the note's deterministic suggestions first, then
    /// every library tag most-used-first (`TagLibrary` — the same source as the
    /// properties typeahead, so the two suggestion surfaces can't disagree).
    private func tagCandidates() -> [String] {
        (file.tagSuggestions ?? []) + TagLibrary.mostUsedFirst(file.modelContext)
    }

    /// A tag completed in the body's `#` popup: FILE it too, so inline tags reach the
    /// frontmatter on export. The properties card's `onChange(of: file.tags)` mirrors
    /// the change to the phone (MacCloudMetaSync).
    private func onInlineTag(_ tag: String) {
        let t = tag.lowercased()
        if !file.tags.contains(t) { file.tags.append(t) }
    }

    /// Karaoke state for the editor: WHICH word is playing, and a click-a-word → seek
    /// callback. Both come from the shared `KaraokeTrack` — the exact rule the phone runs —
    /// so the highlight sits on the spoken word and clicking word N seeks to that same
    /// word's time, even when copy-edit / name-linking / conversation headers made the shown
    /// word count differ from the timings. The track is cached per body: it is re-aligned
    /// only when the words change, never on the 20 Hz playback tick.
    private var karaokePlayback: BodyTextView.KaraokePlayback {
        let displayedWords = file.bestBodyText.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let track = trackCache.track(displayedWords: displayedWords, timings: file.wordTimings,
                                     duration: effectiveDuration)
        return .init(active: track.activeIndex(at: audio.currentTime)) { wordIndex in
            guard let t = track.seekTime(forWord: wordIndex) else { return }
            audio.seek(to: t)
        }
    }

    /// Resolve an `[[img_NNN]]` marker to its captured photo: the Nth entry in the
    /// file's `image_manifest.json`, under the working folder's `images/` (the ONE
    /// `pf.workingFolder` derivation — captures → path; audio/notes → its parent).
    private func imageURL(_ num: Int) -> URL? {
        guard let folder = file.workingFolder else { return nil }
        return MacNotePhotos.fileURL(number: num, folder: folder)
    }

    // MARK: photos (Q325)

    /// The synced store's context, when Mac CloudKit is on (nil otherwise: a local-only note).
    private var cloudContext: ModelContext? { MemoCloudStore.container?.mainContext }

    /// What a marker whose photo is not on disk stands for: the phone's three states.
    private func photoSlot(_ num: Int) -> NotePhoto.Slot {
        MacNotePhotos.slot(number: num, folder: file.workingFolder,
                           hasAsset: { MacNotePhotos.hasAsset(filename: $0, in: cloudContext) })
    }

    /// A photo added at the caret (paste, drop, Edit > Insert Photo…): its file + manifest, and
    /// the owning memo's manifest + photo row so the phone gets it.
    private func addPhoto(_ data: Data) -> MacNotePhotos.Added? {
        let ctx = cloudContext
        let memo = ctx.flatMap { MacCloudWriteBack.resolve(for: file, in: $0) }
        return MacNotePhotos.add(imageData: data, to: file, memo: memo, context: ctx)
    }

    /// Quick Look's Markup saved into a photo: the phone gets the marked-up file.
    private func photoMarkedUp(_ url: URL) {
        let ctx = cloudContext
        let memo = ctx.flatMap { MacCloudWriteBack.resolve(for: file, in: $0) }
        MacNotePhotos.markupSaved(fileURL: url, memo: memo, context: ctx)
    }

    private var karaoke: some View {
        BodyText.karaoke(file.bestBodyText, currentTime: audio.currentTime,
                         duration: effectiveDuration, timings: file.wordTimings)
            .font(Self.bodyFont)
            .lineSpacing(Self.bodyLineSpacing)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bodyBinding: Binding<String> {
        Binding(
            get: { file.bestBodyText },
            set: { newValue in
                if file.sanitised != nil { file.sanitised = newValue }
                else if file.enhancedCopyedit != nil { file.enhancedCopyedit = newValue }
                else { file.transcript = newValue }
                // Live bidirectional sync (Part B): debounced push of this edit to the phone.
                MacCloudEditSync.shared.note(file)
            }
        )
    }
}

/// Builds styled `Text` from the body — shared so karaoke and the read view use
/// identical typography (no reflow when toggling).
enum BodyText {
    /// Accent-color the `[[wiki links]]` (brackets stay visible — WYSIWYG to export).
    static func styled(_ text: String) -> Text {
        var out = Text("")
        forEachSegment(text) { piece, isLink in
            out = out + (isLink ? Text(piece).foregroundColor(Theme.accent) : Text(piece))
        }
        return out
    }

    /// Karaoke for the read-only path (snapshots, where an ImageRenderer can't host the
    /// NSTextView): the same shared track and the same paint as the phone and the editor —
    /// read words step back, the playing word takes the accent, the rest stay full.
    static func karaoke(_ text: String, currentTime: Double, duration: Double, timings: [WordTiming] = []) -> Text {
        let tokens = tokenize(text)
        let words = tokens.compactMap { $0.isWord ? $0.text : nil }
        let active = KaraokeTrack(displayedWords: words, timings: timings, duration: duration)
            .activeIndex(at: currentTime)
        var out = Text("")
        var wc = -1
        for t in tokens {
            if t.isWord {
                wc += 1
                out = out + Text(t.text).foregroundColor(karaokeColor(KaraokeRole.of(word: wc, active: active)))
            } else {
                out = out + Text(t.text)
            }
        }
        return out
    }

    /// The phone's karaoke colours (`skTextDim` / `skAccent` / `skText`) on the Mac's theme.
    static func karaokeColor(_ role: KaraokeRole) -> Color {
        switch role {
        case .read:     return Theme.textSecondary
        case .playing:  return Theme.accent
        case .upcoming: return Theme.textPrimary
        }
    }

    // MARK: helpers

    private static func forEachSegment(_ text: String, _ body: (String, Bool) -> Void) {
        let ns = text as NSString
        guard let regex = try? NSRegularExpression(pattern: "\\[\\[[^\\]]+\\]\\]") else {
            body(text, false); return
        }
        var last = 0
        regex.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let r = match?.range else { return }
            if r.location > last { body(ns.substring(with: NSRange(location: last, length: r.location - last)), false) }
            body(ns.substring(with: r), true)
            last = r.location + r.length
        }
        if last < ns.length { body(ns.substring(from: last), false) }
    }

    private struct Token { let text: String; let isWord: Bool }

    private static func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var current = ""
        var currentIsSpace: Bool?
        for ch in text {
            let isSpace = ch.isWhitespace
            if currentIsSpace == nil || currentIsSpace == isSpace {
                current.append(ch); currentIsSpace = isSpace
            } else {
                tokens.append(Token(text: current, isWord: !(currentIsSpace ?? true)))
                current = String(ch); currentIsSpace = isSpace
            }
        }
        if !current.isEmpty { tokens.append(Token(text: current, isWord: !(currentIsSpace ?? true))) }
        return tokens
    }
}
