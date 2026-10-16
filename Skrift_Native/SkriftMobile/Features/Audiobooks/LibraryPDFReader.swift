import PDFKit
import SwiftUI
import UIKit

/// Q354 (Q6 mock "PDF reader", D135): the PDF reader a Library tile opens. PDFKit with text
/// selection, the page kept on the book, and "Add note" in two places like the mock: a callout
/// over the selection (Copy · Highlight · Add note) and a chip in the dock beside "p. 4 of 18".
/// "Add note" opens `PDFCaptureView` (the quote + his voice).
///
/// Q404 (D207): a PDF with a usable text layer opens as a reading view (the page's text reflowed
/// in the article reader's text view, at the Aa size), with "Original page" in the dock to flip to
/// the real page (remembered per PDF). Q461: a scan, or a poor extraction, is read by on-device
/// text recognition first ("Reading the scan…" while it runs, cached beside the item).
struct LibraryPDFReaderView: View {
    let book: Audiobook
    /// A jump-back from a note opens the page the note came from and does NOT move the book's own
    /// place (the Q6 mock's rule for every source).
    var jumpBackPage: Int? = nil

    @Environment(\.dismiss) private var dismiss
    @AppStorage(ReadingPrefs.fontSizeKey) private var fontSize = ReadingPrefs.defaultFontSize
    @AppStorage(ReadingPrefs.lineHeightKey) private var lineHeight = ReadingPrefs.defaultLineHeight
    @StateObject private var model = PDFReaderModel()
    @StateObject private var textModel = ArticleReaderModel()
    @State private var capture: PDFCaptureRequest?
    @State private var showNotes = false
    @State private var showTextSettings = false
    @State private var readingDoc: ArticleDoc?
    @State private var checked = false
    /// Q461: on-device text recognition is reading a scanned page ("Reading the scan…").
    @State private var scanning = false
    @State private var mode: PDFReaderMode.Mode = .original
    /// The page to open on after a flip between the reading view and the real page.
    @State private var resumePage: Int?
    @State private var highlights: [SourceHighlight] = []

    private var store: AudiobookLibraryStore { .shared }
    private var url: URL { store.audioURL(of: book, fileIndex: 0) }
    private var startPage: Int { resumePage ?? jumpBackPage ?? LibraryPDF.page(of: store.book(id: book.id) ?? book) }

