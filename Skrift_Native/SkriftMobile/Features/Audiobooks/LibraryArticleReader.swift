import SwiftData
import SwiftUI
import UIKit

/// Q355 (mock `mocks/Q351-article-reader.html` "Reader, select a line", signed D195): the article
/// reader a Library tile opens. The stored text, offline, at the reading size of the Aa sheet; select
/// a line and the system menu offers Copy · Highlight · ❝ Add note; highlights of notes made here are
/// yellow and open their note. The dock carries "31% · 29 min left", Aa and "+ Add note".
struct LibraryArticleReaderView: View {
    let book: Audiobook
    /// A jump-back from a note opens the article at the note's word and does NOT move the reading
    /// place (the Q6 rule for every source).
    var jumpBackWord: Int? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage(ReadingPrefs.fontSizeKey) private var fontSize = ReadingPrefs.defaultFontSize
    @AppStorage(ReadingPrefs.lineHeightKey) private var lineHeight = ReadingPrefs.defaultLineHeight
    @StateObject private var model = ArticleReaderModel()
    @State private var doc: ArticleDoc?
    @State private var loading = false
    @State private var capture: ArticleCaptureRequest?
    @State private var showNotes = false
    @State private var showTextSettings = false

    @Query(filter: #Predicate<Memo> { $0.deletedAt == nil },
           sort: \Memo.recordedAt, order: .reverse) private var liveMemos: [Memo]

    private var store: AudiobookLibraryStore { .shared }
    private var current: Audiobook { store.book(id: book.id) ?? book }
    private var hasNotes: Bool { !BookNotesJoin.notes(forBook: book.id, in: liveMemos).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            progressLine
            navBar
            Group {
                if let doc {
                    ArticleNotesFeed(bookID: book.id) { quotes in
                        ArticleTextView(doc: doc, fontSize: fontSize, lineHeight: lineHeight,
                                        noteQuotes: quotes, highlights: ArticleHighlights.load(book.id, store: store),
                                        startWord: jumpBackWord ?? Int(current.position), model: model,
                                        onAddNote: startCapture(selection:),
                                        onHighlight: { text in ArticleHighlights.add(text, bookID: book.id, store: store) },
                                        onOpenNote: openNote)
                    }
                } else {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text(loading ? "Getting the text\u{2026}" : "The text isn\u{2019}t here yet.")
                            .font(.system(size: 13)).foregroundStyle(Color.skTextDim)
                        if !loading {
                            Button("Try again") { Task { await fetchText() } }
                                .font(.system(size: 13, weight: .semibold))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxHeight: .infinity)
            // Q356 (mock `srcnotes`): this article's notes, above the dock. Q381: only when there are
            // notes; with none the row would sit pinned over the text for no reason.
            if hasNotes {
                SourceNotesRow(book: current) { showNotes = true }
                    .padding(.horizontal, 20).padding(.vertical, 8)
            }
            dock
        }
        .background(Color.skBg.ignoresSafeArea())
        .task {
            doc = LibraryArticle.doc(of: book, store: store)
            if doc == nil { await fetchText() }
        }
        .onChange(of: model.topWord) { _, word in
            guard jumpBackWord == nil, model.ready else { return }
            LibraryArticle.savePosition(word: word, bookID: book.id, store: store)
        }
        .sheet(isPresented: $showNotes) {
            BookNotesSheetHost(book: current) { memo in
                showNotes = false
                openNote(memo.id)
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showTextSettings) {
            TextSettingsSheet().presentationDetents([.height(300)])
        }
        .fullScreenCover(item: $capture, onDismiss: { model.clearSelection() }) { request in
            ArticleCaptureView(book: current, request: request) { capture = nil }
        }
        #if DEBUG
        .task { await LibraryArticleDebug.readerAppeared(model: model, capture: $capture, book: book) }
        #endif
        .accessibilityIdentifier("library-article-reader")
    }

    private func fetchText() async {
        loading = true
        defer { loading = false }
        switch await LibraryArticle.complete(current, store: store) {
        case .stored: doc = LibraryArticle.doc(of: book, store: store)
        case .becameNote: dismiss()
        case .unreachable: break
        }
    }

    /// "Add note": the selection, or with none the paragraph at the top of the screen (the mock:
    /// "like the audio capture takes the line you just heard").
    private func startCapture(selection: ArticleSelection?) {
        guard let doc else { return }
        let picked = selection ?? model.paragraphAtTop(of: doc)
        guard let picked, !picked.text.isEmpty else { return }
        capture = ArticleCaptureRequest(quote: picked.text, word: picked.word)
    }

    private func openNote(_ id: UUID) {
        dismiss()
        TabSelectionBridge.shared.select(.notes)
        MemoOpenBridge.shared.open(id)
    }

    // MARK: - Chrome

    /// Q381 (mock `.pbar`): a 2 pt accent line at the very top, as long as the part read.
    private var progressLine: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.skBorder)
                Rectangle().fill(Color.skAccent)
                    .frame(width: geo.size.width * (doc == nil ? 0 : readingBook.progress))
            }
        }
        .frame(height: 2)
        .accessibilityHidden(true)
    }

    private var navBar: some View {
        HStack(spacing: 8) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.skAccentText)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Back to Library")
            .accessibilityIdentifier("library-article-back")
            Text(current.site ?? current.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.skText)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
            Menu {
                Button {
                    var here = current
                    here.position = Double(model.topWord)   // the place on screen, not the kept one
                    if let id = LibraryHatch.sendToNote(book: here) { openNote(id) }
                } label: { Label(LibraryHatch.sendLabel, systemImage: "square.and.pencil") }
                .accessibilityIdentifier("library-article-send-to-note")
                if let raw = current.sourceURL, let url = URL(string: raw) {
                    Button { openURL(url) } label: { Label("Open original page", systemImage: "safari") }
                    ShareLink(item: url) { Label("Share\u{2026}", systemImage: "square.and.arrow.up") }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.skAccentText)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("More")
        }
        .padding(.horizontal, 6)
    }

    private var dock: some View {
        HStack(spacing: 10) {
            Text(doc == nil ? " " : LibraryArticle.dockLine(readingBook))
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(Color.skTextDim)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("library-article-progress")
            Button { showTextSettings = true } label: {
                Text("Aa")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.skTextDim)
                    .frame(width: 40, height: 38)
            }
            .accessibilityLabel("Text size")
            .accessibilityIdentifier("library-article-aa")
            Button { startCapture(selection: model.selection) } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus").font(.system(size: 14, weight: .semibold))
                    Text("Add note").font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(Color.skAccentText)
                .padding(.horizontal, 15).padding(.vertical, 9)
                .frame(minHeight: 38)
                .background(Color.skAccent.opacity(0.18), in: .capsule)
                .overlay(Capsule().strokeBorder(Color.skAccent.opacity(0.25), lineWidth: 0.5))
            }
            .disabled(doc == nil)
            .accessibilityIdentifier("library-article-add-note")
        }
        .padding(.leading, 16).padding(.trailing, 16).padding(.top, 10).padding(.bottom, 10)
        .background(Color.skBg)
        .overlay(alignment: .top) { Rectangle().fill(Color.skBorder).frame(height: 0.5) }
    }

    /// The record with the place on screen, so the dock line moves while he reads.
    private var readingBook: Audiobook {
        var b = current
        if model.ready { b.position = Double(model.topWord) }
        return b
    }
}

