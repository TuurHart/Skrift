import PhotosUI
import SwiftUI

/// "Edit book details" (player ⋯ menu — device finding 2026-06-12: the user
/// expected to fix a wrong title/author/cover AFTER import). Edits title,
/// author and the cover: the cover picks from the photo library
/// (PhotosPicker) and falls back to the current art until one is chosen.
/// Saving persists through the library store; the live session refreshes in
/// place (player UI, mini-player, lock-screen Now Playing) — playback
/// position and transport are untouched.
struct EditBookDetailsView: View {
    let book: Audiobook

    @Environment(\.dismiss) private var dismiss
    private let store = AudiobookLibraryStore.shared

    @State private var title: String
    @State private var author: String
    @State private var pickedCover: PhotosPickerItem?
    @State private var newCoverImage: UIImage?

    init(book: Audiobook) {
        self.book = book
        _title = State(initialValue: book.title)
        _author = State(initialValue: book.author)
    }

    var body: some View {
        ZStack {
            Color.skBg.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                Text("Edit book details")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.skText)

                coverRow

                field("Title", text: $title, id: "edit-book-title")
                field("Author", text: $author, id: "edit-book-author")

                HStack(spacing: 8) {
                    Button("Cancel") { dismiss() }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.skTextDim)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .overlay(RoundedRectangle.sk(11).stroke(Color.skBorder, lineWidth: 1))
                        .accessibilityIdentifier("edit-book-cancel")

                    Button {
                        save()
                    } label: {
                        Text("Save")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Color.skAccent, in: .rect(cornerRadius: 11, style: .continuous))
                    }
                    .accessibilityIdentifier("edit-book-save")
                }

                Spacer(minLength: 0)
            }
            .padding(Theme.Space.margin)
        }
        .onChange(of: pickedCover) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    newCoverImage = image
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("edit-book-sheet")
    }

    // MARK: - Cover

    private var coverRow: some View {
        HStack(spacing: 12) {
            // The picked image previews immediately; otherwise the CURRENT
            // art (or placeholder) stays — the fallback the user expects.
            Group {
                if let newCoverImage {
                    Image(uiImage: newCoverImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    BookCoverView(book: book)
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(.rect(cornerRadius: 10, style: .continuous))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                PhotosPicker(selection: $pickedCover, matching: .images) {
                    HStack(spacing: 5) {
                        Image(systemName: "photo")
                            .font(.system(size: 11))
                        Text("Change cover")
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .foregroundStyle(Color.skAccentText)
                    .padding(.horizontal, 11).padding(.vertical, 6)
                    .background(Color.skAccentSoft, in: .capsule)
                }
                .accessibilityIdentifier("edit-book-cover")

                Text(newCoverImage == nil
                    ? "Pick from Photos — keeps the current art until you do."
                    : "New cover selected — Save to apply.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.skTextFaint)
            }
            Spacer(minLength: 0)
        }
    }

    private func field(_ label: String, text: Binding<String>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.5)
                .foregroundStyle(Color.skTextFaint)
            TextField(label, text: text)
                .font(.system(size: 14))
                .foregroundStyle(Color.skText)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(Color.skElev, in: .rect(cornerRadius: Theme.Radius.field, style: .continuous))
                .accessibilityIdentifier(id)
        }
    }

    // MARK: - Save

    private func save() {
        // Edit the FRESHEST record — the position keeps ticking while this
        // sheet is up (the session persists progress through the store).
        var updated = store.book(id: book.id) ?? book
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty { updated.title = trimmedTitle }
        updated.author = author.trimmingCharacters(in: .whitespacesAndNewlines)

        if let image = newCoverImage, let data = image.jpegData(compressionQuality: 0.9) {
            let folder = store.folder(for: updated.id)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let coverURL = folder.appendingPathComponent("cover.jpg")
            if (try? data.write(to: coverURL, options: .atomic)) != nil {
                updated.hasCover = true
                BookCoverCache.invalidate(updated.id)
            }
        }

        store.update(updated)
        AudiobookSession.shared.refreshFromStore()
        dismiss()
    }
}
