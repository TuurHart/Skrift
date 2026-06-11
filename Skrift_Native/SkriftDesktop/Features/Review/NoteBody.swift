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
    /// Inline name-disambiguation state, present only while the note has ambiguous
    /// names. Passed into the editor so mentions are marked + clickable in place (R3).
    var resolver: InlineResolverModel? = nil
    /// Click an already-linked `[[Name]]` → unlink popover (passed through to the
    /// editor; nil = linked names aren't clickable).
    var onUnlink: ((String, String, BodyTextView.UnlinkScope) -> Void)? = nil

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
                BodyText.styled(file.bestBodyText)
                    .font(Self.bodyFont)
                    .lineSpacing(Self.bodyLineSpacing)
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var editor: some View {
        // NSTextView bridge: self-sizing + live [[link]] accent styling + inline
        // image thumbnails + inline name resolution (R3) + in-place karaoke (recolor
        // the same view + click a word to seek — no reflow, no renderer swap).
        BodyTextView(
            text: bodyBinding, imageURL: imageURL, onAddName: onAddName, onAddAlias: onAddAlias,
            resolver: karaokeActive ? nil : resolver,
            onUnlink: karaokeActive ? nil : onUnlink,
            karaoke: karaokeActive ? karaokePlayback : nil,
            refresh: resolver?.styleVersion ?? 0
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Karaoke state for the editor: how far through the words to brighten, and a
    /// click-a-word → seek callback (proportional to the audio, approximate — matches
    /// the documented behavior).
    private var karaokePlayback: BodyTextView.KaraokePlayback {
        let frac = BodyText.karaokeFraction(
            currentTime: audio.currentTime, duration: effectiveDuration, timings: file.wordTimings)
        return .init(fraction: frac) { wordFraction in
            audio.seek(to: wordFraction * effectiveDuration)
        }
    }

    /// Resolve an `[[img_NNN]]` marker to its captured photo: the Nth entry in the
    /// file's `image_manifest.json`, under the working folder's `images/`.
    private func imageURL(_ num: Int) -> URL? {
        guard !file.path.isEmpty else { return nil }
        let folder = URL(fileURLWithPath: file.path).deletingLastPathComponent()
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("image_manifest.json")),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              num >= 1, num <= arr.count,
              let filename = arr[num - 1]["filename"] as? String else { return nil }
        let url = folder.appendingPathComponent("images").appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
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
    static func karaokeFraction(currentTime: Double, duration: Double, timings: [WordTiming]) -> Double {
        if timings.isEmpty {
            return duration > 0 ? min(1, max(0, currentTime / duration)) : 0
        }
        var started = 0
        for t in timings { if t.start <= currentTime { started += 1 } else { break } }
        return min(1, Double(started) / Double(max(1, timings.count)))
    }

    static func karaoke(_ text: String, currentTime: Double, duration: Double, timings: [WordTiming] = []) -> Text {
        let tokens = tokenize(text)
        let wordCount = tokens.reduce(0) { $0 + ($1.isWord ? 1 : 0) }
        let frac = karaokeFraction(currentTime: currentTime, duration: duration, timings: timings)
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
