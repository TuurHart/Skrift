import SwiftUI
import SwiftData
import UIKit

/// The "note" screen (mockup2). Swipe left/right between memos (`TabView(.page)`),
/// each page = editable title + RAW transcript (with inline `[[img_NNN]]` embeds)
/// + context/tags. A single playback bar is pinned at the bottom and re-targets
/// as you swipe. Title + tags edits fold in the Review affordances (save-now
/// post-record flow); delete / re-transcribe live in the ⋯ menu.
struct MemoDetailView: View {
    let initialID: UUID

    @Query(sort: \Memo.recordedAt, order: .reverse) private var memos: [Memo]
    @Environment(\.dismiss) private var dismiss
    @State private var selection: UUID
    @State private var showActions = false
    @StateObject private var player = AudioPlayerModel()
    private let repository = NotesRepository.shared

    init(initialID: UUID) {
        self.initialID = initialID
        _selection = State(initialValue: initialID)
    }

    private var currentMemo: Memo? { memos.first { $0.id == selection } }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.skBg.ignoresSafeArea()

            TabView(selection: $selection) {
                ForEach(memos) { memo in
                    MemoPageView(memo: memo, bottomInset: 150)
                        .tag(memo.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            bottomChrome
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showActions = true } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 34, height: 34)
                        .foregroundStyle(Color.skTextDim)
                }
                .accessibilityIdentifier("detail-menu")
            }
        }
        // A confirmationDialog is presented by the view controller (not anchored
        // to the toolbar item), so the paged TabView can't swallow it — unlike a
        // toolbar `Menu`, which silently failed to present on device.
        .confirmationDialog("Memo", isPresented: $showActions, titleVisibility: .hidden) {
            Button("Copy transcript", action: copyTranscript)
            Button("Delete", role: .destructive, action: deleteCurrent)
            Button("Cancel", role: .cancel) {}
        }
        .onAppear { player.load(currentMemo?.audioURL) }
        .onChange(of: selection) { _, newID in
            player.load(memos.first { $0.id == newID }?.audioURL)
        }
        .onDisappear { player.stopAndClear(); repository.save() }
    }

    private var bottomChrome: some View {
        VStack(spacing: 10) {
            if memos.count > 1, memos.count <= 8 {
                PageDots(count: memos.count, index: memos.firstIndex { $0.id == selection } ?? 0)
            }
            PlayerBar(player: player)
        }
        .padding(.horizontal, Theme.Space.margin)
        .padding(.bottom, 24)
        .padding(.top, 12)
        .background(
            LinearGradient(colors: [.skBg, .skBg.opacity(0)], startPoint: .bottom, endPoint: .top)
                .ignoresSafeArea()
        )
    }

    private func copyTranscript() {
        guard let text = currentMemo?.transcript, !text.isEmpty else { return }
        UIPasteboard.general.string = text
    }

    private func deleteCurrent() {
        guard let memo = currentMemo else { return }
        let next = memos.first { $0.id != memo.id }?.id
        if let url = memo.audioURL { try? FileManager.default.removeItem(at: url) }
        memo.metadata?.imageManifest?.forEach {
            try? FileManager.default.removeItem(at: AppPaths.recordingsDirectory.appendingPathComponent($0.filename))
        }
        WordTimingsStore().delete(for: memo.id)
        player.stopAndClear()
        repository.delete(memo)
        if let next { selection = next } else { dismiss() }
    }
}

// MARK: - One page

private struct MemoPageView: View {
    @Bindable var memo: Memo
    let bottomInset: CGFloat
    private let repository = NotesRepository.shared
    @State private var showAddTag = false
    @State private var newTag = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                TextField("", text: titleBinding, prompt: titlePrompt)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color.skText)
                    .tint(.skAccent)
                    .submitLabel(.done)
                    .onSubmit { repository.save() }
                    .accessibilityIdentifier("detail-title")

                FlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(metaChips) { chip in
                        ContextChip(text: chip.text, systemImage: chip.symbol)
                    }
                    ForEach(memo.tags, id: \.self) { tag in
                        Button { removeTag(tag) } label: { TagChip(label: "#\(tag)", style: .applied) }
                    }
                    Button { showAddTag = true } label: { TagChip(label: "+ Tag", style: .add) }
                        .accessibilityIdentifier("add-tag-button")
                }
                .padding(.top, 12)

                TranscriptContentView(memo: memo)
                    .padding(.top, 18)

                Color.clear.frame(height: bottomInset)
            }
            .padding(.horizontal, Theme.Space.margin)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .alert("Add tag", isPresented: $showAddTag) {
            TextField("tag", text: $newTag)
            Button("Add", action: addTag)
            Button("Cancel", role: .cancel) { newTag = "" }
        }
    }

    private var titleBinding: Binding<String> {
        Binding(get: { memo.title ?? "" }, set: { memo.title = $0.isEmpty ? nil : $0 })
    }

    private var titlePrompt: Text {
        Text(memo.firstTranscriptLine ?? "Add a title").foregroundStyle(Color.skTextFaint)
    }

    private func addTag() {
        let t = newTag.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        newTag = ""
        guard !t.isEmpty, !memo.tags.contains(t) else { return }
        memo.tags.append(t)
        repository.save()
    }

    private func removeTag(_ tag: String) {
        memo.tags.removeAll { $0 == tag }
        repository.save()
    }

    private struct MetaChip: Identifiable { let id = UUID(); let text: String; let symbol: String? }

    private var metaChips: [MetaChip] {
        var chips: [MetaChip] = [MetaChip(text: MemoDate.label(memo.recordedAt), symbol: nil)]
        if let place = memo.metadata?.location?.placeName, !place.isEmpty {
            chips.append(MetaChip(text: place, symbol: "mappin.circle.fill"))
        }
        if let w = memo.metadata?.weather {
            chips.append(MetaChip(text: "\(w.temperature)°", symbol: "cloud.sun.fill"))
        }
        if let period = memo.metadata?.dayPeriod {
            chips.append(MetaChip(text: period.label, symbol: period.symbol))
        }
        return chips
    }
}

