import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// Q354: everything the Library tab needs for PDFs, in ONE modifier so `AudiobookLibraryView`
/// gains a single line: the "ePub or PDF" door's Files picker, the PDF reader a tile opens, and
/// the "Added to Library · add to a note instead" toast (mock `.itoast`).
///
/// The picker and the cover sit on a clear background view: a second `.fileImporter` or
/// `.fullScreenCover` on the library's own body would fight the audiobook importer and the
/// player for the one presentation slot.
struct LibraryPDFHost: ViewModifier {
    @Binding var isImporting: Bool
    @Binding var reader: Audiobook?
    @ObservedObject private var arrival = LibraryPDFArrival.shared
    @State private var shownArrival: LibraryPDFArrival.Arrival?
    @State private var importFailed = false

    private var store: AudiobookLibraryStore { .shared }

    func body(content: Content) -> some View {
        content
            .background {
                Color.clear
                    .fileImporter(isPresented: $isImporting, allowedContentTypes: [.pdf],
                                  allowsMultipleSelection: true) { result in
                        guard case .success(let urls) = result else { return }
                        importFromFiles(urls)
                    }
                    .fullScreenCover(item: $reader) { book in
                        LibraryPDFReaderView(book: book)
                    }
            }
            .overlay(alignment: .bottom) {
                if let shown = shownArrival {
                    LibraryPDFToast(onAddToNote: { addToNoteInstead(shown) })
                        .padding(.horizontal, 14)
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.22), value: shownArrival)
            .onChange(of: arrival.pending) { _, next in
                guard let next else { return }
                show(next)
            }
            .onAppear { if let next = arrival.pending { show(next) } }
            .alert("That file could not be opened", isPresented: $importFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Skrift could not read it as a PDF.")
            }
            #if DEBUG
            .task { LibraryPDFDebug.run(store: store, reader: $reader, arrival: arrival) }
            #endif
    }

    private func importFromFiles(_ urls: [URL]) {
        var failed = false
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if LibraryPDF.importPDF(from: url, displayName: url.lastPathComponent, store: store) == nil {
                failed = true
            }
        }
        importFailed = failed
    }

    private func show(_ next: LibraryPDFArrival.Arrival) {
        shownArrival = next
        arrival.clear()
        // The mock keeps it up 9 s: long enough to change his mind, short enough to leave alone.
        Task {
            try? await Task.sleep(for: .seconds(9))
            if shownArrival == next { shownArrival = nil }
        }
    }

    /// "Add to a note instead": the source becomes a new note with the PDF attached and leaves
    /// Library; he lands on that note, like every share does.
    private func addToNoteInstead(_ shown: LibraryPDFArrival.Arrival) {
        shownArrival = nil
        guard let book = store.book(id: shown.bookID),
              let memoID = LibraryPDF.moveToNote(book: book, store: store) else { return }
        TabSelectionBridge.shared.select(.notes)
        MemoOpenBridge.shared.open(memoID)
    }
}

extension View {
    func libraryPDFs(isImporting: Binding<Bool>, reader: Binding<Audiobook?>) -> some View {
        modifier(LibraryPDFHost(isImporting: isImporting, reader: reader))
    }
}

/// The in-app toast with an action (mock `.itoast`): dark pill, white 13.5 text, accent action.
struct LibraryPDFToast: View {
    let onAddToNote: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(LibraryPDF.toastText + ".")
                .font(.system(size: 13.5, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onAddToNote) {
                Text(LibraryPDF.toastAction)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(hex: 0xc9bfff))
                    .padding(.horizontal, 8)
                    .frame(minHeight: 40)
            }
            .accessibilityIdentifier("library-pdf-toast-action")
        }
        .padding(.leading, 14).padding(.trailing, 10).padding(.vertical, 10)
        .background(Color(hex: 0x1c1c1e), in: .rect(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 12, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(LibraryPDF.toastLine)
        .accessibilityIdentifier("library-pdf-toast")
    }
}