    var body: some View {
        VStack(spacing: 0) {
            navBar
            ZStack {
                if !checked {
                    if scanning { PDFScanProgressLine() } else { Color.clear }
                } else if mode == .reading, let doc = readingDoc {
                    ArticleTextView(doc: doc, fontSize: fontSize, lineHeight: lineHeight, noteQuotes: [],
                                    highlights: highlights,
                                    startWord: LibraryPDF.startWord(page: startPage, in: doc), model: textModel,
                                    header: false, serifBody: true,
                                    onAddNote: { picked in startCapture(reading: picked, doc: doc) },
                                    onHighlight: { picked in
                                        addHighlight(picked.text, page: LibraryPDF.page(atWord: picked.word, in: doc),
                                                     word: picked.word)
                                    },
                                    onRemoveHighlight: removeHighlight,
                                    onOpenNote: { _ in })
                        .accessibilityIdentifier("library-pdf-reading-view")
                } else {
                    PDFKitReader(url: url, startPage: startPage, model: model)
                        .ignoresSafeArea(edges: .horizontal)
                    if let selection = model.selection {
                        SelectionCallout(anchor: selection.rect, items: calloutItems(for: selection))
                    } else if let tapped = model.tappedHighlight {
                        SelectionCallout(anchor: tapped.rect, items: [
                            SelectionCallout.Item(title: SourceMenu.copy, id: "library-pdf-highlight-copy") {
                                UIPasteboard.general.string = tapped.text
                                model.tappedHighlight = nil
                            },
                            SelectionCallout.Item(title: SourceMenu.removeHighlight, id: "library-pdf-highlight-remove") {
                                removeHighlight(tapped.id)
                                model.tappedHighlight = nil
                            },
                        ])
                    }
                }
            }
            .frame(maxHeight: .infinity)
            // Q356 (mock `readerScreen` → `srcNotesRow`): this PDF's notes, above the dock.
            SourceNotesRow(book: book) { showNotes = true }
                .padding(.horizontal, 20).padding(.vertical, 8)
            dock
        }
        .background(Color.skBg.ignoresSafeArea())
        .task { await open() }
        .sheet(isPresented: $showNotes) {
            BookNotesSheetHost(book: book) { memo in
                showNotes = false
                dismiss()
                TabSelectionBridge.shared.select(.notes)
                MemoOpenBridge.shared.open(memo.id)
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showTextSettings) {
            TextSettingsSheet().presentationDetents([.height(300)])
        }
        .onChange(of: model.page) { _, page in
            if LibraryPDF.savesPage(jumpBackPage: jumpBackPage, ready: model.ready) {
                LibraryPDF.savePage(page, bookID: book.id, store: store)
            }
        }
        // The reading view's place, as a page: the word at the top is on that page.
        .onChange(of: textModel.topWord) { _, word in
            guard mode == .reading, textModel.ready, let doc = readingDoc else { return }
            let page = LibraryPDF.page(atWord: word, in: doc)
            model.ready = true
            if model.page != page { model.page = page }
        }
        .fullScreenCover(item: $capture, onDismiss: { model.clearSelection(); textModel.clearSelection() }) { request in
            PDFCaptureView(book: book, request: request) { capture = nil }
        }
        .accessibilityIdentifier("library-pdf-reader")
    }

    /// The text layer is read off the main thread; the reader then opens in the reading view
    /// (when the text is usable and he has not chosen the real page for this PDF) or on the page.
    private func open() async {
        highlights = LibraryHighlights.list(book.id, store: store)
        model.highlights = highlights
        model.pageCount = max(1, LibraryPDF.pageCount(of: book))
        model.page = startPage
        let file = url
        let cache = LibraryPDF.scanCacheURL(for: file)
        scanning = await Task.detached(priority: .userInitiated) { LibraryPDF.needsRecognition(url: file, cache: cache) }.value
        let doc = await Task.detached(priority: .userInitiated) { LibraryPDF.readingDoc(url: file, scanCache: cache) }.value
        scanning = false
        readingDoc = doc
        mode = PDFReaderMode.resolved(hasReadingView: doc != nil,
                                      prefersOriginal: PDFReaderMode.prefersOriginal(bookID: book.id))
        checked = true
        #if DEBUG
        if mode == .reading { await LibraryPDFDebug.readingAppeared(model: textModel) }
        #endif
    }

    /// The mock's callout over a selection on the real page: Copy · Highlight · ❝ Add note
    /// (Remove highlight instead of Highlight when the selection sits in one).
    private func calloutItems(for selection: PDFReaderModel.Selection) -> [SelectionCallout.Item] {
        var items = [SelectionCallout.Item(title: SourceMenu.copy, id: "library-pdf-copy") { model.copySelection() }]
        if let inside = model.highlightID(containing: selection) {
            items.append(SelectionCallout.Item(title: SourceMenu.removeHighlight, id: "library-pdf-remove-highlight") {
                removeHighlight(inside)
                model.clearSelection()
            })
        } else {
            items.append(SelectionCallout.Item(title: SourceMenu.highlight, id: "library-pdf-highlight") {
                addHighlight(selection.text, page: selection.page, word: 0)
                model.clearSelection()
            })
        }
        items.append(SelectionCallout.Item(title: SourceMenu.addNote, id: "library-pdf-callout-add-note", accent: true) {
            startCapture()
        })
        return items
    }

    private func toggleMode() {
        resumePage = model.page
        model.ready = false
        textModel.ready = false
        model.clearSelection()
        model.tappedHighlight = nil
        textModel.clearSelection()
        mode = mode == .reading ? .original : .reading
        PDFReaderMode.setPrefersOriginal(mode == .original, bookID: book.id)
    }

    private func addHighlight(_ text: String, page: Int, word: Int) {
        LibraryHighlights.add(text, page: page, word: word, bookID: book.id, store: store)
        highlights = LibraryHighlights.list(book.id, store: store)
        model.highlights = highlights
    }

    private func removeHighlight(_ id: UUID) {
        LibraryHighlights.remove(id, bookID: book.id, store: store)
        highlights = LibraryHighlights.list(book.id, store: store)
        model.highlights = highlights
    }

    private func startCapture() {
        if mode == .reading, let doc = readingDoc {
            startCapture(reading: textModel.selection ?? textModel.paragraphAtTop(of: doc), doc: doc)
            return
        }
        capture = PDFCaptureRequest(quote: model.selection?.text ?? "", page: model.page)
    }

    /// From the reading view: the selection (or the paragraph at the top), with the page it is on.
    private func startCapture(reading picked: ArticleSelection?, doc: ArticleDoc) {
        guard let picked, !picked.text.isEmpty else {
            capture = PDFCaptureRequest(quote: "", page: model.page)
            return
        }
        capture = PDFCaptureRequest(quote: picked.text, page: LibraryPDF.page(atWord: picked.word, in: doc))
    }

    // MARK: - Chrome

    private var navBar: some View {
        HStack(spacing: 8) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.skAccentText)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Back to Library")
            .accessibilityIdentifier("library-pdf-back")
            Text(book.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.skText)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
            Menu {
                // Q356 (mock `srcMenu`): the PDF stays here; a new note links back to this page.
                Button {
                    var here = store.book(id: book.id) ?? book
                    here.position = Double(model.page)   // the page on screen, not the kept one
                    if let id = LibraryHatch.sendToNote(book: here) {
                        dismiss()
                        TabSelectionBridge.shared.select(.notes)
                        MemoOpenBridge.shared.open(id)
                    }
                } label: { Label(LibraryHatch.sendLabel, systemImage: "square.and.pencil") }
                .accessibilityIdentifier("library-pdf-send-to-note")
                Button {
                    if let id = LibraryPDF.moveToNote(book: book, store: store) {
                        dismiss()
                        TabSelectionBridge.shared.select(.notes)
                        MemoOpenBridge.shared.open(id)
                    }
                } label: { Label(LibraryPDF.toastAction, systemImage: "note.text") }
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
        HStack(spacing: 6) {
            Text("p. \(model.page) of \(model.pageCount)")
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(Color.skTextDim)
                .lineLimit(1)
                .fixedSize()
                .accessibilityIdentifier("library-pdf-page")
            Spacer(minLength: 4)
            if PDFReaderMode.showsToggle(hasReadingView: readingDoc != nil) {
                Button { toggleMode() } label: {
                    Text(mode == .reading ? "Original page" : "Reading view")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Color.skAccentText)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 6)
                        .frame(minHeight: 38)
                }
                .accessibilityIdentifier("library-pdf-toggle")
            }
            if mode == .reading, readingDoc != nil {
                Button { showTextSettings = true } label: {
                    Text("Aa")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.skTextDim)
                        .frame(width: 36, height: 38)
                }
                .accessibilityLabel("Text size")
                .accessibilityIdentifier("library-pdf-aa")
            }
            Button { startCapture() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus").font(.system(size: 14, weight: .semibold))
                    Text("Add note").font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(Color.skAccentText)
                .padding(.horizontal, 15).padding(.vertical, 9)
                .frame(minHeight: 38)
                .background(Color.skAccent.opacity(0.18), in: .capsule)
                .overlay(Capsule().strokeBorder(Color.skAccent.opacity(0.25), lineWidth: 0.5))
                .fixedSize()
            }
            .accessibilityIdentifier("library-pdf-add-note")
        }
        .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 10)
        .background(Color.skBg)
        .overlay(alignment: .top) { Rectangle().fill(Color.skBorder).frame(height: 0.5) }
    }
}