/// The jump-back from a note: this article at that word.
struct ArticleJumpRequest: Identifiable {
    let id = UUID()
    let book: Audiobook
    let word: Int
}

/// What the capture screen opens with.
struct ArticleCaptureRequest: Identifiable {
    let id = UUID()
    let quote: String
    let word: Int
}

struct ArticleSelection: Equatable {
    let text: String
    /// Words of the article before it (the capture's place).
    let word: Int
}

/// The quotes of this article's live notes, so the reader paints them yellow and opens them.
private struct ArticleNotesFeed<Content: View>: View {
    let bookID: UUID
    @ViewBuilder let content: ([ArticleTextView.NoteQuote]) -> Content
    @Query(filter: #Predicate<Memo> { $0.deletedAt == nil },
           sort: \Memo.recordedAt, order: .reverse) private var liveMemos: [Memo]

    var body: some View {
        content(BookNotesJoin.notes(forBook: bookID, in: liveMemos).compactMap { memo in
            memo.captureQuote.map { ArticleTextView.NoteQuote(text: $0.displayText, memoID: memo.id) }
        })
    }
}

// MARK: - Highlights without a note

/// "Highlight" (mock callout): a yellow mark that stays in the article, no note made. Local to the
/// device, beside the stored text (`highlights.json`).
@MainActor
enum ArticleHighlights {
    static func url(_ bookID: UUID, store: AudiobookLibraryStore) -> URL {
        store.folder(for: bookID).appendingPathComponent("highlights.json")
    }

