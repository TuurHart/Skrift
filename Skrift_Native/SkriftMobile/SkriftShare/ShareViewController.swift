import UIKit
import SwiftUI

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
///   4. The sheet calls `complete(entries:imageDatas:payload:)` → CaptureInbox.write → extensionContext complete.
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
        view.backgroundColor = ShareTheme.backdropUI
        // Fill the host sheet. The host sizes this remote view to its CONTENT
        // (intrinsic/preferredContentSize), not the sheet — a compact card
        // would float at the bottom of an unpaintable gray sheet backdrop.
        // Ask for more height than any sheet can give; the host clamps it.
        preferredContentSize = CGSize(width: 0, height: ShareTheme.hostHeight)
        // The sheet always uses the dark palette (mock spec). SwiftUI's
        // preferredColorScheme does NOT propagate inside an extension's
        // UIHostingController — without this the adaptive sk* colors render
        // light (white cards on the dark surface).
        overrideUserInterfaceStyle = .dark

        // Load the share and present the sheet (Q439 / C238: the ONE shared
        // `IngressDispatch` decides what the share is, inside the loader). Every
        // kind gets the sheet: audio slim (card + significance, no ramble — signed
        // mock share-ingest-wave1.html state 1; 2+ clips add the chooser), video and
        // documents with a typed thought (E1, mocks m1/m2). Every terminal path goes
        // through a feedback state (A12/A16, signed mock state 4) — no silent exits
        // that look identical to success, and an empty share never saves a husk (C75).
        Task { @MainActor in
            switch await SharePayloadLoader.load(from: extensionContext) {
            case .sheet(let payload):
                if payload.isBook {
                    handBookToApp(payload)
                } else if let fp = payload.fingerprint, Self.ledger?.existing(fp) != nil {
                    // C127 (Q440): these exact bytes were shared before — that note IS the
                    // share. Nothing new is written; the temps go.
                    Self.dropTemps(of: payload)
                    presentState(.alreadyInSkrift)
                } else {
                    presentSheet(payload: payload)
                }
            case .failed(let message):
                presentState(.error(message: message, canRetry: false))
            case .unsupported:
                presentState(.unsupported(detail: "This share didn't contain anything Skrift understands — no text, link, image or audio arrived."))
            }
        }
    }

    /// C127: the share ledger beside the inbox (nil without the App Group container).
    private static var ledger: ShareLedger? { ShareLedger.inContainer(CaptureInbox.containerURL) }

    private static func dropTemps(of payload: SharePayload) {
        for item in payload.audioItems { try? FileManager.default.removeItem(at: item.url) }
        if let v = payload.videoURL { try? FileManager.default.removeItem(at: v) }
        if let f = payload.fileURL { try? FileManager.default.removeItem(at: f) }
    }

    /// C146 (Q440): a book goes straight to the app's book importer — no note sheet, no file
    /// card. The entry carries the file; the drain raises the importer on the Books tab.
    private func handBookToApp(_ payload: SharePayload) {
        guard let src = payload.fileURL else {
            presentState(.error(message: "The share couldn't be read.", canRetry: false))
            return
        }
        let ext = src.pathExtension.isEmpty ? "skriftbook" : src.pathExtension
        let id = UUID()
        let entry = CaptureInboxEntry(
            id: id, type: "book", url: nil, urlTitle: nil, text: nil, imageFileName: nil, mimeType: nil,
            annotationText: nil, significance: 0, sharedAt: ISO8601DateFormatter().string(from: Date()),
            fileName: "book_\(id.uuidString).\(ext)", fileDisplayName: payload.fileName)
        if CaptureInbox.write(entry, fileSourceURL: src) {
            Self.dropTemps(of: payload)
            presentState(.saved(summary: "Book → Books"))
        } else {
            presentState(.error(message: "The share couldn't be handed to Skrift.", canRetry: true),
                         retry: { [weak self] in self?.handBookToApp(payload) })
        }
    }

    private func presentSheet(payload: SharePayload) {
        let sheet = ShareSheetView(
            payload: payload,
            onSave: { [weak self] entries, imageDatas in
                self?.complete(entries: entries, imageDatas: imageDatas, payload: payload)
            },
            onCancel: { [weak self] in
                self?.cancel()
            }
        )
        install(UIHostingController(rootView: sheet))
    }

    /// Swap the hosted SwiftUI root (sheet ⇄ feedback state), keeping the
    /// greedy-height constraint setup identical.
    private func install(_ hc: UIHostingController<some View>) {
        if let old = hostingController {
            old.willMove(toParent: nil)
            old.view.removeFromSuperview()
            old.removeFromParent()
        }
        hc.view.backgroundColor = .clear
        addChild(hc)
        view.addSubview(hc.view)
        hc.view.translatesAutoresizingMaskIntoConstraints = false
        // Greedy height at priority 999: belt to preferredContentSize's braces.
        // If the host derives our size from the constraint system instead, this
        // breaks gracefully down to whatever the sheet actually offers — never
        // content-hugs back to the bare card.
        let greedyHeight = view.heightAnchor.constraint(greaterThanOrEqualToConstant: ShareTheme.hostHeight)
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

    /// Show a terminal feedback state. Saved ✓ auto-dismisses (~0.9 s — the
    /// flash IS the receipt); error/unsupported wait for the user.
    private func presentState(_ kind: ShareFeedbackView.Kind,
                              retry: (() -> Void)? = nil) {
        let view = ShareFeedbackView(
            kind: kind,
            onRetry: { retry?() },
            onClose: { [weak self] in self?.cancel() }
        )
        install(UIHostingController(rootView: view))
        if case .saved = kind {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
            }
        }
    }

    // MARK: - Completion

    /// Write every entry the sheet produced (1 for most shares; N for the
    /// audio-split choice). Audio temp files map to entries by index: one entry
    /// takes ALL clips (combine), N entries take one clip each (split).
    /// Success flashes Saved ✓; a failed write shows the error state with a
    /// retry (temps are kept — they're the retry source). A12: this used to
    /// ignore the write result and complete anyway.
    private func complete(entries: [CaptureInboxEntry], imageDatas: [Data], payload: SharePayload) {
        var allOK = true
        for (i, entry) in entries.enumerated() {
            var audioFileURLs: [URL]?
            if let names = entry.audioFileNames, !names.isEmpty {
                if entries.count == 1 {
                    audioFileURLs = payload.audioItems.map(\.url)
                } else if i < payload.audioItems.count {
                    audioFileURLs = [payload.audioItems[i].url]
                }
            }
            let ok = CaptureInbox.write(entry,
                                        // E1: video/file entries come through the
                                        // sheet now — their temp copies ride along.
                                        videoFileURL: entry.videoFileName != nil ? payload.videoURL : nil,
                                        fileSourceURL: entry.fileName != nil ? payload.fileURL : nil,
                                        audioFileURLs: audioFileURLs,
                                        imageDatas: entry.imageFileNames != nil ? imageDatas : nil,
                                        emailAttachmentDatas: entry.emailAttachmentFileNames != nil
                                            ? payload.emailAttachments.map(\.data) : nil)
            allOK = allOK && ok
        }
        guard allOK else {
            // Duplicate re-writes on retry are safe: entry ids are stable and the
            // drain dedups by memo UUID.
            presentState(.error(message: "The share couldn't be handed to Skrift.", canRetry: true),
                         retry: { [weak self] in
                             self?.complete(entries: entries, imageDatas: imageDatas, payload: payload)
                         })
            return
        }
        // C127: these bytes now have a note (the first entry's id is its memo id, C147).
        if let fp = payload.fingerprint, let first = entries.first {
            Self.ledger?.record(fp, id: first.id)
        }
        // Everything is copied into the inbox now — drop the extension-temp files.
        Self.dropTemps(of: payload)
        presentState(.saved(summary: Self.savedSummary(for: entries, payload: payload)))
    }

    /// One line saying WHAT was saved ("8 voice notes → one note", "4 photos →
    /// one note", "Link saved") — the mock's receipt copy.
    private static func savedSummary(for entries: [CaptureInboxEntry], payload: SharePayload) -> String {
        if payload.isAudio {
            let clips = payload.audioItems.count
            if entries.count > 1 { return "\(clips) voice notes → \(entries.count) notes" }
            if clips > 1 { return "\(clips) voice notes → one note" }
            return "Voice note → a new note"
        }
        if payload.isVideo { return "Video → a new note" }
        switch payload.type {
        case .image:
            let n = payload.imageItems.count
            return n > 1 ? "\(n) photos → one note" : "Photo saved"
        case .url:  return "Link saved"
        case .text: return "Text saved"
        case .file:
            if entries.first?.routeToLibrary == true { return "PDF → Library" }
            return payload.fileName.map { "\($0) saved" } ?? "Document saved"
        }
    }

    private func cancel() {
        extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
    }
}