/// The jump-back from a note: this PDF at that page.
struct PDFJumpRequest: Identifiable {
    let id = UUID()
    let book: Audiobook
    let page: Int
}

/// What the capture screen opens with.
struct PDFCaptureRequest: Identifiable {
    let id = UUID()
    let quote: String
    let page: Int
}

// MARK: - Reader state

@MainActor
final class PDFReaderModel: ObservableObject {
    struct Selection: Equatable {
        let text: String
        /// In the PDF view's own coordinate space (the callout overlay shares its frame).
        let rect: CGRect
        /// 1-based page the selection starts on.
        var page: Int = 1
    }

    /// A tap on a stored highlight on the real page: its menu (Copy · Remove highlight).
    struct TappedHighlight: Equatable {
        let id: UUID
        let text: String
        let rect: CGRect
    }

    static let annotationPrefix = "skrift-hl:"

    @Published var page = 1
    @Published var pageCount = 1
    @Published private(set) var selection: Selection?
    @Published var tappedHighlight: TappedHighlight?
    /// The PDF's stored highlights, drawn as yellow highlight annotations on the real page.
    var highlights: [SourceHighlight] = [] { didSet { if highlights != oldValue { applyHighlights() } } }
    weak var pdfView: PDFView?
    /// False until the view has landed on the kept page: nothing is persisted before that, so the
    /// first layout pass (page 1) can never overwrite the page he left on.
    var ready = false