    static func load(_ bookID: UUID, store: AudiobookLibraryStore) -> [String] {
        guard let data = try? Data(contentsOf: url(bookID, store: store)) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    static func add(_ text: String, bookID: UUID, store: AudiobookLibraryStore) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        var all = load(bookID, store: store)
        guard !all.contains(t) else { return }
        all.append(t)
        if let data = try? JSONEncoder().encode(all) { try? data.write(to: url(bookID, store: store), options: .atomic) }
    }
}

// MARK: - Reader state

@MainActor
final class ArticleReaderModel: ObservableObject {
    /// The word at the top of the screen (the reading place). Published only on a word change.
    @Published var topWord = 0
    @Published var selection: ArticleSelection?
    weak var textView: UITextView?
    /// False until the view has landed on its start word: nothing is saved before that.
    var ready = false
    /// UTF-16 offset of the first body character and of each body word in the text view's string.
    var wordStarts: [Int] = []
    var wordCount = 0

    func word(atCharacter c: Int) -> Int {
        var lo = 0, hi = wordStarts.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if wordStarts[mid] <= c { lo = mid + 1 } else { hi = mid }
        }
        return max(0, lo - 1)
    }

    func character(ofWord w: Int) -> Int {
        guard !wordStarts.isEmpty else { return 0 }
        return wordStarts[min(max(0, w), wordStarts.count - 1)]
    }

    /// The paragraph holding the top word, as a selection.
    func paragraphAtTop(of doc: ArticleDoc) -> ArticleSelection? {
        var seen = 0
        for block in doc.blocks {
            let n = block.text.split(whereSeparator: \.isWhitespace).count
            if block.kind == .paragraph, topWord < seen + n { return ArticleSelection(text: block.text, word: seen) }
            seen += n
        }
        return doc.blocks.last { $0.kind == .paragraph }.map {
            ArticleSelection(text: $0.text, word: max(0, doc.wordCount - $0.text.split(whereSeparator: \.isWhitespace).count))
        }
    }

    func clearSelection() {
        if let tv = textView { tv.selectedRange = NSRange(location: tv.selectedRange.location, length: 0) }
        selection = nil
    }
}

// MARK: - The text

/// One `UITextView` (not editable, selectable): header + body as attributed text, so selection,
/// the system edit menu and scrolling are the platform's own.
struct ArticleTextView: UIViewRepresentable {
    struct NoteQuote: Equatable {
        let text: String
        let memoID: UUID
    }

    let doc: ArticleDoc
    let fontSize: Double
    let lineHeight: Double
    let noteQuotes: [NoteQuote]
    let highlights: [String]
    let startWord: Int
    let model: ArticleReaderModel
    let onAddNote: (ArticleSelection?) -> Void
    let onHighlight: (String) -> Void
    let onOpenNote: (UUID) -> Void

    static let noteKey = NSAttributedString.Key("skriftNoteID")

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.backgroundColor = .clear
        tv.textContainerInset = UIEdgeInsets(top: 4, left: 22, bottom: 24, right: 22)
        tv.textContainer.lineFragmentPadding = 0
        tv.delegate = context.coordinator
        tv.linkTextAttributes = [.foregroundColor: UIColor(Color.skAccentText)]
        // Q381 (mock `--sel`): the selection and its handles are system blue, not the accent purple.
        tv.tintColor = .systemBlue
        tv.addGestureRecognizer({
            let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
            tap.cancelsTouchesInView = false
            return tap
        }())
        model.textView = tv
        context.coordinator.render(tv)
        // Land on the start word once the text is laid out.
        DispatchQueue.main.async {
            context.coordinator.scroll(tv, toWord: startWord)
            model.topWord = startWord
            model.ready = true
        }
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        let c = context.coordinator
        let changed = c.parent.fontSize != fontSize || c.parent.lineHeight != lineHeight
            || c.parent.noteQuotes != noteQuotes || c.parent.highlights != highlights
        c.parent = self
        guard changed else { return }
        let keep = model.topWord
        c.render(tv)
        DispatchQueue.main.async { c.scroll(tv, toWord: keep) }
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ArticleTextView
        init(_ parent: ArticleTextView) { self.parent = parent }

        func render(_ tv: UITextView) {
            let built = ArticleLayout.build(parent.doc, fontSize: parent.fontSize, lineHeight: parent.lineHeight,
                                            noteQuotes: parent.noteQuotes, highlights: parent.highlights)
            tv.attributedText = built.text
            parent.model.wordStarts = built.wordStarts
            parent.model.wordCount = parent.doc.wordCount
        }

