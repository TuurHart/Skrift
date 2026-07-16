import SwiftUI

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
    /// Memo↔memo link chip clicked → open that memo (nil = inert chips).
    var onOpenMemoLink: ((UUID) -> Void)? = nil
    /// The `[[` picker's link targets (lazily evaluated; empty = picker disabled).
    var linkCandidates: () -> [MemoLinkCandidate] = { [] }
    /// Resolve a link target's CURRENT title so chips don't show a stale snapshot.
    var linkTitle: (UUID) -> String? = { _ in nil }

    private static let bodyFont = Font.system(size: 16)
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
    }

    /// Read/snapshot body. An audiobook capture renders its leading C1 quote block
    /// styled (italic + accent bar + plain-text attribution caption from the C2
    /// fields) above the ramble — presentation only, the stored text keeps the raw
    /// "> " lines (and the real `[[Author]]` stays export-time in the Compiler).
    @ViewBuilder private var readBody: some View {
        if let book = file.bookCapture,
           let split = QuoteProtection.splitLeadingQuote(file.bestBodyText) {
            VStack(alignment: .leading, spacing: 18) {
                quoteCard(split.quote, attribution: book.attribution)
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

    /// The styled quote block (mocks/audiobook-capture.html `.quoteblock`): italic
    /// quote lines behind an accent left bar, attribution caption underneath. The
    /// "> " markers stay visible — same WYSIWYG-to-export rule as the literal
    /// `[[brackets]]`.
    private func quoteCard(_ quote: String, attribution: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            BodyText.styled(quote)
                .font(Self.bodyFont.italic())
                .lineSpacing(Self.bodyLineSpacing)
                .foregroundStyle(Theme.textPrimary)
            Text(attribution)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 14)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.25)
                .fill(Theme.accent.opacity(0.6))
                .frame(width: 2.5)
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
            onOpenMemoLink: karaokeActive ? nil : onOpenMemoLink,
            linkCandidates: karaokeActive ? { [] } : linkCandidates,
            linkTitle: linkTitle,
            tagCandidates: karaokeActive ? { [] } : tagCandidates,
            onInlineTag: onInlineTag,
            karaoke: karaokeActive ? karaokePlayback : nil,
            quoteAttribution: file.bookCapture?.attribution
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

    /// Karaoke state for the editor: how far through the words to brighten, and a
    /// click-a-word → seek callback. The SHOWN words are aligned to the raw word-timings
    /// ONCE (C3), so the highlight sits on the spoken word AND clicking word N seeks to
    /// that same word's real time — even when copy-edit / name-linking / conversation
    /// headers made the displayed word count differ from the timings. Falls back to a
    /// time proportion only when timings are absent (e.g. demo notes).
    private var karaokePlayback: BodyTextView.KaraokePlayback {
        let timings = file.wordTimings
        let duration = effectiveDuration
        let displayedWords = file.bestBodyText.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let times = timings.isEmpty ? [] : Karaoke.wordTimes(displayedWords: displayedWords, timings: timings)
        let frac: Double = times.isEmpty
            ? BodyText.karaokeFraction(currentTime: audio.currentTime, duration: duration, timings: timings)
            : min(1, Double(Karaoke.activeCount(times: times, currentTime: audio.currentTime)) / Double(max(1, displayedWords.count)))
        return .init(fraction: frac) { wordIndex in
            let target: Double
            if wordIndex >= 0, wordIndex < times.count {
                target = times[wordIndex]                       // aligned time of the SHOWN word
            } else if wordIndex >= 0, wordIndex < timings.count {
                target = timings[wordIndex].start               // fallback: raw index
            } else if timings.count > 1 {
                target = duration * Double(wordIndex) / Double(timings.count - 1)
            } else {
                target = 0
            }
            audio.seek(to: max(0, min(target, duration)))
        }
    }

    /// Resolve an `[[img_NNN]]` marker to its captured photo: the Nth entry in the
    /// file's `image_manifest.json`, under the working folder's `images/` (the ONE
    /// `pf.workingFolder` derivation — captures → path; audio/notes → its parent).
    private func imageURL(_ num: Int) -> URL? {
        guard let folder = file.workingFolder,
              let data = try? Data(contentsOf: folder.appendingPathComponent("image_manifest.json")),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              num >= 1, num <= arr.count,
              let filename = arr[num - 1]["filename"] as? String else { return nil }
        let imageFile = folder.appendingPathComponent("images").appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: imageFile.path) ? imageFile : nil
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

    /// Karaoke: brighten words up to the play position, dim the rest. When real
    /// word `timings` are present, the highlight tracks actual speech cadence
    /// (counting how many spoken words have started by `currentTime`) and maps that
    /// proportionally onto the body words — exact when the body equals the
    /// transcript, graceful when the copy-edit shifted words. Falls back to a pure
    /// time/duration proportion when timings are absent (demo/pre-A2 notes).
    /// Fraction 0…1 of the body's words to brighten at `currentTime`. With real word
    /// `timings` it counts how many spoken words have started (tracks speech cadence);
    /// otherwise it's a pure time/duration proportion. Shared by the SwiftUI read path
    /// and the NSTextView in-place karaoke, so they highlight identically.
    static func karaokeFraction(currentTime: Double, duration: Double, timings: [WordTiming],
                                displayedWords: [String]? = nil) -> Double {
        if timings.isEmpty {
            return duration > 0 ? min(1, max(0, currentTime / duration)) : 0
        }
        // C3: when the SHOWN words are known, align them to the raw timings so the
        // highlight tracks the actual spoken word (not a count the copy-edit shifted).
        if let dw = displayedWords, !dw.isEmpty {
            let times = Karaoke.wordTimes(displayedWords: dw, timings: timings)
            if !times.isEmpty {
                return min(1, Double(Karaoke.activeCount(times: times, currentTime: currentTime)) / Double(dw.count))
            }
        }
        // Fallback (no displayed-word list, e.g. a caller that only has the timings):
        // raw-progress proportion — how many spoken words have started.
        var started = 0
        for t in timings { if t.start <= currentTime { started += 1 } else { break } }
        return min(1, Double(started) / Double(max(1, timings.count)))
    }

    static func karaoke(_ text: String, currentTime: Double, duration: Double, timings: [WordTiming] = []) -> Text {
        let tokens = tokenize(text)
        let words = tokens.compactMap { $0.isWord ? $0.text : nil }
        let wordCount = words.count
        let frac = karaokeFraction(currentTime: currentTime, duration: duration, timings: timings,
                                   displayedWords: words)
        let active = Int(frac * Double(max(1, wordCount)))
        var out = Text("")
        var wc = -1
        for t in tokens {
            if t.isWord {
                wc += 1
                let bright = wc <= active
                out = out + Text(t.text).foregroundColor(bright ? Theme.textPrimary : Theme.textPrimary.opacity(0.4))
            } else {
                out = out + Text(t.text).foregroundColor(Theme.textPrimary.opacity(0.4))
            }
        }
        return out
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