    func refreshSelection() {
        guard let view = pdfView, let current = view.currentSelection,
              let text = current.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
              let pdfPage = current.pages.first else {
            if selection != nil { selection = nil }
            return
        }
        let rect = view.convert(current.bounds(for: pdfPage), from: pdfPage)
        let index = view.document?.index(for: pdfPage) ?? 0
        let next = Selection(text: text, rect: rect, page: index == NSNotFound ? page : index + 1)
        if next != selection { selection = next }
        if tappedHighlight != nil { tappedHighlight = nil }
    }

    func refreshPage() {
        guard let view = pdfView, let doc = view.document, let current = view.currentPage else { return }
        let index = doc.index(for: current)
        if index != NSNotFound, page != index + 1 { page = index + 1 }
    }

    /// The stored highlight a selection sits in (same page, overlapping words), if any.
    func highlightID(containing selection: Selection) -> UUID? {
        let picked = SourceHighlights.normalized(selection.text)
        return highlights.first { h in
            h.page == selection.page && (h.text.contains(picked) || picked.contains(h.text))
        }?.id
    }

    func copySelection() {
        if let text = selection?.text { UIPasteboard.general.string = text }
        clearSelection()
    }

    func clearSelection() {
        pdfView?.clearSelection()
        selection = nil
    }

    /// Redraw the yellow on the real page: drop our annotations, add one per line of each highlight.
    func applyHighlights() {
        guard let view = pdfView, let doc = view.document else { return }
        for i in 0..<doc.pageCount {
            guard let p = doc.page(at: i) else { continue }
            for a in p.annotations where a.userName?.hasPrefix(Self.annotationPrefix) == true { p.removeAnnotation(a) }
        }
        let yellow = UIColor(red: 1, green: 0.8, blue: 0, alpha: 0.42)
        for h in highlights {
            guard let number = h.page, let page = doc.page(at: number - 1) else { continue }
            guard let match = doc.findString(h.text, withOptions: [.caseInsensitive]).first(where: { $0.pages.first == page })
            else { continue }
            for line in match.selectionsByLine() {
                let a = PDFAnnotation(bounds: line.bounds(for: page), forType: .highlight, withProperties: nil)
                a.color = yellow
                a.userName = Self.annotationPrefix + h.id.uuidString
                page.addAnnotation(a)
            }
        }
    }

    /// A tap at `point` (PDF view coordinates): opens a stored highlight's menu, or closes it.
    func tap(at point: CGPoint) {
        guard let view = pdfView, let page = view.page(for: point, nearest: false) else {
            tappedHighlight = nil
            return
        }
        let onPage = view.convert(point, to: page)
        guard selection == nil, let a = page.annotation(at: onPage), let name = a.userName,
              name.hasPrefix(Self.annotationPrefix),
              let id = UUID(uuidString: String(name.dropFirst(Self.annotationPrefix.count))),
              let h = highlights.first(where: { $0.id == id }) else {
            tappedHighlight = nil
            return
        }
        tappedHighlight = TappedHighlight(id: id, text: h.text, rect: view.convert(a.bounds, from: page))
    }
}

