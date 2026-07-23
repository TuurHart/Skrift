import SwiftUI

/// A0 — the import-moment prompt (mock `mocks/book-text-unified.html`, signed off
/// 2026-07-23; Tuur: "when you upload something, it should probably tell you you can
/// do both at the same time"). Appears ONCE per book, right after import confirms,
/// offering both text actions together: ① start the on-device transcribe, ② add the
/// ePub (which waits and matches up on its own). Skipping is just dismissing — the
/// footer says where everything lives from then on ("Text…"). The chain
/// (import → transcribe → auto-match on finish) already works in the runner; this
/// sheet only makes it VISIBLE.
struct BookTextPromptSheet: View {
    let book: Audiobook
    /// Dismiss A0 and open the unified "Text" sheet with its Add flow (the picker
    /// lives on that sheet — BookTextFlow's iOS-26 presentation rule).
    var onAddText: () -> Void

    @ObservedObject private var job = BookTranscriptionJob.shared
    @Environment(\.dismiss) private var dismiss

    private var transcribingThisBook: Bool {
        job.activeBookID == book.id && job.isRunningOrPaused
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule().fill(Color.skBorder).frame(width: 36, height: 4)
                .frame(maxWidth: .infinity).padding(.top, 8).padding(.bottom, 14)

            Text("Give this book text")
                .font(.system(size: 16, weight: .bold)).foregroundStyle(Color.skText)
                .padding(.bottom, 2)
            Text("Import is done. Add its words now — you can start both together and walk away.")
                .font(.system(size: 11.5)).foregroundStyle(Color.skTextFaint)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 16)

            card {
                Text("① Transcribe the audio")
                    .font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Color.skText)
                Text(transcribeMeta)
                    .font(.system(size: 11.5)).foregroundStyle(Color.skTextDim)
                    .fixedSize(horizontal: false, vertical: true)
                if transcribingThisBook {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 13))
                        Text("Transcribing").font(.system(size: 12.5, weight: .semibold))
                    }
                    .foregroundStyle(Color.skAccent)
                    .padding(.top, 8)
                } else {
                    Button { job.start(book: book) } label: {
                        Text("Start transcribing")
                            .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Color.skAccent, in: RoundedRectangle.sk(10))
                    }
                    .padding(.top, 7)
                    .accessibilityIdentifier("book-text-prompt-transcribe")
                }
            }

            card {
                (Text("② Add the real book ").foregroundStyle(Color.skText)
                 + Text("(optional)").foregroundStyle(Color.skTextFaint).fontWeight(.regular))
                    .font(.system(size: 13.5, weight: .semibold))
                Text("Have the ePub? Add it now — it waits for the transcript and matches up on its own the moment transcription finishes. Published words, real chapters.")
                    .font(.system(size: 11.5)).foregroundStyle(Color.skTextDim)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    dismiss()
                    onAddText()
                } label: {
                    Text("Add book text…")
                        .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Color.skAccent)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(
                            RoundedRectangle.sk(10)
                                .strokeBorder(Color.skAccent.opacity(0.9), lineWidth: 1.5)
                        )
                }
                .padding(.top, 7)
                .accessibilityIdentifier("book-text-prompt-add")
            }

            Text("Both run in the background — keep listening meanwhile.\nSkip this now and find it any time under \u{201C}Text…\u{201D}.")
                .font(.system(size: 10.5)).foregroundStyle(Color.skTextFaint)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.margin)
        .background(Color.skSurface.ignoresSafeArea())
        .presentationDetents([.medium])
        .accessibilityIdentifier("book-text-prompt")
    }

    /// Same never-fabricate rule as the unified sheet: the per-book estimate appears
    /// only once the job has a measured per-device rate.
    private var transcribeMeta: String {
        var line = "Works for every book, fully on-device. Read-along, captures and chapters come from this"
        if let eta = job.estimatedRemainingSeconds(for: book), eta > 1 {
            line += ". ≈ \(TranscribeBookView.shortDuration(eta)) for this book"
        }
        return line + "."
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 3, content: content)
            .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.skElev, in: RoundedRectangle.sk(14))
            .padding(.bottom, 12)
    }
}

/// Once-ever bookkeeping for A0 — a plain per-device UserDefaults set (deliberately
/// NOT an `Audiobook` field: the record's local-only sync doctrine exists because
/// additive fields get erased by older writers; a UI-once flag has no business in
/// the store at all).
enum BookTextPrompt {
    static let defaultsKey = "bookTextPromptSeen"

    static func seen(_ bookID: UUID, defaults: UserDefaults = .standard) -> Bool {
        (defaults.stringArray(forKey: defaultsKey) ?? []).contains(bookID.uuidString)
    }

    static func markSeen(_ bookID: UUID, defaults: UserDefaults = .standard) {
        var ids = defaults.stringArray(forKey: defaultsKey) ?? []
        guard !ids.contains(bookID.uuidString) else { return }
        ids.append(bookID.uuidString)
        defaults.set(ids, forKey: defaultsKey)
    }
}
