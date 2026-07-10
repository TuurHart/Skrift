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
        // Audio DOES get the sheet (slim: card + significance, no ramble —
        // signed mock share-ingest-wave1.html state 1; 2+ clips add the chooser).
        // Every terminal path goes through a feedback state (A12/A16, signed
        // mock state 4) — no silent exits that look identical to success.
        Task { @MainActor in
            let payload = await SharePayloadLoader.load(from: extensionContext)
            if payload.isAudio {
                if !payload.audioItems.isEmpty {
                    presentSheet(payload: payload)
                } else {
                    presentState(.error(message: "The voice note couldn't be read from the share.",
                                        canRetry: false))
                }
            } else if payload.isVideo {
                completeVideo(payload)
            } else if payload.type == .file, payload.fileURL != nil {
                completeFile(payload)
            } else if Self.isEmptyPayload(payload) {
                // A16: unknown/empty payloads used to fall into an empty text
                // sheet whose Save minted a husk note.
                presentState(.unsupported(detail: "This share didn't contain anything Skrift understands — no text, link, image or audio arrived."))
            } else {
                presentSheet(payload: payload)
            }
        }
    }

    /// True when the loader fell through with nothing usable (unknown payloads
    /// land as an empty `.text`; a failed image load as empty `imageItems`).
    private static func isEmptyPayload(_ p: SharePayload) -> Bool {
        switch p.type {
        case .url:   return (p.url ?? "").isEmpty
        case .text:  return (p.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .image: return p.imageItems.isEmpty
        case .file:  return p.fileURL == nil
        }
    }

    private func presentSheet(payload: SharePayload) {
        let sheet = ShareSheetView(
            payload: payload,
            onSave: { [weak self] entries, imageDatas, dictationData in
                self?.complete(entries: entries, imageDatas: imageDatas,
                               dictationData: dictationData, payload: payload)
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
    private func complete(entries: [CaptureInboxEntry], imageDatas: [Data],
                          dictationData: Data?, payload: SharePayload) {
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
                                        dictationData: i == 0 ? dictationData : nil,
                                        audioFileURLs: audioFileURLs,
                                        imageDatas: entry.imageFileNames != nil ? imageDatas : nil)
            allOK = allOK && ok
        }
        guard allOK else {
            // Duplicate re-writes on retry are safe: entry ids are stable and the
            // drain dedups by memo UUID.
            presentState(.error(message: "The share couldn't be handed to Skrift.", canRetry: true),
                         retry: { [weak self] in
                             self?.complete(entries: entries, imageDatas: imageDatas,
                                            dictationData: dictationData, payload: payload)
                         })
            return
        }
        // Everything is copied into the inbox now — drop the extension-temp files.
        for item in payload.audioItems { try? FileManager.default.removeItem(at: item.url) }
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
        switch payload.type {
        case .image:
            let n = payload.imageItems.count
            return n > 1 ? "\(n) photos → one note" : "Photo saved"
        case .url:  return "Link saved"
        case .text: return "Text saved"
        case .file: return "Document saved"
        }
    }

    /// A shared video bypasses the annotation sheet: write a "video" inbox entry
    /// (the movie copied in) and finish via the Saved ✓ flash. The main app
    /// imports it as a normal voice memo (audio + a frame thumbnail + transcribe)
    /// on its next foreground drain. A12: a failed copy used to `cancel()` —
    /// the sheet closed looking exactly like success.
    private func completeVideo(_ payload: SharePayload) {
        guard let videoURL = payload.videoURL else {
            presentState(.error(message: "The video couldn't be read from the share.", canRetry: false))
            return
        }
        let id = UUID()
        let ext = videoURL.pathExtension.isEmpty ? "mov" : videoURL.pathExtension
        let entry = CaptureInboxEntry(
            id: id, type: "video", url: nil, urlTitle: nil, text: nil,
            imageFileName: nil, mimeType: nil, annotationText: nil,
            significance: 0, sharedAt: ISO8601.string(from: Date()),
            videoFileName: "video_\(id.uuidString).\(ext)"
        )
        guard CaptureInbox.write(entry, videoFileURL: videoURL) else {
            presentState(.error(message: "The video couldn't be handed to Skrift.", canRetry: true),
                         retry: { [weak self] in self?.completeVideo(payload) })
            return
        }
        try? FileManager.default.removeItem(at: videoURL)   // copied into the inbox now
        presentState(.saved(summary: "Video → a new note"))
    }

    /// A shared document (PDF/etc.) bypasses the annotation sheet: write a "file"
    /// inbox entry (the document copied in) and finish. The main app persists it as
    /// a `.file` capture on its next foreground drain; the user can ramble on it in
    /// the memo detail. (2026-06-21 device feedback: "share a PDF and have it live in there".)
    private func completeFile(_ payload: SharePayload) {
        guard let fileURL = payload.fileURL else {
            presentState(.error(message: "The document couldn't be read from the share.", canRetry: false))
            return
        }
        let id = UUID()
        let ext = fileURL.pathExtension.isEmpty ? "pdf" : fileURL.pathExtension
        let entry = CaptureInboxEntry(
            id: id, type: "file", url: nil, urlTitle: nil, text: nil,
            imageFileName: nil, mimeType: payload.mimeType, annotationText: nil,
            significance: 0, sharedAt: ISO8601.string(from: Date()),
            fileName: "file_\(id.uuidString).\(ext)",
            fileDisplayName: payload.fileName
        )
        guard CaptureInbox.write(entry, fileSourceURL: fileURL) else {
            presentState(.error(message: "The document couldn't be handed to Skrift.", canRetry: true),
                         retry: { [weak self] in self?.completeFile(payload) })
            return
        }
        try? FileManager.default.removeItem(at: fileURL)   // copied into the inbox now
        presentState(.saved(summary: payload.fileName.map { "\($0) saved" } ?? "Document saved"))
    }

    private func cancel() {
        extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
    }
}
