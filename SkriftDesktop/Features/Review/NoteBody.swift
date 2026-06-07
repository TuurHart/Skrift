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

    private static let bodyFont = Font.system(size: 16)
    private static let bodyLineSpacing: CGFloat = 6

    private var karaokeActive: Bool {
        audio.isPlaying && file.durationSeconds > 0 && file.steps.transcribe == .done
    }

    var body: some View {
        Group {
            if karaokeActive {
                karaoke
            } else if interactive {
                editor
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
        // NSTextView bridge: self-sizing + live [[link]] accent styling while editing.
        BodyTextView(text: bodyBinding)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var karaoke: some View {
        BodyText.karaoke(file.bestBodyText, currentTime: audio.currentTime, duration: file.durationSeconds)
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

    /// Karaoke: brighten words up to the proportional play position, dim the rest.
    /// Proportional alignment (copy-edit is minimal, so it lines up within seconds)
    /// mirrors `KaraokeText.tsx`.
    static func karaoke(_ text: String, currentTime: Double, duration: Double) -> Text {
        let tokens = tokenize(text)
        let wordCount = tokens.reduce(0) { $0 + ($1.isWord ? 1 : 0) }
        let frac = duration > 0 ? min(1, max(0, currentTime / duration)) : 0
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
