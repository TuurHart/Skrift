#if DEBUG
import SwiftUI

/// Q336 (DEBUG only): Settings -> "Test notes". Fill seeds the deterministic fake library into
/// this app's own synced store; Remove deletes exactly the marked notes. Logic: `TestLibrary` /
/// `TestLibraryRunner` (Shared/Corpus).
struct TestLibrarySettingsSection: View {
    @StateObject private var runner = TestLibraryRunner()
    @State private var confirmRemove = false

    var body: some View {
        Section {
            Button {
                let repo = NotesRepository.shared
                runner.fill(container: repo.container, recordingsDirectory: AppPaths.recordingsDirectory) {
                    repo.noteStoreDidChangeBySync()
                    NamesCloudSync.run(repo)
                }
            } label: {
                Label(TestLibraryRunner.Copy.fillTitle, systemImage: "tray.and.arrow.down")
            }
            .disabled(runner.busy)
            .accessibilityIdentifier("test-library-fill")

            Button(role: .destructive) { confirmRemove = true } label: {
                Label(TestLibraryRunner.Copy.removeTitle, systemImage: "trash")
            }
            .disabled(runner.busy || runner.markedCount == 0)
            .accessibilityIdentifier("test-library-remove")

            HStack {
                if runner.busy { ProgressView().controlSize(.mini) }
                Text(runner.status.isEmpty ? "\(runner.markedCount) test notes here" : runner.status)
                    .font(.footnote.monospacedDigit()).foregroundStyle(Color.skTextDim)
            }
            .accessibilityIdentifier("test-library-status")
        } header: {
            Text(TestLibraryRunner.Copy.sectionTitle)
        } footer: {
            Text(TestLibraryRunner.Copy.help)
        }
        .onAppear { runner.refreshCount(container: NotesRepository.shared.container) }
        .confirmationDialog(TestLibraryRunner.Copy.removeConfirm, isPresented: $confirmRemove, titleVisibility: .visible) {
            Button(TestLibraryRunner.Copy.removeTitle, role: .destructive) {
                let repo = NotesRepository.shared
                runner.remove(container: repo.container, deleteLocalFiles: { memo in
                    let dir = AppPaths.recordingsDirectory
                    if let url = memo.audioURL { try? FileManager.default.removeItem(at: url) }
                    for entry in memo.metadata?.imageManifest ?? [] {
                        try? FileManager.default.removeItem(at: dir.appendingPathComponent(entry.filename))
                    }
                }) {
                    repo.noteStoreDidChangeBySync()
                    NamesCloudSync.run(repo)
                }
            }
        }
    }
}
#endif
