import SwiftUI
import UIKit

/// Q353 (D90, Q6 mock door "Podcast or episode"): paste an Apple Podcasts or Spotify link, or a feed
/// address. Skrift finds the show's public feed, downloads the episode's MP3 into the Library and
/// says plainly when a show has no public feed. A show link (no episode named) lists recent
/// episodes to pick from.
struct PodcastLinkSheet: View {
    /// Called with the finished record; the caller adds it to the store.
    let onAdd: (Audiobook) -> Void
    /// Q356: a podcast link shared from another app (`PodcastLinkArrival`); looked up on appear.
    var initialLink: String? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var phase: Phase = .idle
    @FocusState private var focused: Bool

    private enum Phase: Equatable {
        case idle
        case looking
        case choosing(PodcastShow)
        case downloading(String)
        case refused(String)

        static func == (a: Phase, b: Phase) -> Bool {
            switch (a, b) {
            case (.idle, .idle), (.looking, .looking): true
            case (.choosing(let x), .choosing(let y)): x == y
            case (.downloading(let x), .downloading(let y)): x == y
            case (.refused(let x), .refused(let y)): x == y
            default: false
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add a podcast episode")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Color.skText)
                .accessibilityAddTraits(.isHeader)
            Text("Paste a link from Apple Podcasts or Spotify, or a feed address. Skrift uses the show's public feed.")
                .font(.system(size: 13))
                .foregroundStyle(Color.skTextDim)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                TextField("https://", text: $text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .focused($focused)
                    .submitLabel(.go)
                    .onSubmit(go)
                    .font(.system(size: 15))
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(Color.skElev, in: .rect(cornerRadius: 10, style: .continuous))
                    .accessibilityIdentifier("podcast-link-field")
                Button("Paste") {
                    if let s = UIPasteboard.general.string { text = s }
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.skAccentText)
                .accessibilityIdentifier("podcast-link-paste")
            }

            content

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.margin)
        .padding(.top, 22)
        .padding(.bottom, 12)
        .background(Color.skBg.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("podcast-link-sheet")
        .onAppear {
            // Q356: a link shared from another app arrives here and is looked up at once.
            if let initialLink, !initialLink.isEmpty {
                text = initialLink
                go()
                return
            }
            // Prefill from the clipboard only when it already holds a link.
            if text.isEmpty, let s = UIPasteboard.general.string, PodcastLink.classify(s) != nil { text = s }
            focused = text.isEmpty
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .idle:
            primary("Add episode", enabled: !text.trimmingCharacters(in: .whitespaces).isEmpty, action: go)
        case .looking:
            status("Finding the show's feed…")
        case .downloading(let title):
            status("Downloading \u{201C}\(title)\u{201D}…")
        case .refused(let message):
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(Color.skText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.skSurface, in: .rect(cornerRadius: 12, style: .continuous))
                .accessibilityIdentifier("podcast-link-refusal")
            primary("Try another link", enabled: true) { phase = .idle; focused = true }
        case .choosing(let show):
            Text("\(show.title) — pick an episode")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.skTextDim)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(show.episodes.prefix(30))) { episode in
                        Button { start(show, episode) } label: { episodeRow(episode) }
                            .buttonStyle(.plain)
                        Rectangle().fill(Color.skBorder).frame(height: 0.5)
                    }
                }
            }
            .accessibilityIdentifier("podcast-episode-list")
        }
    }

    private func episodeRow(_ episode: PodcastEpisode) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(episode.title)
                .font(.system(size: 14.5, weight: .medium))
                .foregroundStyle(Color.skText)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(Self.detail(episode))
                .font(.system(size: 11.5))
                .foregroundStyle(Color.skTextFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    static func detail(_ episode: PodcastEpisode) -> String {
        var parts: [String] = []
        if let d = episode.publishedAt { parts.append(d.formatted(.dateTime.day().month(.abbreviated).year())) }
        if let t = episode.duration { parts.append("\(Int((t / 60).rounded())) min") }
        return parts.joined(separator: " · ")
    }

    private func status(_ message: String) -> some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(message).font(.system(size: 14)).foregroundStyle(Color.skTextDim)
        }
        .padding(.vertical, 6)
    }

    private func primary(_ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(enabled ? Color.skAccent : Color.skAccent.opacity(0.35),
                            in: .rect(cornerRadius: 12, style: .continuous))
        }
        .disabled(!enabled)
        .accessibilityIdentifier("podcast-link-add")
    }

    // MARK: - Actions

    private func go() {
        guard case .idle = phase, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        focused = false
        phase = .looking
        let input = text
        Task {
            do {
                switch try await PodcastImporter.resolve(input) {
                case .episode(let show, let episode): start(show, episode)
                case .chooseEpisode(let show): phase = .choosing(show)
                }
            } catch {
                phase = .refused(Self.sentence(error))
            }
        }
    }

    private func start(_ show: PodcastShow, _ episode: PodcastEpisode) {
        phase = .downloading(episode.title)
        Task {
            do {
                let book = try await PodcastImporter.download(show: show, episode: episode,
                                                              libraryDirectory: AudiobookLibraryStore.shared.directory)
                onAdd(book)
                dismiss()
            } catch {
                phase = .refused(Self.sentence(error))
            }
        }
    }

    /// A refusal already is one plain sentence; anything else (network, unreadable file) gets one.
    private static func sentence(_ error: Error) -> String {
        if let refusal = error as? PodcastRefusal { return refusal.message }
        if error is URLError { return "Skrift couldn't reach that link, check the connection and try again." }
        return "Skrift couldn't download that episode."
    }
}
