import QuickLook
import SwiftUI
import UIKit

/// UIKit-presented QuickLook with markup save-back AND the native ZOOM
/// transition (P2#12 — "something black comes up from the bottom"): a SwiftUI
/// cover can only slide, so the controller is presented directly and
/// `transitionViewFor` anchors the zoom on the tapped photo's drawn rect (a
/// transient UIImageView laid exactly over the attachment; removed on
/// dismissal). Markup runs in `.updateContents`; the edit chain is reported
/// ON DISMISS only — the round-3 erase crash was the editor rebuilding under
/// a live markup session. A nil anchor (the shared-file card) presents with
/// the standard animation.
@MainActor
final class MarkupQuickLook: NSObject, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
    typealias Anchor = (container: UIView, rect: CGRect, image: UIImage?)

    private var url: URL?
    private var transitionView: UIImageView?
    private var edited = false
    private var onDismiss: ((_ edited: Bool) -> Void)?

    /// State setup + controller construction, separated from presentation so
    /// tests can drive the delegate without putting QuickLook on screen.
    func prepare(url: URL, onDismiss: @escaping (_ edited: Bool) -> Void) -> QLPreviewController {
        self.url = url
        self.edited = false
        self.onDismiss = onDismiss
        let ql = QLPreviewController()
        ql.dataSource = self
        ql.delegate = self
        return ql
    }

    func present(url: URL, anchor: Anchor?, onDismiss: @escaping (_ edited: Bool) -> Void) {
        let ql = prepare(url: url, onDismiss: onDismiss)
        if let anchor {
            // Laid exactly over the drawn attachment (same scale-to-fill the
            // attachment renderer uses) so the zoom appears to lift the photo
            // itself off the page.
            let iv = UIImageView(image: anchor.image)
            iv.frame = anchor.rect
            iv.contentMode = .scaleToFill
            iv.clipsToBounds = true
            iv.isUserInteractionEnabled = false
            anchor.container.addSubview(iv)
            transitionView = iv
        }
        topController(near: anchor?.container.window)?.present(ql, animated: true)
    }

    private func topController(near window: UIWindow?) -> UIViewController? {
        let win = window ?? UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
        var top = win?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }

    // MARK: QLPreviewControllerDataSource

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { url == nil ? 0 : 1 }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        (url ?? URL(fileURLWithPath: "/")) as NSURL
    }

    // MARK: QLPreviewControllerDelegate

    func previewController(_ controller: QLPreviewController,
                           transitionViewFor item: QLPreviewItem) -> UIView? {
        transitionView
    }

    /// Markup writes INTO the file (photos live in the app's recordings dir,
    /// always writable) — no "Save to Files?" detour.
    func previewController(_ controller: QLPreviewController,
                           editingModeFor previewItem: QLPreviewItem) -> QLPreviewItemEditingMode {
        .updateContents
    }

    func previewController(_ controller: QLPreviewController,
                           didUpdateContentsOf previewItem: QLPreviewItem) {
        DevLog.log("markup: saved back \((previewItem.previewItemURL ?? URL(fileURLWithPath: "/")).lastPathComponent)")
        edited = true
    }

    func previewControllerDidDismiss(_ controller: QLPreviewController) {
        transitionView?.removeFromSuperview()
        transitionView = nil
        let wasEdited = edited
        edited = false
        url = nil
        let callback = onDismiss
        onDismiss = nil
        callback?(wasEdited)
    }
}