        func scroll(_ tv: UITextView, toWord word: Int) {
            guard word > 0 else { return }
            tv.layoutIfNeeded()
            let c = parent.model.character(ofWord: word)
            let glyphs = tv.layoutManager.glyphRange(forCharacterRange: NSRange(location: c, length: 1), actualCharacterRange: nil)
            let rect = tv.layoutManager.boundingRect(forGlyphRange: glyphs, in: tv.textContainer)
            let maxY = max(0, tv.contentSize.height - tv.bounds.height)
            tv.setContentOffset(CGPoint(x: 0, y: min(maxY, max(0, rect.minY + tv.textContainerInset.top - 16))), animated: false)
        }

        // Reading place: the word at the top; the end counts as read.
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard let tv = scrollView as? UITextView, parent.model.ready else { return }
            let word: Int
            if tv.contentOffset.y + tv.bounds.height >= tv.contentSize.height - 8 {
                word = parent.model.wordCount
            } else {
                let point = CGPoint(x: 1, y: tv.contentOffset.y - tv.textContainerInset.top + 20)
                let glyph = tv.layoutManager.glyphIndex(for: point, in: tv.textContainer)
                word = parent.model.word(atCharacter: tv.layoutManager.characterIndexForGlyph(at: glyph))
            }
            if word != parent.model.topWord { parent.model.topWord = word }
        }

        func textViewDidChangeSelection(_ tv: UITextView) {
            parent.model.selection = selection(in: tv)
        }

        private func selection(in tv: UITextView) -> ArticleSelection? {
            let r = tv.selectedRange
            guard r.length > 0, let first = parent.model.wordStarts.first, r.location >= first else { return nil }
            let text = (tv.text as NSString).substring(with: r).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return ArticleSelection(text: text, word: parent.model.word(atCharacter: r.location))
        }

        /// The mock's callout: Copy · Highlight · ❝ Add note (the system menu, with our items).
        func textView(_ tv: UITextView, editMenuForTextIn range: NSRange,
                      suggestedActions: [UIMenuElement]) -> UIMenu? {
            guard range.length > 0 else { return nil }
            let picked = selection(in: tv)
            let text = (tv.text as NSString).substring(with: range)
            let copy = UIAction(title: "Copy") { _ in UIPasteboard.general.string = text }
            var items: [UIMenuElement] = [copy]
            if let picked {
                items.append(UIAction(title: "Highlight") { [weak self] _ in
                    self?.parent.onHighlight(picked.text)
                    tv.selectedRange = NSRange(location: range.location, length: 0)
                })
                items.append(UIAction(title: "\u{275D} Add note") { [weak self] _ in self?.parent.onAddNote(picked) })
            }
            return UIMenu(children: items)
        }

        /// A tap on a note's highlight opens that note.
        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let tv = gesture.view as? UITextView, tv.selectedRange.length == 0 else { return }
            var point = gesture.location(in: tv)
            point.x -= tv.textContainerInset.left
            point.y -= tv.textContainerInset.top
            let index = tv.layoutManager.characterIndex(for: point, in: tv.textContainer,
                                                        fractionOfDistanceBetweenInsertionPoints: nil)
            guard index < tv.textStorage.length,
                  let id = tv.textStorage.attribute(ArticleTextView.noteKey, at: index, effectiveRange: nil) as? UUID
            else { return }
            parent.onOpenNote(id)
        }
    }
}

/// Builds the reader's attributed text (header + body) and the word index the reading place uses.
enum ArticleLayout {
    struct Built {
        let text: NSAttributedString
        let wordStarts: [Int]
    }