#if DEBUG
/// Screenshot hooks (Simulator only): `-seedLibraryPDF` puts two PDFs on the shelf,
/// `-showPDFReader` opens the 18-page one on page 4 with its budget line selected,
/// `-showPDFToast` raises the share toast.
@MainActor
enum LibraryPDFDebug {
    private static var sampleSelection: String { "Sensor integration and field tests: €18,000" }
    /// Q404: what the screenshots select (the mock's selection, beside the stored highlight).
    private static var originalSelection: String { "The project runs for eighteen months." }
    private static var readingSelection: String { "project runs for eighteen months. Costs below" }
    /// Q463: the Q462 mock's comment.
    private static var sampleComment: String {
        "Ask Rui if the second test site is still Sines. If not, this line drops by a third."
    }

    /// Q404: on `-showPDFReader`, select the mock's words in the reading view and raise its menu.
    static func readingAppeared(model: ArticleReaderModel) async {
        guard LaunchFlags.showPDFReader, LaunchFlags.pdfCommentStep == nil else { return }
        try? await Task.sleep(for: .milliseconds(900))
        guard let tv = model.textView else { return }
        let r = (tv.text as NSString).range(of: readingSelection)
        guard r.location != NSNotFound else { return }
        tv.becomeFirstResponder()
        tv.selectedRange = r
        try? await Task.sleep(for: .milliseconds(300))
        model.showSelectionMenu?()
    }

    static func run(store: AudiobookLibraryStore, reader: Binding<Audiobook?>, arrival: LibraryPDFArrival) {
        if let path = LaunchFlags.showPDFFile {
            // Q460: a fixture PDF from a path, opened in its reading view.
            let url = URL(fileURLWithPath: path)
            let title = url.deletingPathExtension().lastPathComponent
            let book = store.books.first { $0.title == title }
                ?? LibraryPDF.importPDF(from: url, displayName: url.lastPathComponent, store: store)
            if let book {
                PDFReaderMode.setPrefersOriginal(false, bookID: book.id)
                reader.wrappedValue = book
            }
            return
        }
        guard LaunchFlags.seedLibraryPDF || LaunchFlags.showPDFReader || LaunchFlags.showPDFToast else { return }
        var grant = store.books.first { $0.title == "GFR grant application, draft 3" }
        var budget = store.books.first { $0.title == "Sensor budget, revised" }
        if grant == nil, let url = makeGrantPDF() {
            grant = LibraryPDF.importPDF(from: url, displayName: "GFR grant application, draft 3.pdf", store: store)
            if let g = grant { LibraryPDF.savePage(4, bookID: g.id, store: store); grant = store.book(id: g.id) }
        }
        if budget == nil, let url = makeSimplePDF(pages: 6) {
            budget = LibraryPDF.importPDF(from: url, displayName: "Sensor budget, revised.pdf", store: store)
        }
        if let g = grant, LibraryHighlights.list(g.id, store: store).isEmpty {
            // Q404: the mock's stored yellow highlight on the budget line.
            LibraryHighlights.add(sampleSelection, page: 4, word: 0, bookID: g.id, store: store)
            grant = store.book(id: g.id)
        }
        if let step = LaunchFlags.pdfCommentStep, let g = grant,
           let h = LibraryHighlights.list(g.id, store: store).first {
            // Q463: the Q462 mock's comment on the budget line (none for the first callout).
            LibraryHighlights.setComment(step == "tap" ? nil : sampleComment, audio: nil, on: h.id,
                                         bookID: g.id, store: store)
            grant = store.book(id: g.id)
        }
        if LaunchFlags.showPDFReader, let g = grant {
            // Q404: `-pdfOriginal` opens the real page; otherwise the reading view.
            PDFReaderMode.setPrefersOriginal(ProcessInfo.processInfo.arguments.contains("-pdfOriginal"), bookID: g.id)
            reader.wrappedValue = g
        }
        if LaunchFlags.showPDFToast, let budget { arrival.post(bookID: budget.id) }
    }

