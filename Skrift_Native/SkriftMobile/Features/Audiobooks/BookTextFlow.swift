import SwiftUI
import UniformTypeIdentifiers

/// 📖 The ONE "Book text" presentation bundle — the sheet (mock `book-text-sheet.html`
/// variant B), its Add fileImporter, the busy message, and the three outcome alerts —
/// as a modifier, so every surface with a "Book text…" verb (the library's long-press
/// menu AND the player's ⋯ menu, device finding 2026-07-22: "it doesn't show here")
/// presents the identical flow from one implementation. Shared-code-first: this was
/// extracted verbatim from AudiobookLibraryView, which now applies it like the player.
///
/// Usage: hold `@State private var bookTextBook: Audiobook?`, set it from the verb,
/// apply `.bookTextFlow(book: $bookTextBook)`.
struct BookTextFlow: ViewModifier {
    @Binding var sheetBook: Audiobook?

    /// Which book the in-flight fileImporter pick resolves onto (captured at Add-tap
    /// so a re-presented sheet can't cross wires).
    @State private var attachBook: Audiobook?
    @State private var showImporter = false
    /// Busy line rendered INSIDE the sheet (a plain overlay on the presenting view is
    /// invisible once the sheet covers it; alerts/importers stack over it natively).
    @State private var busyMessage: String?
    /// Success/partial outcome — an ALERT (2026-07-22 device round: a 1.6 s toast
    /// read as "nothing happened").
    @State private var outcome: String?
    /// The picked file couldn't be read/copied at all (I/O-level failure).
    @State private var attachError: String?
    /// Every file's verdict came back rejected; carries the just-attached filename so
    /// Remove detaches exactly that text (multi-text semantics).
    @State private var rejected: (book: Audiobook, filename: String)?

    /// ePub (falling back to its raw UTI if the extension lookup ever fails)
    /// + plain text — a book's text can arrive either way.
    static let attachTypes: [UTType] = {
        var types: [UTType] = []
        if let epub = UTType(filenameExtension: "epub") ?? UTType("org.idpf.epub-container") {
            types.append(epub)
        }
        types.append(.plainText)
        return types
    }()

    func body(content: Content) -> some View {
        content
            .sheet(item: $sheetBook) { book in
                BookTextSheet(book: book, busyMessage: busyMessage) {
                    attachBook = book
                    showImporter = true
                }
                // The picker + alerts hang OFF THE SHEET's own content (device finding
                // 2026-07-22: "that button does not function" — a fileImporter attached
                // to the covered presenting view silently refuses to present on iOS 26;
                // presentations must originate from the topmost presented controller).
                .fileImporter(isPresented: $showImporter, allowedContentTypes: Self.attachTypes) { result in
                    guard let book = attachBook, case .success(let url) = result else { return }
                    Task { await runAttach(url: url, book: book) }
                }
                .bookTextAlerts(outcome: $outcome, attachError: $attachError, rejected: $rejected)
            }
    }

    private func runAttach(url: URL, book: Audiobook) async {
        // The busy message persists for the whole run and follows the runner's live
        // stages (a 13 h book's matching takes minutes — a static line read as hung,
        // Tuur 2026-07-22); outcomes are explicit, user-dismissed alerts.
        withAnimation(.easeOut(duration: 0.2)) { busyMessage = "Checking the text against this audiobook…" }
        defer { withAnimation(.easeIn(duration: 0.3)) { busyMessage = nil } }
        do {
            let summary = try await BookAlignmentRunner.attach(bookFileAt: url, bookID: book.id) { stage in
                Task { @MainActor in busyMessage = stage }
            }
            if summary.deferredWhileTranscribing {
                outcome = "This book is still transcribing. The text is saved — it will match up on its own the moment transcription finishes."
            } else if summary.totalFiles == 0 {
                outcome = "No transcript yet — the text will align on its own when transcription finishes."
            } else if summary.alignedFiles == 0 {
                rejected = (book, url.lastPathComponent)
            } else if summary.alignedFiles == summary.totalFiles {
                outcome = summary.totalFiles == 1
                    ? "The text matches this audiobook. Read-along and quote captures now use the book\u{2019}s own words, and chapters come from its real table of contents."
                    : "All \(summary.totalFiles) files match this text. Read-along and quote captures now use the book\u{2019}s own words, and chapters come from its real table of contents."
            } else {
                outcome = "The text matches \(summary.alignedFiles) of \(summary.totalFiles) audio files — most likely one book of a multi-book audiobook. Where it matches, read-along and captures use the published text and chapters come from its table of contents; the other files keep the transcript."
            }
        } catch {
            attachError = error.localizedDescription
        }
    }
}

extension View {
    /// Attach the full "Book text" flow (sheet + picker + alerts) to this surface.
    func bookTextFlow(book: Binding<Audiobook?>) -> some View {
        modifier(BookTextFlow(sheetBook: book))
    }

    /// The three attach-outcome alerts, hung off the SHEET's content (they must
    /// originate from the topmost presented controller to show over it).
    func bookTextAlerts(outcome: Binding<String?>, attachError: Binding<String?>,
                        rejected: Binding<(book: Audiobook, filename: String)?>) -> some View {
        self
            .alert("Book text attached", isPresented: .init(
                get: { outcome.wrappedValue != nil },
                set: { if !$0 { outcome.wrappedValue = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(outcome.wrappedValue ?? "")
            }
            .alert("Couldn\u{2019}t attach book text", isPresented: .init(
                get: { attachError.wrappedValue != nil },
                set: { if !$0 { attachError.wrappedValue = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(attachError.wrappedValue ?? "")
            }
            // "Keep anyway" (.cancel role → the alert's default/bold treatment) leaves it
            // attached in case a later re-transcribe changes the picture; "Remove" detaches
            // exactly THIS text via `removeText` (other attached texts untouched).
            .alert("This doesn\u{2019}t look like this audiobook\u{2019}s text", isPresented: .init(
                get: { rejected.wrappedValue != nil },
                set: { if !$0 { rejected.wrappedValue = nil } }
            ), presenting: rejected.wrappedValue.map(\.book)) { _ in
                Button("Keep anyway", role: .cancel) {}
                Button("Remove", role: .destructive) {
                    if let r = rejected.wrappedValue {
                        Task { await BookAlignmentRunner.removeText(filename: r.filename, bookID: r.book.id) }
                    }
                }
            } message: { _ in
                Text("Checking it against the transcript didn\u{2019}t find a match. You can keep it and try again later, or remove it now.")
            }
    }
}