    static func highlightColor() -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(red: 1, green: 0.8, blue: 0, alpha: 0.28)
            : UIColor(red: 1, green: 0.8, blue: 0, alpha: 0.42) }
    }

    static func build(_ doc: ArticleDoc, fontSize: Double, lineHeight: Double,
                      noteQuotes: [ArticleTextView.NoteQuote], highlights: [String]) -> Built {
        let out = NSMutableAttributedString()
        let text = UIColor(Color.skText), dim = UIColor(Color.skTextDim), faint = UIColor(Color.skTextFaint)

        func para(spacing: CGFloat, before: CGFloat = 0, lineHeight: CGFloat? = nil) -> NSParagraphStyle {
            let p = NSMutableParagraphStyle()
            p.paragraphSpacing = spacing
            p.paragraphSpacingBefore = before
            if let lineHeight { p.minimumLineHeight = lineHeight; p.maximumLineHeight = lineHeight }
            return p
        }

        // Header (mock `.rdhead`): site · article, title, byline, date · read time · Original page ↗.
        let kicker = "\(doc.site.uppercased()) \u{00B7} ARTICLE\n"
        out.append(NSAttributedString(string: kicker, attributes: [
            .font: UIFont.monospacedSystemFont(ofSize: 10.5, weight: .semibold), .kern: 0.7,
            .foregroundColor: faint, .paragraphStyle: para(spacing: 6)]))
        out.append(NSAttributedString(string: doc.title + "\n", attributes: [
            .font: UIFont.systemFont(ofSize: 27, weight: .bold), .kern: -0.3,
            .foregroundColor: text, .paragraphStyle: para(spacing: 6, lineHeight: 31)]))
        if let by = [doc.publisher, doc.byline].compactMap({ $0 }).uniqued().joined(separator: " \u{00B7} ").nonEmpty {
            out.append(NSAttributedString(string: by + "\n", attributes: [
                .font: UIFont.systemFont(ofSize: 13), .foregroundColor: dim, .paragraphStyle: para(spacing: 6)]))
        }
        var meta: [String] = []
        if let d = doc.published { meta.append(d.formatted(.dateTime.month(.abbreviated).year())) }
        meta.append("\(doc.readMinutes) min read")
        let metaLine = NSMutableAttributedString(string: meta.joined(separator: "   ") + "   ", attributes: [
            .font: UIFont.systemFont(ofSize: 11.5), .foregroundColor: faint])
        if let url = URL(string: doc.url) {
            metaLine.append(NSAttributedString(string: "Original page \u{2197}", attributes: [
                .font: UIFont.systemFont(ofSize: 11.5, weight: .semibold), .link: url]))
        }
        metaLine.append(NSAttributedString(string: "\n"))
        metaLine.addAttribute(.paragraphStyle, value: para(spacing: 22), range: NSRange(location: 0, length: metaLine.length))
        out.append(metaLine)

        // Body (mock `.rdbody`): the Aa size and line height; paragraphs 0.9 em apart, headings 1.06 em.
        let size = CGFloat(fontSize)
        let body = UIFont.systemFont(ofSize: size)
        let head = UIFont.systemFont(ofSize: size * 1.06, weight: .bold)
        let lh = size * CGFloat(lineHeight)
        let bodyStart = out.length
        for (i, block) in doc.blocks.enumerated() {
            let last = i == doc.blocks.count - 1
            let s = block.text + (last ? "" : "\n")
            if block.kind == .heading {
                out.append(NSAttributedString(string: s, attributes: [
                    .font: head, .foregroundColor: text,
                    .paragraphStyle: para(spacing: size * 0.5, before: i == 0 ? 0 : size * 0.7, lineHeight: size * 1.06 * 1.35)]))
            } else {
                out.append(NSAttributedString(string: s, attributes: [
                    .font: body, .foregroundColor: text, .paragraphStyle: para(spacing: size * 0.9, lineHeight: lh)]))
            }
        }

        // Yellow: notes first (they open their note), then plain highlights.
        let ns = out.string as NSString
        let bodyRange = NSRange(location: bodyStart, length: ns.length - bodyStart)
        var glyphs: [(at: Int, memo: UUID)] = []
        for q in noteQuotes {
            let r = ns.range(of: q.text, options: [], range: bodyRange)
            guard r.location != NSNotFound else { continue }
            out.addAttributes([.backgroundColor: highlightColor(), ArticleTextView.noteKey: q.memoID], range: r)
            glyphs.append((r.location + r.length, q.memoID))
        }
        for h in highlights {
            let r = ns.range(of: h, options: [], range: bodyRange)
            if r.location != NSNotFound { out.addAttribute(.backgroundColor, value: highlightColor(), range: r) }
        }
        // Q381 (mock `.hlq`): a ❝ after the end of a noted sentence, accent colour, 0.8 em, no
        // background; it opens the note too. Hair space (not a word break) keeps the word count.
        for g in glyphs.sorted(by: { $0.at > $1.at }) {
            out.insert(NSAttributedString(string: "\u{200A}\u{275D}", attributes: [
                .font: UIFont.systemFont(ofSize: size * 0.8, weight: .black),
                .foregroundColor: UIColor(Color.skAccentText),
                ArticleTextView.noteKey: g.memo]), at: g.at)
        }
        let final = out.string as NSString

        // Word starts in the body (whitespace-split, the same count `ArticleDoc.wordCount` makes).
        var starts: [Int] = []
        var inWord = false
        for i in bodyStart..<final.length {
            let ch = final.character(at: i)
            let space = ch == 32 || ch == 10 || ch == 9 || ch == 13 || ch == 0xA0
            if !space, !inWord { starts.append(i) }
            inWord = !space
        }
        return Built(text: out, wordStarts: starts)
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

private extension Array where Element == String {
    func uniqued() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted }
    }
}

