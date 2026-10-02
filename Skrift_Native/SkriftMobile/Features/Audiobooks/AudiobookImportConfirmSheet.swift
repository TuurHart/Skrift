import SwiftUI

/// One-time editable confirm sheet, shown ONLY when the file's tags were
/// missing (locked design: import asks nothing otherwise).
struct AudiobookImportConfirmSheet: View {
    let pending: PendingAudiobookImport
    var onConfirm: (Audiobook) -> Void
    var onCancel: () -> Void

    @State private var title: String
    @State private var author: String

    init(pending: PendingAudiobookImport,
         onConfirm: @escaping (Audiobook) -> Void,
         onCancel: @escaping () -> Void) {
        self.pending = pending
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _title = State(initialValue: pending.book.title)
        _author = State(initialValue: pending.book.author)
    }

    var body: some View {
        ZStack {
            Color.skBg.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    BookCoverView(book: pending.book)
                        .frame(width: 54, height: 54)
                        .clipShape(.rect(cornerRadius: 9, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Confirm book details")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.skText)
                        Text("This file’s tags were incomplete — fill in what’s missing.")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.skTextDim)
                    }
                }

                LabeledTextField(label: "Title", text: $title, id: "import-title")
                LabeledTextField(label: "Author", text: $author, id: "import-author")

                CancelConfirmRow(confirmTitle: "Add to Library", cancelID: "import-cancel",
                                 confirmID: "import-confirm", onCancel: onCancel) {
                    var book = pending.book
                    book.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    book.author = author.trimmingCharacters(in: .whitespacesAndNewlines)
                    if book.title.isEmpty { book.title = pending.book.title }
                    onConfirm(book)
                }
                Spacer(minLength: 0)
            }
            .padding(Theme.Space.margin)
        }
        .interactiveDismissDisabled()
    }
}
