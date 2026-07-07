import SwiftUI

/// The memo picker behind the editor's `[[` trigger (chunk 5): search-as-you-
/// type over titles + first lines, most recent first, current memo excluded.
/// Picking inserts a `[[memo:UUID|Title]]` chip at the trigger.
struct MemoLinkPickerSheet: View {
    /// (id, display title, date line) — prepared by the page.
    let candidates: [(id: UUID, title: String, subtitle: String)]
    var onPick: (UUID, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [(id: UUID, title: String, subtitle: String)] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return candidates }
        return candidates.filter {
            $0.title.lowercased().contains(q) || $0.subtitle.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.skBg.ignoresSafeArea()
                List(filtered, id: \.id) { row in
                    Button {
                        onPick(row.id, row.title)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.title)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Color.skText)
                                .lineLimit(1)
                            Text(row.subtitle)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.skTextDim)
                                .lineLimit(1)
                        }
                        .padding(.vertical, 2)
                    }
                    .listRowBackground(Color.skSurface)
                }
                .scrollContentBackground(.hidden)
                .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                            prompt: "Search notes")
                .accessibilityIdentifier("memo-link-picker")
            }
            .navigationTitle("Link a note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
