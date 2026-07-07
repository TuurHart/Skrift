import SwiftUI
import SwiftData

/// The trash (Apple Voice Memos' "Recently Deleted"): memos soft-deleted from
/// the list, each with a days-remaining countdown. Swipe (or long-press) a row
/// to Restore or Delete Now; everything else is purged automatically at startup
/// after `TrashPolicy.retentionDays`. Presented as a sheet from the memos list.
struct RecentlyDeletedView: View {
    @Query(filter: #Predicate<Memo> { $0.deletedAt != nil },
           sort: [SortDescriptor(\Memo.deletedAt, order: .reverse)])
    private var memos: [Memo]
    @Environment(\.dismiss) private var dismiss
    private let repository = NotesRepository.shared

    /// The memo a Delete-Now is pending confirmation for.
    @State private var confirmDelete: Memo?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.skBg.ignoresSafeArea()
                if memos.isEmpty { emptyState } else { list }
            }
            .navigationTitle("Recently Deleted")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("trash-done-button")
                }
            }
            .confirmationDialog(
                "Delete this note permanently? Its audio and photos will be gone for good.",
                isPresented: Binding(
                    get: { confirmDelete != nil },
                    set: { if !$0 { confirmDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete Now", role: .destructive) {
                    if let memo = confirmDelete { repository.permanentlyDelete(memo) }
                    confirmDelete = nil
                }
                .accessibilityIdentifier("trash-confirm-delete-button")
                Button("Cancel", role: .cancel) { confirmDelete = nil }
            }
        }
    }

    private var list: some View {
        List {
            Section {
                ForEach(memos) { memo in
                    TrashRow(memo: memo)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button { repository.restore(memo) } label: {
                                Label("Restore", systemImage: "arrow.uturn.backward")
                            }
                            .tint(.skAccent)
                            .accessibilityIdentifier("trash-restore-button")
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { confirmDelete = memo } label: {
                                Label("Delete Now", systemImage: "trash")
                            }
                            .accessibilityIdentifier("trash-delete-now-button")
                        }
                        .contextMenu {
                            Button { repository.restore(memo) } label: {
                                Label("Restore", systemImage: "arrow.uturn.backward")
                            }
                            Button(role: .destructive) { confirmDelete = memo } label: {
                                Label("Delete Now", systemImage: "trash")
                            }
                        }
                }
            } footer: {
                Text("Notes are kept for \(TrashPolicy.retentionDays) days, then deleted permanently.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.skTextFaint)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 8)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("trash-list")
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "Nothing here",
            systemImage: "trash",
            description: Text("Deleted notes are kept for \(TrashPolicy.retentionDays) days before being removed for good.")
        )
        .accessibilityIdentifier("trash-empty")
    }
}

// MARK: - Row

/// A trashed memo: title + when it was recorded, with the purge countdown.
/// No tap-through to detail — the memo is deleted; Restore brings it back.
private struct TrashRow: View {
    let memo: Memo

    var body: some View {
        HStack(spacing: 11) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(MemoDate.label(memo.recordedAt))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Color.skTextFaint)
                    Spacer()
                    if let countdown = memo.trashCountdownLabel() {
                        Text(countdown)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.skRed)
                    }
                }
                Text(memo.displayTitle)
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(Color.skText)
                    .lineLimit(1)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
                Text(memo.durationLabel)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.skTextDim)
                    .padding(.top, 4)
            }
        }
        .skCard()
    }
}
