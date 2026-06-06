#if DEBUG
import SwiftUI
import AppKit

/// Headless visual verification. Launched with `-snapshot <path>`, the app renders
/// the review UI to a PNG via `ImageRenderer` and exits — no window, no Screen
/// Recording permission. Used to check each build chunk against the design mock.
enum Snapshot {
    nonisolated static func renderIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-snapshot"), i + 1 < args.count else { return }
        let path = args[i + 1]

        MainActor.assumeIsolated {
            let files = DemoSeed.snapshotFiles()
            let model = AppModel()
            model.activeID = files.first?.id
            if let id = files.first?.id { model.selection = [id] }

            let view = HStack(spacing: 0) {
                SidebarView(model: model, files: files, scrollable: false).frame(width: 228)
                DetailPane(file: files.first).frame(maxWidth: .infinity)
            }
            .frame(width: 1180, height: 780)
            .background(Theme.bg)
            .environment(\.colorScheme, .dark)

            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            if let img = renderer.nsImage,
               let tiff = img.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: path))
                FileHandle.standardError.write(Data("snapshot written: \(path)\n".utf8))
            } else {
                FileHandle.standardError.write(Data("snapshot render failed\n".utf8))
            }
            exit(0)
        }
    }
}
#endif
