import SwiftUI
import PDFKit

/// Q297 / D177: what a PDF note's jump-back presents.
struct PDFJumpRequest: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    /// 1-based.
    let page: Int
}

/// The PDF note's jump-back target: the note's own file, scrolled to the page it came from.
/// QuickLook (the note's markup viewer) cannot be told a page, so this is a plain PDFKit reader;
/// markup stays on the inline block's own viewer.
struct PDFPageJumpView: View {
    let request: PDFJumpRequest
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let doc = PDFDocument(url: request.url) {
                    PDFPageRepresentable(document: doc, page: request.page)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    ContentUnavailableView("This PDF can’t be opened",
                                           systemImage: "doc.questionmark",
                                           description: Text("The file is missing or damaged on this device."))
                }
            }
            .navigationTitle("Page \(request.page)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("pdf-jump-done")
                }
            }
        }
    }
}

private struct PDFPageRepresentable: UIViewRepresentable {
    let document: PDFDocument
    let page: Int

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.document = document
        view.accessibilityIdentifier = "pdf-jump-view"
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        let index = SourceJump.clampedPageIndex(page: page, pageCount: document.pageCount)
        // The view has no layout yet on first update; go(to:) needs one, so defer a tick.
        DispatchQueue.main.async {
            if let target = document.page(at: index) { view.go(to: target) }
        }
    }
}
