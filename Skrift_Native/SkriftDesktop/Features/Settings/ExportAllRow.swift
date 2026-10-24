import SwiftUI
import AppKit
import SwiftData

/// Settings → Sync → "Export all notes" (D218, D219, signed mock `mocks/Q515-export-all.html`):
/// the row at the bottom of the Sync card. Ready: the count and "Export…". Building: a bar, the
/// count done and Cancel; closing Settings keeps it going (`ExportAllRun.shared`). Finished: the
/// save panel, Downloads by default; Save moves the zip there, Cancel deletes it.
struct ExportAllRow: View {
    @ObservedObject var run: ExportAllRun
    /// Snapshot injection: the count to show (nil = count the stores on appear).
    var countOverride: Int? = nil
    var interactive = true
    @State private var count: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                switch run.state {
                case .building(let done, let total):
                    Text(SharedCopy.exportAllBuilding).font(.system(size: 12)).foregroundStyle(Theme.textPrimary)
                    bar(total == 0 ? 0 : Double(done) / Double(total))
                    Text("\(done) of \(total)").font(.system(size: 12)).monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                    button("Cancel") { run.cancel() }
                default:
                    Text(SharedCopy.exportAllLabel).font(.system(size: 12)).foregroundStyle(Theme.textPrimary)
                    Spacer()
                    if let n = countOverride ?? count {
                        Text("\(n) notes").font(.system(size: 12)).monospacedDigit()
                            .foregroundStyle(Theme.textSecondary)
                    }
                    button("Export…") { Self.start(run) }
                }
            }
            Text(helpText)
                .font(.system(size: 11)).foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 11)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline.opacity(0.07)).frame(height: 0.5) }
        .accessibilityIdentifier("settings.exportAll")
        .onAppear { if countOverride == nil, interactive { count = Self.liveCount() } }
    }

    private var helpText: String {
        switch run.state {
        case .building: return "You can close Settings; it keeps going."
        case .failed(let message): return message
        default: return SharedCopy.exportAllRowHelp
        }
    }

    /// The folder row's "Choose…" button (`SettingsView.folderRow`).
    private func button(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 12)).foregroundStyle(Theme.accent)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Theme.hairline.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }

    /// Drawn, not a `ProgressView`: the snapshot renderer can't draw AppKit controls.
    private func bar(_ fraction: Double) -> some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.hairline.opacity(0.10))
                Capsule().fill(Theme.accent).frame(width: g.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 4)
        .frame(minWidth: 60)
    }

    // MARK: - the stores and the save panel

    @MainActor private static func stores() -> (rows: [PipelineFile], memos: [Memo], cloud: ModelContext?) {
        let rows = (try? SharedStore.container.mainContext.fetch(FetchDescriptor<PipelineFile>())) ?? []
        // A fresh context: `mainContext` reads stale after a CloudKit import.
        let cloud = MemoCloudStore.container.map { ModelContext($0) }
        let memos = (try? cloud?.fetch(FetchDescriptor<Memo>())) ?? []
        return (rows, memos, cloud)
    }

    @MainActor static func liveCount() -> Int {
        let s = stores()
        return VaultExporter.exportAllCount(rows: s.rows, memos: s.memos)
    }

    /// The notes that go in, read from `local` (rows) and `cloud` (memos and their blobs).
    @MainActor static func items(local: ModelContext, cloud: ModelContext?, people: [Person], author: String) -> [ExportAll.Item] {
        let rows = (try? local.fetch(FetchDescriptor<PipelineFile>())) ?? []
        let memos = (try? cloud?.fetch(FetchDescriptor<Memo>())) ?? []
        return VaultExporter.exportAllItems(rows: rows, memos: memos, assets: { id in
            (try? cloud?.fetch(FetchDescriptor<MemoAsset>(predicate: #Predicate { $0.memoID == id }))) ?? []
        }, people: people, author: author)
    }

    @MainActor static func start(_ run: ExportAllRun) {
        run.start(gather: {
            items(local: SharedStore.container.mainContext, cloud: stores().cloud,
                  people: NamesStore.shared.livePeople(), author: SettingsStore.shared.load().authorName)
        }, onFinished: { url in
            let panel = NSSavePanel()
            panel.nameFieldStringValue = url.lastPathComponent
            panel.allowedContentTypes = [.zip]
            panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            panel.canCreateDirectories = true
            let done: (NSApplication.ModalResponse) -> Void = { response in
                guard response == .OK, let dest = panel.url else { return run.finish() }
                do {
                    if FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.removeItem(at: dest) }
                    try FileManager.default.moveItem(at: url, to: dest)
                    run.finish()
                } catch {
                    run.fail("Couldn't save the zip there: \(error.localizedDescription) Export again and pick another folder.")
                }
            }
            if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: done) }
            else { panel.begin(completionHandler: done) }
        })
    }
}