// MARK: - PDFKit

/// PDFKit's own selection menu is switched off: the reader draws its own callout (Copy · Highlight
/// · Add note) so the two never stack.
private final class ReaderPDFView: PDFView {
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool { false }
}

private struct PDFKitReader: UIViewRepresentable {
    let url: URL
    let startPage: Int
    let model: PDFReaderModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIView(context: Context) -> PDFView {
        let view = ReaderPDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.pageShadowsEnabled = true
        view.pageBreakMargins = UIEdgeInsets(top: 6, left: 0, bottom: 10, right: 0)
        view.backgroundColor = UIColor(Color.skBg)
        view.document = PDFDocument(url: url)
        model.pdfView = view
        model.pageCount = max(1, view.document?.pageCount ?? 1)
        model.applyHighlights()
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)
        let nc = NotificationCenter.default
        nc.addObserver(context.coordinator, selector: #selector(Coordinator.pageChanged),
                       name: .PDFViewPageChanged, object: view)
        nc.addObserver(context.coordinator, selector: #selector(Coordinator.selectionChanged),
                       name: .PDFViewSelectionChanged, object: view)
        // The callout follows the selection as the page scrolls or zooms.
        nc.addObserver(context.coordinator, selector: #selector(Coordinator.selectionChanged),
                       name: .PDFViewVisiblePagesChanged, object: view)
        nc.addObserver(context.coordinator, selector: #selector(Coordinator.selectionChanged),
                       name: .PDFViewScaleChanged, object: view)
        // Land on the kept page once the view has a size.
        DispatchQueue.main.async {
            if let doc = view.document {
                let index = min(max(0, startPage - 1), doc.pageCount - 1)
                if let target = doc.page(at: index) { view.go(to: target) }
                model.page = index + 1
            }
            model.ready = true
            model.refreshPage()
        }
        // The first `go` runs before auto-scaling has laid the pages out, which leaves the kept page
        // scrolled part-way (seen in the first Simulator render). Once layout has settled, land on
        // its top again, unless he has already moved on.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let doc = view.document {
                let index = min(max(0, startPage - 1), doc.pageCount - 1)
                // `go(to: page)` left the page ~80 pt low in the first render; naming the page's
                // top-left corner as the destination pins that corner to the view's top.
                if model.page == index + 1, let target = doc.page(at: index) {
                    let top = target.bounds(for: .cropBox)
                    view.go(to: PDFDestination(page: target, at: CGPoint(x: top.minX, y: top.maxY)))
                }
            }
            #if DEBUG
            LibraryPDFDebug.selectSampleIfAsked(in: view, model: model)
            #endif
        }
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {}

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let model: PDFReaderModel
        init(model: PDFReaderModel) { self.model = model }
        @objc func pageChanged() { Task { @MainActor in model.refreshPage(); model.refreshSelection() } }
        @objc func selectionChanged() { Task { @MainActor in model.refreshSelection() } }
        @MainActor @objc func tapped(_ gesture: UITapGestureRecognizer) {
            model.tap(at: gesture.location(in: gesture.view))
        }
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}

// MARK: - The callout over the selection (mock `.callout`)

/// The mock's dark callout: Copy · Highlight · ❝ Add note over a selection, Copy · Remove
/// highlight over a tapped highlight.
private struct SelectionCallout: View {
    struct Item {
        let title: String
        let id: String
        var accent = false
        let action: () -> Void
    }