// MARK: - Capture: the selection + his voice

/// "Add note" (mock "Add note", pick 2): the selection is the quote, word for word (no sentence
/// builder: the selection handles chose the words), a rating, and "Record your thoughts". Same frame
/// as `PDFCaptureView` / `MergedCaptureView` so the captures read the same.
struct ArticleCaptureView: View {
    let book: Audiobook
    let request: ArticleCaptureRequest
    let onFinish: () -> Void

    @State private var significance: Double = 0
    @State private var createdMemoID: UUID?
    @State private var showRamble = false
    @State private var rambleSaved = false

    private var site: String { book.site ?? "" }

    var body: some View {
        VStack(spacing: 0) {
            header
            PhoneRatingRow(value: $significance)
                .padding(.horizontal, 16)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 2) {
                Text("Your highlight.").font(.system(size: 14.5, weight: .bold)).foregroundStyle(Color.skText)
                Text("This is the quote, word for word. Say what you think next.")
                    .font(.system(size: 11.5)).foregroundStyle(Color.skTextDim)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 8)
            quoteBlock
            linkBack
            Text("Wrong words? \u{2715}, then drag the selection handles in the article.")
                .font(.system(size: 11))
                .foregroundStyle(Color.skTextFaint)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18).padding(.top, 6)
            Spacer(minLength: 0)
            recordBar
        }
        .background(Color.skBg.ignoresSafeArea())
        .fullScreenCover(isPresented: $showRamble, onDismiss: {
            // Bailed before recording: a quote alone is not a capture, drop it (same as audiobooks).
            if !rambleSaved, let id = createdMemoID, let memo = NotesRepository.shared.memo(id: id) {
                NotesRepository.shared.permanentlyDelete(memo)
            }
            onFinish()
        }) {
            if let id = createdMemoID {
                RecordView(onSaved: { _ in rambleSaved = true }, appendTo: id)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("library-article-capture")
    }

    private var header: some View {
        HStack(spacing: 9) {
            Text("\u{275D}")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(
                    LinearGradient(colors: [Color(hex: 0x8e7dff), Color(hex: 0x6a59ef)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: .rect(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text("Add note")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.skText)
                Text(site.isEmpty ? book.title : "\(book.title) \u{00B7} \(site)")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.skTextFaint)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { onFinish() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.skTextDim)
                    .frame(width: 24, height: 24)
                    .background(Color.skElev, in: .circle)
            }
            .accessibilityLabel("Cancel")
            .accessibilityIdentifier("library-article-capture-close")
        }
        .padding(.horizontal, 16).padding(.top, 15).padding(.bottom, 12)
    }

    /// Q381 (mock `.linkback`): the boxed line under the quote: the place, and what the vault gets.
    private var linkBack: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\u{2197}")
            (Text("Links back to the article").fontWeight(.semibold).foregroundColor(Color.skText)
             + Text(" at \(LibraryArticle.percent(word: request.word, of: book))%. The vault gets the title, the site and the URL."))
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 12))
        .foregroundStyle(Color.skTextDim)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.skSurface, in: .rect(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.skBorder, lineWidth: 0.5))
        .padding(.horizontal, 18).padding(.top, 14)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("library-article-linkback")
    }

    /// Accent bar, italic, borderless: the quote idiom (no box on shared input). Fixed text.
    private var quoteBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(request.quote)
                .font(.system(size: 15.5).italic())
                .foregroundStyle(Color.skText.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("library-article-quote")
            (Text("\u{2014} ") + Text(book.title).italic() + Text(site.isEmpty ? "" : ", \(site)"))
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Color.skTextDim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 14)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(Color.skAccent.opacity(0.65)).frame(width: 3)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
    }

    private var recordBar: some View {
        RecordThoughtsButton { recordThoughts() }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 18)
        .accessibilityIdentifier("library-article-capture-record")
    }

    private func recordThoughts() {
        guard createdMemoID == nil else { return }
        guard let id = LibraryArticle.saveCapture(quote: request.quote, book: book, wordOffset: request.word,
                                                  significance: significance) else { return }
        Haptics.success()
        createdMemoID = id
        showRamble = true
    }
}

// MARK: - The "Article" door: paste a link

