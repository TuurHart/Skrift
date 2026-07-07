import QuickLook
import SwiftUI

/// QuickLook with MARKUP save-back (round-1 P2#10 "draw on photos in-app"):
/// the plain `.quickLookPreview` modifier is read-only; this wrapper answers
/// `.updateContents`, so the pencil tools write straight back into the photo
/// file, and `onEdited` fires for the re-mirror/re-thumbnail chain. Live Text
/// (copyable OCR) comes along for free, as before.
struct MarkupPreviewView: UIViewControllerRepresentable {
    let url: URL
    var onEdited: () -> Void = {}
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UINavigationController {
        let ql = QLPreviewController()
        ql.dataSource = context.coordinator
        ql.delegate = context.coordinator
        // A nav wrapper gives QL its bar (Done + the markup pencil) inside
        // the SwiftUI cover.
        let nav = UINavigationController(rootViewController: ql)
        nav.navigationBar.tintColor = UIColor(Color.skAccent)
        return nav
    }

    func updateUIViewController(_ nav: UINavigationController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
        private let parent: MarkupPreviewView
        init(_ parent: MarkupPreviewView) { self.parent = parent }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController,
                               previewItemAt index: Int) -> QLPreviewItem {
            parent.url as NSURL
        }

        /// Markup writes INTO the file (photos live in the app's recordings
        /// dir, always writable) — no "Save to Files?" detour.
        func previewController(_ controller: QLPreviewController,
                               editingModeFor previewItem: QLPreviewItem) -> QLPreviewItemEditingMode {
            .updateContents
        }

        func previewController(_ controller: QLPreviewController,
                               didUpdateContentsOf previewItem: QLPreviewItem) {
            DevLog.log("markup: saved back \(parent.url.lastPathComponent)")
            parent.onEdited()
        }

        func previewControllerDidDismiss(_ controller: QLPreviewController) {
            parent.dismiss()
        }
    }
}
