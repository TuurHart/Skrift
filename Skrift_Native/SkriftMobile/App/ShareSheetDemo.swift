#if DEBUG
import SwiftUI
import UIKit

/// Q464 (DEBUG): the share extension's real views, presented in a system sheet over a fake host
/// app, so a UI test can screenshot every state against `mocks/Q455-share-sheet.html` without
/// driving another app's share sheet. Launch with `-shareSheetDemo <state>` (voice, video, link,
/// photo, already, cant) and `-shareSheetDemoDark` for dark. The share UI files are compiled
/// into the app target for this (project.yml); the extension is still what ships them.
struct ShareSheetDemoHost: View {
    let state: String
    let dark: Bool
    @State private var shown = true

    var body: some View {
        ZStack {
            Color(red: 0.043, green: 0.078, blue: 0.102).ignoresSafeArea()   // a chat app behind
            Text("host app").foregroundStyle(.white.opacity(0.3))
        }
        .sheet(isPresented: $shown) {
            content
                .preferredColorScheme(dark ? .dark : .light)
                .presentationDetents([.large])
                .interactiveDismissDisabled()
        }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case "already":
            ShareFeedbackView(kind: .alreadyInSkrift(title: "Kiln idea",
                                                     line: "14 Oct  Glaze test at 1240 °C, the slow cool gives…"),
                              onRetry: {}, onClose: {})
        case "cant":
            ShareFeedbackView(kind: .unsupported(detail: "This share has no text, link, picture or audio in it. Nothing was saved."),
                              onRetry: {}, onClose: {})
        default:
            ShareSheetView(payload: Self.payload(state), sender: Self.sender(state),
                           onSave: { _, _ in true }, onCancel: {})
        }
    }

    private static let roster: [ShareRosterName] = [
        ShareRosterName(name: "Marta Silva", aliases: ["Marta"]),
        ShareRosterName(name: "Mark de Vries", aliases: ["Mark"]),
        ShareRosterName(name: "Mãe", aliases: []),
        ShareRosterName(name: "Matthijs", aliases: []),
    ]

    private static func sender(_ state: String) -> ShareSenderContext {
        let fromChat = state == "voice" || state == "photo"
        return ShareSenderContext(offered: fromChat, initialName: nil, roster: roster,
                                  remembered: ["WhatsApp|Marta": "Marta Silva"])
    }

    private static func payload(_ state: String) -> SharePayload {
        let dummy = FileManager.default.temporaryDirectory.appendingPathComponent("demo.bin")
        switch state {
        case "video":
            var p = SharePayload(type: .file)
            p.isVideo = true
            p.videoURL = dummy
            p.videoDuration = 72
            p.videoFilmedAt = DateComponents(calendar: .current, year: 2026, month: 10, day: 14, hour: 18, minute: 40).date
            return p
        case "link":
            return SharePayload(type: .url, url: "https://craftsmag.com/the-slow-cool",
                                urlTitle: "The slow cool: what a kiln teaches about patience")
        case "photo":
            return SharePayload(type: .image,
                                imageItems: [SharedImageItem(data: photoData, fileName: "capture_demo.jpg",
                                                             mimeType: "image/jpeg", recordedAt: nil,
                                                             originalName: "IMG-20261014-WA0003.jpg")],
                                mimeType: "image/jpeg")
        default:   // voice
            var p = SharePayload(type: .file)
            p.isAudio = true
            p.audioItems = [SharedAudioItem(url: dummy, duration: 41, recordedAt: nil,
                                            originalName: "PTT-20261014-WA0001.opus")]
            return p
        }
    }

    /// A sunset-ish gradient standing in for a shared photo.
    private static let photoData: Data = {
        let size = CGSize(width: 800, height: 600)
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            let colors = [UIColor(red: 0.85, green: 0.55, blue: 0.31, alpha: 1).cgColor,
                          UIColor(red: 0.65, green: 0.33, blue: 0.18, alpha: 1).cgColor,
                          UIColor(red: 0.23, green: 0.16, blue: 0.14, alpha: 1).cgColor]
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray,
                               locations: [0, 0.48, 1])!
            ctx.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            UIColor(red: 0.95, green: 0.76, blue: 0.48, alpha: 1).setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 480, y: 90, width: 170, height: 170))
        }
        return img.jpegData(compressionQuality: 0.85) ?? Data()
    }()
}
#endif