/// The empty Library's "Article" door and the + menu's "Article link…": paste a link, Skrift fetches
/// it once. Article text: a source. No article text: a note, and the toast says so.
struct ArticleLinkSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @State private var working = false

    private var trimmed: String { link.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add an article")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.skText)
            Text("Paste a link. Skrift saves the text for offline reading. A page with no article text is saved as a note.")
                .font(.system(size: 12.5))
                .foregroundStyle(Color.skTextDim)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                TextField("https://\u{2026}", text: $link)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .font(.system(size: 14))
                    .padding(.horizontal, 12).frame(height: 40)
                    .background(Color.skSurface, in: .rect(cornerRadius: 10, style: .continuous))
                    .accessibilityIdentifier("article-link-field")
                Button("Paste") { link = UIPasteboard.general.string ?? link }
                    .font(.system(size: 13, weight: .semibold))
            }
            Button { add() } label: {
                HStack {
                    if working { ProgressView().tint(.white) }
                    Text(working ? "Getting the text\u{2026}" : "Add to Library")
                }
                .font(.system(size: 14.5, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 44)
                .background(Color.skAccent, in: .rect(cornerRadius: 12, style: .continuous))
            }
            .disabled(trimmed.isEmpty || working)
            .opacity(trimmed.isEmpty ? 0.5 : 1)
            .accessibilityIdentifier("article-link-add")
            Spacer(minLength: 0)
        }
        .padding(20)
        .presentationDetents([.height(280)])
        .background(Color.skBg)
    }

    private func add() {
        var raw = trimmed
        if !raw.contains("://") { raw = "https://" + raw }
        working = true
        Task {
            await LibraryArticle.drain(entryID: UUID(), url: raw, title: nil,
                                       store: .shared, repository: .shared)
            working = false
            dismiss()
        }
    }
}

// MARK: - Host: reader, door sheet, toast, waiting sources

/// Q355: everything the Library tab needs for articles in ONE modifier (like `LibraryPDFHost`): the
/// reader a tile opens, the paste-a-link sheet, the "No article text on that page" toast, and a
/// retry of sources whose text has not arrived (offline at share time, or synced from a device).
struct LibraryArticleHost: ViewModifier {
    @Binding var reader: Audiobook?
    @Binding var showLinkSheet: Bool
    @ObservedObject private var arrival = LibraryArticleArrival.shared
    @State private var shown: LibraryArticleArrival.Arrival?

    func body(content: Content) -> some View {
        content
            .background {
                Color.clear
                    .fullScreenCover(item: $reader) { book in LibraryArticleReaderView(book: book) }
                    .sheet(isPresented: $showLinkSheet) { ArticleLinkSheet() }
            }
            .overlay(alignment: .bottom) {
                if let shown {
                    LibraryArticleToast { openNote(shown) }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.22), value: shown)
            .onChange(of: arrival.pending) { _, next in if let next { show(next) } }
            .onAppear { if let next = arrival.pending { show(next) } }
            .task { await retryWaiting() }
            #if DEBUG
            .task { LibraryArticleDebug.run(reader: $reader) }
            #endif
    }

    private func show(_ next: LibraryArticleArrival.Arrival) {
        shown = next
        arrival.clear()
        Task {
            try? await Task.sleep(for: .seconds(8))   // the mock's 8 s
            if shown == next { shown = nil }
        }
    }

    private func openNote(_ arrival: LibraryArticleArrival.Arrival) {
        shown = nil
        TabSelectionBridge.shared.select(.notes)
        MemoOpenBridge.shared.open(arrival.memoID)
    }

    @MainActor
    private func retryWaiting() async {
        let store = AudiobookLibraryStore.shared
        for book in store.books where LibraryArticle.isFetching(book, store: store) {
            _ = await LibraryArticle.complete(book, store: store)
        }
    }
}

extension View {
    func libraryArticles(reader: Binding<Audiobook?>, showLinkSheet: Binding<Bool>) -> some View {
        modifier(LibraryArticleHost(reader: reader, showLinkSheet: showLinkSheet))
    }
}

/// The in-app toast with an action (mock `.itoast`), the PDF toast's frame.
struct LibraryArticleToast: View {
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(LibraryArticle.noArticleToast)
                .font(.system(size: 13.5, weight: .bold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onOpen) {
                Text(LibraryArticle.noArticleAction)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(hex: 0xc9bfff))
                    .padding(.horizontal, 8)
                    .frame(minHeight: 40)
            }
            .accessibilityIdentifier("library-article-toast-action")
        }
        .padding(.leading, 14).padding(.trailing, 10).padding(.vertical, 10)
        .background(Color(hex: 0x1c1c1e), in: .rect(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 12, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("library-article-toast")
    }
}

