import SwiftUI
import UIKit

/// Settings → iCloud sync → "Export all notes…" (D218, D219, signed mock
/// `SkriftDesktop/mocks/Q515-export-all.html`): the row after "Synced audiobooks". Ready: the
/// count. Building: a spinner, the count done, a bar and Cancel; leaving Settings keeps it going
/// (`ExportAllRun.shared`). Finished: the share sheet with the one zip, over whatever is on
/// screen; closing it deletes the file.
struct ExportAllSettingsRow: View {
    @ObservedObject var run: ExportAllRun = .shared
    /// Render-test injection: the count to show (nil = count the store on appear).
    var countOverride: Int? = nil
    @State private var count: Int?

    var body: some View {
        Group {
            switch run.state {
            case .building(let done, let total):
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 12) {
                        ProgressView().frame(width: 22)
                        Text(SharedCopy.exportAllBuilding)
                        Spacer()
                        Text("\(done) of \(total)").monospacedDigit().foregroundStyle(Color.skTextDim)
                    }
                    ThinProgressBar(fraction: total == 0 ? 0 : Double(done) / Double(total), height: 4)
                        .padding(.leading, 34)
                    HStack {
                        Text("You can leave Settings.").font(.footnote).foregroundStyle(Color.skTextDim)
                        Spacer()
                        Button("Cancel") { run.cancel() }
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("export-all-cancel")
                    }
                    .padding(.leading, 34)
                }
                .padding(.vertical, 4)
            default:
                VStack(alignment: .leading, spacing: 4) {
                    Button { Self.start(run) } label: {
                        HStack {
                            Label(SharedCopy.exportAllLabel + "…", systemImage: "square.and.arrow.up")
                            Spacer()
                            if let n = countOverride ?? count {
                                Text("\(n)").monospacedDigit().foregroundStyle(Color.skTextDim)
                            }
                        }
                    }
                    if case .failed(let message) = run.state {
                        Text(message).font(.footnote).foregroundStyle(Color.skTextDim)
                    }
                }
            }
        }
        .accessibilityIdentifier("export-all-row")
        .onAppear { if countOverride == nil { count = NotesRepository.shared.canonicalMemos().count } }
        #if DEBUG
        .task {
            guard LaunchFlags.exportAllOnLaunch, !Self.launchExportStarted else { return }
            Self.launchExportStarted = true
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            count = NotesRepository.shared.canonicalMemos().count
            Self.start(run)
        }
        #endif
    }

    #if DEBUG
    private static var launchExportStarted = false
    #endif

    @MainActor static func start(_ run: ExportAllRun) {
        run.start(gather: {
            ObsidianPublisher.live(author: AuthorSettings.name())
                .exportAllItems(NotesRepository.shared.canonicalMemos())
        }, onFinished: { url in presentShareSheet(url, run: run) })
    }

    /// The system share sheet over whatever is on screen: a `.sheet` on a Form row closes itself
    /// at once, and he may have left Settings while it built. Closing it deletes the zip.
    @MainActor private static func presentShareSheet(_ url: URL, run: ExportAllRun) {
        let window = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        guard let top else { return run.fail("Couldn't open the share sheet. Export again.") }
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        sheet.completionWithItemsHandler = { _, _, _, _ in run.finish() }
        if let popover = sheet.popoverPresentationController {   // iPad: anchor it mid-screen
            popover.sourceView = top.view
            popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        top.present(sheet, animated: true)
    }
}
