import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// UIKit host for the SwiftUI share sheet. Share extensions MUST subclass
/// UIViewController (the UIKit lifecycle); SwiftUI is hosted via UIHostingController.
///
/// The principal class is declared in Info.plist:
///   NSExtensionPrincipalClass = $(PRODUCT_MODULE_NAME).ShareViewController
///
/// Flow:
///   1. iOS calls `viewDidLoad` after the extension launches.
///   2. We load the share payload from `extensionContext.inputItems`.
///   3. Present the SwiftUI `ShareSheetView` via a child UIHostingController.
///   4. The sheet calls `complete(entry:imageData:)` → CaptureInbox.write → extensionContext complete.
///   5. The sheet calls `cancel()` → extensionContext cancel.
@objc(ShareViewController)     // must match NSExtensionPrincipalClass (no module prefix in plist)
final class ShareViewController: UIViewController {

    private var hostingController: UIViewController?

    override func viewDidLoad() {
        super.viewDidLoad()
        // Opaque dark backdrop: the system share-sheet card behind us renders
        // a light-gray backdrop the extension can't dim or resize (the sheet
        // presentation is host-owned) — a translucent scrim over it reads as
        // washed gray, and the keyboard gap shows it too. #0e0f16, one step
        // darker than the card surface.
        view.backgroundColor = UIColor(red: 0.055, green: 0.059, blue: 0.086, alpha: 1)
        // Fill the host sheet. The host sizes this remote view to its CONTENT
        // (intrinsic/preferredContentSize), not the sheet — a compact card
        // would float at the bottom of an unpaintable gray sheet backdrop.
        // Ask for more height than any sheet can give; the host clamps it.
        preferredContentSize = CGSize(width: 0, height: 10_000)
        // The sheet always uses the dark palette (mock spec). SwiftUI's
        // preferredColorScheme does NOT propagate inside an extension's
        // UIHostingController — without this the adaptive sk* colors render
        // light (white cards on the dark surface).
        overrideUserInterfaceStyle = .dark

        // Load the share payload asynchronously and then present the sheet — or,
        // for a shared video, skip the sheet and import it as a voice memo.
        Task { @MainActor in
            let payload = await SharePayloadLoader.load(from: extensionContext)
            if payload.isVideo {
                completeVideo(payload)
            } else {
                presentSheet(payload: payload)
            }
        }
    }

    private func presentSheet(payload: SharePayload) {
        let sheet = ShareSheetView(
            payload: payload,
            onSave: { [weak self] entry, imageData, dictationData in
                self?.complete(entry: entry, imageData: imageData, dictationData: dictationData)
            },
            onCancel: { [weak self] in
                self?.cancel()
            }
        )
        let hc = UIHostingController(rootView: sheet)
        hc.view.backgroundColor = .clear
        addChild(hc)
        view.addSubview(hc.view)
        hc.view.translatesAutoresizingMaskIntoConstraints = false
        // Greedy height at priority 999: belt to preferredContentSize's braces.
        // If the host derives our size from the constraint system instead, this
        // breaks gracefully down to whatever the sheet actually offers — never
        // content-hugs back to the bare card.
        let greedyHeight = view.heightAnchor.constraint(greaterThanOrEqualToConstant: 10_000)
        greedyHeight.priority = UILayoutPriority(999)
        NSLayoutConstraint.activate([
            hc.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hc.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hc.view.topAnchor.constraint(equalTo: view.topAnchor),
            hc.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            greedyHeight
        ])
        hc.didMove(toParent: self)
        hostingController = hc
    }

    // MARK: - Completion

    private func complete(entry: CaptureInboxEntry, imageData: Data?, dictationData: Data?) {
        CaptureInbox.write(entry, imageData: imageData, dictationData: dictationData)
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }

    /// A shared video bypasses the annotation sheet: write a "video" inbox entry
    /// (the movie copied in) and finish. The main app imports it as a normal voice
    /// memo (audio + a frame thumbnail + transcribe) on its next foreground drain.
    private func completeVideo(_ payload: SharePayload) {
        guard let videoURL = payload.videoURL else { cancel(); return }
        let id = UUID()
        let ext = videoURL.pathExtension.isEmpty ? "mov" : videoURL.pathExtension
        let entry = CaptureInboxEntry(
            id: id, type: "video", url: nil, urlTitle: nil, text: nil,
            imageFileName: nil, mimeType: nil, annotationText: nil,
            significance: 0, sharedAt: ISO8601.string(from: Date()),
            videoFileName: "video_\(id.uuidString).\(ext)"
        )
        CaptureInbox.write(entry, videoFileURL: videoURL)
        try? FileManager.default.removeItem(at: videoURL)   // copied into the inbox now
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }

    private func cancel() {
        extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
    }
}
