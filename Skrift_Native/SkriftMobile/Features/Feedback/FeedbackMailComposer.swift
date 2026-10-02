import MessageUI
import SwiftUI
import UIKit

/// Recipient for "Send feedback". Change here when it changes.
let feedbackRecipientEmail = "tiurihartog@icloud.com"

/// `MFMailComposeViewController` wrapper (ported from Shhhcribble). Pre-fills To /
/// Subject / Body (transcript + note + timestamp + device) and attaches a `.zip` of
/// the raw `Documents/Feedback/<uuid>/` folder for easy parsing on the receiving
/// end. The user can edit before sending; `onSent` fires only on a real send so the
/// caller can `markSent`.
struct FeedbackMailComposer: UIViewControllerRepresentable {
    let item: FeedbackItem
    var onSent: ((FeedbackItem) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(item: item, onSent: onSent) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients([feedbackRecipientEmail])

        let snippet = item.transcript.isEmpty
            ? (item.note.isEmpty ? "(no transcript)" : String(item.note.prefix(40)))
            : String(item.transcript.prefix(40))
        vc.setSubject("Skrift feedback — \(snippet)")

        var body = ""
        if !item.transcript.isEmpty { body += "Transcript:\n\(item.transcript)\n\n" }
        if !item.note.isEmpty { body += "Note:\n\(item.note)\n\n" }
        body += "Captured: \(item.createdAt.formatted(date: .abbreviated, time: .standard))\n"
        body += "\nDevice: \(UIDevice.current.model), iOS \(UIDevice.current.systemVersion)\n"
        body += "App: Skrift\n\n"
        body += "Raw data attached as feedback.zip — extract for the metadata.json + screenshot.png."
        vc.setMessageBody(body, isHTML: false)

        if let zipData = Self.zipFeedbackItem(item) {
            vc.addAttachmentData(zipData, mimeType: "application/zip", fileName: "feedback.zip")
        }
        return vc
    }

    /// Stage the item's folder into a temp dir, then zip via `NSFileCoordinator`'s
    /// `.forUploading` option (Apple-blessed). Returns the zip's raw `Data`.
    private static func zipFeedbackItem(_ item: FeedbackItem) -> Data? {
        let fm = FileManager.default
        let stagingRoot = fm.temporaryDirectory.appendingPathComponent("feedback-stage-\(UUID().uuidString)", isDirectory: true)
        let stagingFolder = stagingRoot.appendingPathComponent("feedback", isDirectory: true)
        guard (try? fm.createDirectory(at: stagingFolder, withIntermediateDirectories: true)) != nil else { return nil }
        defer { try? fm.removeItem(at: stagingRoot) }

        let dst = stagingFolder.appendingPathComponent(item.folder.lastPathComponent, isDirectory: true)
        try? fm.copyItem(at: item.folder, to: dst)

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
        let item: FeedbackItem
        let onSent: ((FeedbackItem) -> Void)?
        init(item: FeedbackItem, onSent: ((FeedbackItem) -> Void)?) { self.item = item; self.onSent = onSent }

        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult, error: Error?) {
            controller.dismiss(animated: true) { [item, onSent] in
                if result == .sent { onSent?(item) }
            }
        }
    }
}