    /// Selects the budget line on the open reader so the callout can be screenshotted.
    static func selectSampleIfAsked(in view: PDFView, model: PDFReaderModel) {
        guard LaunchFlags.showPDFReader, LaunchFlags.pdfCommentStep == nil, let doc = view.document else { return }
        for match in doc.findString(originalSelection, withOptions: [.literal]).prefix(1) {
            view.setCurrentSelection(match, animate: false)
            // A programmatic selection is not drawn without a first responder; a touch selection is.
            match.color = UIColor.systemBlue.withAlphaComponent(0.25)
            view.highlightedSelections = [match]
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                model.refreshSelection()
            }
        }
    }

    private static func makeGrantPDF() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("grant_\(UUID().uuidString).pdf")
        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let body = UIFont(name: "Georgia", size: 13) ?? .systemFont(ofSize: 13)
        let head = UIFont.systemFont(ofSize: 15, weight: .bold)
        let data = UIGraphicsPDFRenderer(bounds: bounds).pdfData { ctx in
            for p in 1...18 {
                ctx.beginPage()
                if p == 4 {
                    ("4. Budget" as NSString).draw(at: CGPoint(x: 56, y: 60), withAttributes: [.font: head])
                    let lines = [
                        "The project runs for eighteen months. Costs below are for the first phase only;",
                        "phase two is costed in Annex B.",
                        "",
                        sampleSelection + " covers two test sites",
                        "and the replacement parts we expect to burn through.",
                    ]
                    for (i, line) in lines.enumerated() {
                        (line as NSString).draw(at: CGPoint(x: 56, y: 96 + CGFloat(i) * 20), withAttributes: [.font: body])
                    }
                    // Q404: the mock's two-column table (label left, amount right-aligned).
                    let rows = [("Personnel", "€42,000"), ("Sensor integration and field tests", "€18,000"),
                                ("Travel", "€3,200"), ("Total phase one", "€63,200")]
                    for (i, row) in rows.enumerated() {
                        let y = 216 + CGFloat(i) * 20
                        (row.0 as NSString).draw(at: CGPoint(x: 56, y: y), withAttributes: [.font: body])
                        let amount = row.1 as NSString
                        let w = amount.size(withAttributes: [.font: body]).width
                        amount.draw(at: CGPoint(x: 400 - w, y: y), withAttributes: [.font: body])
                    }
                    ("We ask the panel to note that the field tests carry most of the technical risk." as NSString)
                        .draw(at: CGPoint(x: 56, y: 312), withAttributes: [.font: body])
                } else if p == 1 {
                    ("GFR grant application, draft 3" as NSString).draw(
                        in: CGRect(x: 56, y: 120, width: 500, height: 120),
                        withAttributes: [.font: UIFont.systemFont(ofSize: 34, weight: .bold)])
                    for i in 0..<6 {
                        ("Lorem ipsum dolor sit amet, consectetur adipiscing elit sed do" as NSString)
                            .draw(at: CGPoint(x: 56, y: 280 + CGFloat(i) * 22), withAttributes: [.font: body])
                    }
                } else {
                    ("Section \(p)" as NSString).draw(at: CGPoint(x: 56, y: 60), withAttributes: [.font: head])
                    // A text layer on every page, so the reading view is offered (Q404 quality rule).
                    let filler = ["This section sets out the plan for one part of the work and who carries it,",
                                  "with the dates the panel asked for and the risks we see in each step.",
                                  "The figures are in the budget section; nothing here changes them."]
                    for (i, line) in filler.enumerated() {
                        (line as NSString).draw(at: CGPoint(x: 56, y: 96 + CGFloat(i) * 20), withAttributes: [.font: body])
                    }
                }
            }
        }
        return (try? data.write(to: url)) != nil ? url : nil
    }

    private static func makeSimplePDF(pages: Int) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("simple_\(UUID().uuidString).pdf")
        let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData { ctx in
            for p in 1...pages {
                ctx.beginPage()
                ("Sensor budget, revised, page \(p)" as NSString)
                    .draw(at: CGPoint(x: 56, y: 60), withAttributes: [.font: UIFont.systemFont(ofSize: 15, weight: .bold)])
            }
        }
        return (try? data.write(to: url)) != nil ? url : nil
    }
}
#endif