    let anchor: CGRect
    let items: [Item]

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    if i > 0 { Rectangle().fill(.white.opacity(0.2)).frame(width: 0.5, height: 38) }
                    Button(action: item.action) {
                        Text(item.title)
                            .font(.system(size: 13, weight: item.accent ? .bold : .medium))
                            .foregroundStyle(item.accent ? Color(hex: 0xc9bfff) : .white)
                            .padding(.horizontal, 12).frame(minHeight: 38)
                    }
                    .accessibilityIdentifier(item.id)
                }
            }
            .background(Color(hex: 0x1c1c1e), in: .rect(cornerRadius: 9, style: .continuous))
            .shadow(color: .black.opacity(0.3), radius: 7, y: 4)
            .fixedSize()
            .position(position(in: geo.size))
        }
    }

    /// About how wide the callout draws: 13 pt text plus 24 pt of padding per item.
    private var halfWidth: CGFloat {
        items.reduce(0) { $0 + CGFloat($1.title.count) * 7.4 + 24 } / 2
    }

    /// Above the selection when there is room, else below it; kept inside the view.
    private func position(in size: CGSize) -> CGPoint {
        let halfHeight: CGFloat = 19
        let x = min(max(anchor.midX, halfWidth + 8), max(halfWidth + 8, size.width - halfWidth - 8))
        let above = anchor.minY - halfHeight - 8
        let y = above > halfHeight + 4 ? above : min(anchor.maxY + halfHeight + 8, size.height - halfHeight - 4)
        return CGPoint(x: x, y: y)
    }
}

// MARK: - Capture: the quote + his voice

/// "Add note" from the reader (mock `capnote`): the selected text as the quote, a rating, and
/// "Record your thoughts". Mirrors `MergedCaptureView`'s frame so the two captures read the same;
/// the note lands in Notes carrying the source and the page.
struct PDFCaptureView: View {
    let book: Audiobook
    let request: PDFCaptureRequest
    let onFinish: () -> Void

    @State private var quote: String
    @State private var significance: Double = 0
    @State private var createdMemoID: UUID?
    @State private var showRamble = false
    @State private var rambleSaved = false
    @FocusState private var quoteFocused: Bool

    init(book: Audiobook, request: PDFCaptureRequest, onFinish: @escaping () -> Void) {
        self.book = book
        self.request = request
        self.onFinish = onFinish
        _quote = State(initialValue: request.quote)
    }

    private var canRecord: Bool { !quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            header
            PhoneRatingRow(value: $significance)
                .padding(.horizontal, 16)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 2) {
                Text("Your quote.").font(.system(size: 14.5, weight: .bold)).foregroundStyle(Color.skText)
                Text("What you selected on the page. Edit it if you like.")
                    .font(.system(size: 11.5)).foregroundStyle(Color.skTextDim)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 6)
            quoteBlock
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
        .accessibilityIdentifier("library-pdf-capture")
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
                Text("\(book.title) \u{00B7} \(LibraryPDF.pageLabel(request.page))")
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
            .accessibilityIdentifier("library-pdf-capture-close")
        }
        .padding(.horizontal, 16).padding(.top, 15).padding(.bottom, 12)
    }

    /// Accent bar, italic, borderless: the quote idiom (no box on shared input).
    private var quoteBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $quote)
                .focused($quoteFocused)
                .font(.system(size: 15.5).italic())
                .foregroundStyle(Color.skText.opacity(0.78))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 90, maxHeight: 260)
                .accessibilityIdentifier("library-pdf-quote")
            attribution
                .font(.system(size: 12.5, weight: .medium))
        }
        .padding(.leading, 14)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(Color.skAccent.opacity(0.65)).frame(width: 3)
        }
        .padding(.horizontal, 18)
    }

    private var attribution: Text {
        guard let parts = CaptureQuote.attributionParts(book: book.title, author: book.author,
                                                        chapter: LibraryPDF.pageLabel(request.page)) else {
            return Text("")
        }
        return Text(parts.lead).foregroundStyle(Color.skTextDim)
            + Text(parts.title).italic().foregroundStyle(Color.skTextDim)
            + Text(parts.tail).foregroundStyle(Color.skTextDim)
    }

    private var recordBar: some View {
        RecordThoughtsButton { recordThoughts() }
        .disabled(!canRecord)
        .opacity(canRecord ? 1 : 0.45)
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 18)
        .accessibilityIdentifier("library-pdf-capture-record")
    }

    private func recordThoughts() {
        guard createdMemoID == nil else { return }
        quoteFocused = false
        guard let id = LibraryPDF.saveCapture(quote: quote, book: book, page: request.page,
                                              significance: significance) else { return }
        Haptics.success()
        createdMemoID = id
        showRamble = true
    }
}