#if DEBUG
/// Screenshot hooks (Simulator only, no network): `-seedLibraryArticle` puts the mock's two articles on
/// the shelf, `-showArticleReader` opens "Local-first software" with the mock's sentence selected,
/// `-showArticleCapture` opens Add note on it, `-showArticleToast` raises the no-article toast.
@MainActor
enum LibraryArticleDebug {
    static let quote = "Your data should live on your own device first, and the network should only carry copies."

    static func run(reader: Binding<Audiobook?>) {
        let flags = LaunchFlags.self
        guard flags.seedLibraryArticle || flags.showArticleReader || flags.showArticleCapture || flags.showArticleToast
                || flags.showArticleNote
        else { return }
        let store = AudiobookLibraryStore.shared
        var lfs = store.books.first { $0.title == "Local-first software" }
        if lfs == nil { lfs = LibraryArticle.add(localFirst, store: store) }
        if !store.books.contains(where: { $0.title == "The Web We Lost" }) {
            var web = LibraryArticle.add(webWeLost, store: store)
            web.position = web.duration
            store.update(web)
        }
        if flags.showArticleReader || flags.showArticleCapture { reader.wrappedValue = lfs }
        if flags.showArticleToast { LibraryArticleArrival.shared.post(memoID: UUID()) }
        if flags.showArticleNote, let book = lfs, let at = localFirst.wordOffset(of: quote),
           let id = LibraryArticle.saveCapture(quote: quote, book: book, wordOffset: at, significance: 0) {
            TabSelectionBridge.shared.select(.notes)
            MemoOpenBridge.shared.open(id)
        }
    }

    static func readerAppeared(model: ArticleReaderModel, capture: Binding<ArticleCaptureRequest?>, book: Audiobook) async {
        guard LaunchFlags.showArticleReader || LaunchFlags.showArticleCapture else { return }
        try? await Task.sleep(for: .milliseconds(600))
        guard let tv = model.textView else { return }
        let r = (tv.text as NSString).range(of: quote)
        guard r.location != NSNotFound else { return }
        if LaunchFlags.showArticleCapture {
            capture.wrappedValue = ArticleCaptureRequest(quote: quote, word: model.word(atCharacter: r.location))
        } else {
            tv.becomeFirstResponder()
            tv.selectedRange = r
            // `-scrollArticleReader`: a screenshot with the reading place moved (the progress line).
            if ProcessInfo.processInfo.arguments.contains("-scrollArticleReader") {
                tv.setContentOffset(CGPoint(x: 0, y: 150), animated: false)
            }
        }
    }

    /// The mock's example text (written for the Q351 mock, not the real article's words).
    static var localFirst: ArticleDoc {
        ArticleDoc(url: "https://www.inkandswitch.com/local-first/", title: "Local-first software",
                   site: "inkandswitch.com", publisher: "Ink & Switch",
                   byline: "Martin Kleppmann, Adam Wiggins, Peter van Hardenberg, Mark McGranaghan",
                   published: ISO8601DateFormatter().date(from: "2019-04-15T09:00:00Z"),
                   blocks: [
                    .init(kind: .heading, text: "Why the cloud feels fragile"),
                    .init(kind: .paragraph, text: "Most apps keep your work on someone else\u{2019}s server and hand you a view of it. When the server goes away, so does the work, however carefully you made it. That trade made sense when phones were slow and storage was dear."),
                    .init(kind: .paragraph, text: "Neither is true any more. \(quote) Then the app works on a plane, in a tunnel, or ten years after the company folds."),
                    .init(kind: .heading, text: "What it asks of the software"),
                    .init(kind: .paragraph, text: "Two devices will edit the same thing while apart, so the app has to merge without asking you to pick a winner. That is the hard part, and most of this piece is about it. The rest is ordinary craft: fast saves, plain files, and an export you can read without the app."),
                    .init(kind: .paragraph, text: "None of this is free. Sync becomes the product\u{2019}s spine, and every new feature has to say how it merges. We think the cost is worth it for anything a person means to keep."),
                   ])
    }

    static var webWeLost: ArticleDoc {
        ArticleDoc(url: "https://anildash.com/2012/12/13/the_web_we_lost/", title: "The Web We Lost",
                   site: "anildash.com", publisher: nil, byline: "Anil Dash", published: nil,
                   blocks: [.init(kind: .paragraph, text: "There was a time when the pages you made were yours in a plain and boring way."),
                            .init(kind: .paragraph, text: "People linked to each other by hand, and a link was a small act of trust."),
                            .init(kind: .paragraph, text: "The good news is that the old tools still work.")])
    }
}
#endif
