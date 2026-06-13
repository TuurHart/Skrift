import SwiftUI
import SwiftData

/// Desktop "Recently Deleted" — the trash restore surface, mirroring the phone's
/// `RecentlyDeletedView` (Apple Voice Memos): soft-deleted notes with a
/// days-remaining countdown, each Restore-able or Delete-Now-able; the rest are
/// purged automatically at launch after `DesktopTrashPolicy.retentionDays`.
/// Presented as a sheet from the sidebar footer.
struct RecentlyDeletedView: View {
    let files: [PipelineFile]
    var onClose: () -> Void = {}
    /// Snapshot mode renders without a ScrollView (ImageRenderer can't lay out
    /// scroll contents) and as plain Text for the action buttons.
    var interactive = true
    @Environment(\.modelContext) private var ctx

    @State private var confirmDelete: PipelineFile?

    var body: some View {
        VStack(spacing: 0) {
            header
            if files.isEmpty {
                emptyState
            } else if interactive {
                ScrollView { rows }
            } else {
                rows
                Spacer(minLength: 0)
            }
        }
        .frame(width: 460, height: interactive ? 520 : nil)
        .background(Theme.bg)
        .accessibilityIdentifier("trash.root")
    }

    private var header: some View {
        HStack {
            Text("Recently Deleted")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            Spacer()
            Button(action: onClose) {
                Text("Done").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("trash.done")
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline.opacity(0.07)).frame(height: 0.5) }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "trash").font(.system(size: 28)).foregroundStyle(Theme.textMuted)
            Text("Nothing here").font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.textSecondary)
            Text("Deleted notes appear here for \(DesktopTrashPolicy.retentionDays) days before they’re removed for good.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.textMuted)
                .multilineTextAlignment(.center).frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(files) { file in
                row(file)
                Rectangle().fill(Theme.hairline.opacity(0.06)).frame(height: 0.5)
            }
        }
        .alert("Delete permanently?",
               isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })) {
            Button("Delete Now", role: .destructive) {
                if let f = confirmDelete { DesktopTrash.deleteForever([f], in: ctx) }
                confirmDelete = nil
            }
            Button("Cancel", role: .cancel) { confirmDelete = nil }
        } message: {
            Text("This removes the note and its audio from disk. This can’t be undone.")
        }
    }

    private func row(_ file: PipelineFile) -> some View {
        let days = file.trashDaysRemaining()
        return HStack(spacing: 11) {
            Image(systemName: file.sourceSymbol)
                .font(.system(size: 12)).foregroundStyle(Theme.textMuted)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.queueTitle)
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(days == 0 ? "Removed today" : "\(days) day\(days == 1 ? "" : "s") left")
                    .font(.system(size: 11)).foregroundStyle(Theme.textMuted)
            }
            Spacer(minLength: 8)
            if interactive {
                Button("Restore") { DesktopTrash.restore([file], in: ctx) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Theme.accent)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
                    .accessibilityIdentifier("trash.restore")
                Button { confirmDelete = file } label: {
                    Image(systemName: "trash").font(.system(size: 11))
                        .foregroundStyle(Theme.destructive)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(Theme.destructive.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("trash.delete-now")
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
    }
}
