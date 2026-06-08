import MessageUI
import SwiftUI
import UIKit

/// Recipient for "Send feedback". Change here when it changes.
let feedbackRecipientEmail = "tiurihartog@icloud.com"

/// `MFMailComposeViewController` wrapper (ported from Shhhcribble). Pre-fills To /
/// Subject / Body (transcript + note + timestamp + device) and attaches a `.zip` of
/// the raw `Documents/Feedback/<uuid>/` folders for easy parsing on the receiving
/// end. The user can edit before sending; `onSent` fires only on a real send so the
/// caller can `markSent`.
struct FeedbackMailComposer: UIViewControllerRepresentable {
    let items: [FeedbackItem]
    var onSent: (([FeedbackItem]) -> Void)? = nil

    init(item: FeedbackItem, onSent: (([FeedbackItem]) -> Void)? = nil) {
        self.items = [item]; self.onSent = onSent
    }
    init(items: [FeedbackItem], onSent: (([FeedbackItem]) -> Void)? = nil) {
        self.items = items; self.onSent = onSent
    }

    func makeCoordinator() -> Coordinator { Coordinator(items: items, onSent: onSent) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients([feedbackRecipientEmail])

        if items.count == 1, let item = items.first {
            let snippet = item.transcript.isEmpty
                ? (item.note.isEmpty ? "(no transcript)" : String(item.note.prefix(40)))
                : String(item.transcript.prefix(40))
            vc.setSubject("Skrift feedback — \(snippet)")
        } else {
            vc.setSubject("Skrift feedback (\(items.count) items)")
        }

        var body = ""
        for (idx, item) in items.enumerated() {
            if items.count > 1 { body += "— Item \(idx + 1) of \(items.count) —\n\n" }
            if !item.transcript.isEmpty { body += "Transcript:\n\(item.transcript)\n\n" }
            if !item.note.isEmpty { body += "Note:\n\(item.note)\n\n" }
            body += "Captured: \(item.createdAt.formatted(date: .abbreviated, time: .standard))\n"
            if idx < items.count - 1 { body += "\n———\n\n" }
        }
        body += "\nDevice: \(UIDevice.current.model), iOS \(UIDevice.current.systemVersion)\n"
        body += "App: Skrift\n\n"
        body += "Raw data attached as feedback.zip — extract for the metadata.json + screenshot.png per item."
        vc.setMessageBody(body, isHTML: false)

        if let zipData = Self.zipFeedbackItems(items) {
            let zipName = items.count == 1 ? "feedback.zip" : "feedback-\(items.count)-items.zip"
            vc.addAttachmentData(zipData, mimeType: "application/zip", fileName: zipName)
        }
        return vc
    }

    /// Stage the selected folders into a temp dir, then zip via `NSFileCoordinator`'s
    /// `.forUploading` option (Apple-blessed). Returns the zip's raw `Data`.
    private static func zipFeedbackItems(_ items: [FeedbackItem]) -> Data? {
        guard !items.isEmpty else { return nil }
        let fm = FileManager.default
        let stagingRoot = fm.temporaryDirectory.appendingPathComponent("feedback-stage-\(UUID().uuidString)", isDirectory: true)
        let stagingFolder = stagingRoot.appendingPathComponent("feedback", isDirectory: true)
        guard (try? fm.createDirectory(at: stagingFolder, withIntermediateDirectories: true)) != nil else { return nil }
        defer { try? fm.removeItem(at: stagingRoot) }

        for item in items {
            let dst = stagingFolder.appendingPathComponent(item.folder.lastPathComponent, isDirectory: true)
            try? fm.copyItem(at: item.folder, to: dst)
        }
        let coordinator = NSFileCoordinator()
        var zipData: Data?
        var coordError: NSError?
        coordinator.coordinate(readingItemAt: stagingFolder, options: [.forUploading], error: &coordError) { zipURL in
            zipData = try? Data(contentsOf: zipURL)
        }
        return zipData
    }

    func updateUIViewController(_ vc: MFMailComposeViewController, context: Context) {}

    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let items: [FeedbackItem]
        let onSent: (([FeedbackItem]) -> Void)?
        init(items: [FeedbackItem], onSent: (([FeedbackItem]) -> Void)?) { self.items = items; self.onSent = onSent }

        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult, error: Error?) {
            controller.dismiss(animated: true) { [items, onSent] in
                if result == .sent { onSent?(items) }
            }
        }
    }
}