// MARK: - Transcript (RAW + inline image markers)

private struct TranscriptContentView: View {
    let memo: Memo

    var body: some View {
        if memo.transcriptStatus == .failed, (memo.transcript ?? "").isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                StatusPill(style: .error, label: "Transcription failed", systemImage: "exclamationmark.triangle.fill")
                Text("Re-transcribe from the ⋯ menu.")
                    .font(.footnote).foregroundStyle(Color.skTextDim)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                // Show the pill whenever transcribing — including a re-transcribe
                // of a memo that already has text — so the action gives feedback.
                if memo.transcriptStatus == .transcribing {
                    StatusPill(style: .working, label: "Transcribing")
                }
                ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                    switch seg {
                    case .text(let s):
                        Text(s)
                            .font(.system(size: 15.5))
                            .lineSpacing(4)
                            .foregroundStyle(Color.skText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    case .image(let n):
                        ImageEmbed(url: imageURL(markerIndex: n))
                    }
                }
            }
        }
    }

    private enum Segment { case text(String); case image(Int) }

    private var segments: [Segment] {
        guard let text = memo.transcript, !text.isEmpty else { return [] }
        var result: [Segment] = []
        let ns = text as NSString
        let regex = try? NSRegularExpression(pattern: #"\[\[img_(\d+)\]\]"#)
        var last = 0
        regex?.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match else { return }
            if match.range.location > last {
                let chunk = ns.substring(with: NSRange(location: last, length: match.range.location - last))
                if !chunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.append(.text(chunk.trimmingCharacters(in: .whitespacesAndNewlines))) }
            }
            let num = Int(ns.substring(with: match.range(at: 1))) ?? 0
            result.append(.image(num))
            last = match.range.location + match.range.length
        }
        if last < ns.length {
            let tail = ns.substring(from: last)
            if !tail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.append(.text(tail.trimmingCharacters(in: .whitespacesAndNewlines))) }
        }
        return result.isEmpty ? [.text(text)] : result
    }

    private func imageURL(markerIndex: Int) -> URL? {
        guard let manifest = memo.metadata?.imageManifest, markerIndex >= 1, markerIndex <= manifest.count else { return nil }
        return AppPaths.recordingsDirectory.appendingPathComponent(manifest[markerIndex - 1].filename)
    }
}

/// An inline photo from the transcript markers; placeholder if the file is gone
/// (e.g. seeded demo memos).
private struct ImageEmbed: View {
    let url: URL?

    var body: some View {
        Group {
            if let url, let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable().scaledToFill()
            } else {
                LinearGradient(colors: [Color(hex: 0x2b3350), Color(hex: 0x161a29)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay(Image(systemName: "photo").font(.title).foregroundStyle(Color.skTextFaint))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 160)
        .clipShape(.rect(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle.sk(14).stroke(Color.skBorder, lineWidth: 1))
    }
}

// MARK: - Player bar

private struct PlayerBar: View {
    @ObservedObject var player: AudioPlayerModel

    var body: some View {
        VStack(spacing: 10) {
            Slider(value: Binding(
                get: { player.currentTime },
                set: { player.seek(to: $0) }
            ), in: 0...max(player.duration, 0.01))
            .tint(.skAccent)
            .disabled(!player.hasAudio)

            HStack {
                Text(timeString(player.currentTime))
                Spacer()
                Text(timeString(player.duration))
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.skTextDim)

            HStack(spacing: 34) {
                Button { player.skip(-10) } label: {
                    skipLabel("gobackward.10")
                }
                .accessibilityIdentifier("skip-back-button")

                Button { player.togglePlay() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white)
                        .frame(width: 60, height: 60)
                        .background(Color.skAccent, in: .circle)
                        .shadow(color: .skAccent.opacity(0.4), radius: 10, y: 6)
                }
                .accessibilityIdentifier("play-button")
                .disabled(!player.hasAudio)

                Button { player.skip(10) } label: {
                    skipLabel("goforward.10")
                }
                .accessibilityIdentifier("skip-fwd-button")
            }
            .foregroundStyle(Color.skText)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .trailing) {
                Button { player.cycleRate() } label: {
                    Text(rateLabel)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.skText)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(Color.skSurface, in: .rect(cornerRadius: 9, style: .continuous))
                        .overlay(RoundedRectangle.sk(9).stroke(Color.skBorder, lineWidth: 1))
                }
                .accessibilityIdentifier("speed-button")
            }
        }
    }

    private func skipLabel(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 24))
    }

    private var rateLabel: String {
        player.rate == 1 ? "1×" : (player.rate == 1.5 ? "1.5×" : "2×")
    }

    private func timeString(_ t: TimeInterval) -> String {
        guard t.isFinite else { return "0:00" }
        let total = Int(t)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Page dots

private struct PageDots: View {
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == index ? Color.skAccent : Color.skTextFaint)
                    .frame(width: i == index ? 18 : 6, height: 6)
            }
        }
        .animation(Theme.Motion.snappy, value: index)
    }
}
