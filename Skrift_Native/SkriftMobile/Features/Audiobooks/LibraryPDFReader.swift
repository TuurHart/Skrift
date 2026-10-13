import PDFKit
import SwiftUI
import UIKit

/// Q354 (Q6 mock "PDF reader", D135): the PDF reader a Library tile opens. PDFKit with text
/// selection, the page kept on the book, and "Add note" in two places like the mock: a callout
/// over the selection (Copy · Add note) and a chip in the dock beside "p. 4 of 18".
/// "Add note" opens `PDFCaptureView` (the quote + his voice).
struct LibraryPDFReaderView: View {
    let book: Audiobook
    /// A jump-back from a note opens the page the note came from and does NOT move the book's own
    /// place (the Q6 mock's rule for every source).
    var jumpBackPage: Int? = nil

    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = PDFReaderModel()
    @State private var capture: PDFCaptureRequest?
    @State private var movedToNote = false

    private var store: AudiobookLibraryStore { .shared }
    private var url: URL { store.audioURL(of: book, fileIndex: 0) }

    var body: some View {
        VStack(spacing: 0) {
            navBar
            ZStack {
                PDFKitReader(url: url, startPage: jumpBackPage ?? LibraryPDF.page(of: book), model: model)
                    .ignoresSafeArea(edges: .horizontal)
                if let selection = model.selection {
                    SelectionCallout(
                        anchor: selection.rect,
                        onCopy: { model.copySelection() },
                        onAddNote: { startCapture() })
                }
            }
            .frame(maxHeight: .infinity)
            dock
        }
        .background(Color.skBg.ignoresSafeArea())
        .onChange(of: model.page) { _, page in
            if jumpBackPage == nil, model.ready { LibraryPDF.savePage(page, bookID: book.id, store: store) }
        }
        .fullScreenCover(item: $capture, onDismiss: { model.clearSelection() }) { request in
            PDFCaptureView(book: book, request: request) { capture = nil }
        }
        .accessibilityIdentifier("library-pdf-reader")
    }

    private func startCapture() {
        capture = PDFCaptureRequest(quote: model.selection?.text ?? "", page: model.page)
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
        HStack {
            Text("p. \(model.page) of \(model.pageCount)")
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(Color.skTextDim)
                .accessibilityIdentifier("library-pdf-page")
            Spacer()
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
    }

    @Published var page = 1
    @Published var pageCount = 1
    @Published private(set) var selection: Selection?
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
        let next = Selection(text: text, rect: rect)
        if next != selection { selection = next }
    }

    func refreshPage() {
        guard let view = pdfView, let doc = view.document, let current = view.currentPage else { return }
        let index = doc.index(for: current)
        if index != NSNotFound, page != index + 1 { page = index + 1 }
    }

    func copySelection() {
        if let text = selection?.text { UIPasteboard.general.string = text }
        clearSelection()
    }

    func clearSelection() {
        pdfView?.clearSelection()
        selection = nil
    }
}

// MARK: - PDFKit

/// PDFKit's own selection menu is switched off: the reader draws its own callout (Copy · Add
/// note) so the two never stack.
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
                if model.page == index + 1, let target = doc.page(at: index) { view.go(to: target) }
            }
            #if DEBUG
            LibraryPDFDebug.selectSampleIfAsked(in: view, model: model)
            #endif
        }
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {}

    final class Coordinator: NSObject {
        let model: PDFReaderModel
        init(model: PDFReaderModel) { self.model = model }
        @objc func pageChanged() { Task { @MainActor in model.refreshPage(); model.refreshSelection() } }
        @objc func selectionChanged() { Task { @MainActor in model.refreshSelection() } }
    }
}

// MARK: - The callout over the selection (mock `.callout`)

private struct SelectionCallout: View {
    let anchor: CGRect
    let onCopy: () -> Void
    let onAddNote: () -> Void

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                Button(action: onCopy) {
                    Text("Copy")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).frame(minHeight: 38)
                }
                .accessibilityIdentifier("library-pdf-copy")
                Rectangle().fill(.white.opacity(0.2)).frame(width: 0.5, height: 38)
                Button(action: onAddNote) {
                    Text("\u{275D} Add note")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(hex: 0xc9bfff))
                        .padding(.horizontal, 12).frame(minHeight: 38)
                }
                .accessibilityIdentifier("library-pdf-callout-add-note")
            }
            .background(Color(hex: 0x1c1c1e), in: .rect(cornerRadius: 9, style: .continuous))
            .shadow(color: .black.opacity(0.3), radius: 7, y: 4)
            .fixedSize()
            .position(position(in: geo.size))
        }
    }

    /// Above the selection when there is room, else below it; kept inside the view.
    private func position(in size: CGSize) -> CGPoint {
        let halfWidth: CGFloat = 78, halfHeight: CGFloat = 19
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
        Button { recordThoughts() } label: {
            HStack(spacing: 12) {
                Image(systemName: "mic")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.18), in: .circle)
                Text("Record your thoughts")
                    .font(.system(size: 14.5, weight: .bold))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
            }
            .padding(EdgeInsets(top: 13, leading: 16, bottom: 13, trailing: 16))
            .background(
                LinearGradient(colors: [Color(hex: 0x8e7dff), Color(hex: 0x6a59ef)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: .rect(cornerRadius: 14, style: .continuous))
        }
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
