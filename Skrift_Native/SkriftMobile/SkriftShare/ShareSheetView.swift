import SwiftUI
import UIKit

/// The share sheet UI — mock state 1 (`mocks/capture-items.html`).
///
/// Layout (bottom sheet, dark):
///   - Grab handle
///   - "Save to Skrift" header + ✕ dismiss
///   - Preview block: link card (URL) / italic quote (text) / thumbnail (image)
///   - Annotation TextEditor with placeholder
///   - Significance circles + sync line
///   - Save button
///
/// On Save → builds a `CaptureInboxEntry` → calls `onSave` (which writes to
/// CaptureInbox and completes the extension context).
struct ShareSheetView: View {
    let payload: SharePayload
    /// Entries to write (1 for everything except audio-split, where each clip
    /// becomes its own entry) + the image datas aligned to `imageFileNames`.
    let onSave: (_ entries: [CaptureInboxEntry], _ imageDatas: [Data], _ dictationData: Data?) -> Void
    let onCancel: () -> Void

    @State private var annotation: String = ""
    @State private var significance: Double = 0
    @FocusState private var annotationFocused: Bool
    /// B1 chooser: N shared voice notes → one note (default, clips merged in
    /// order) or N separate notes. Only shown when 2+ audio clips arrived.
    @State private var combineIntoOne = true
    /// E2 audio-length routing: a clip running ≥ 1 hour (user-locked threshold)
    /// defaults to the Books tab (read-along) instead of a transcribed memo —
    /// overridable per share via the routing chooser.
    @State private var sendToBooks = false

    /// Any clip at/over the 1-hour threshold → the Books routing chooser shows.
    private var hasLongClip: Bool {
        payload.audioItems.contains { ($0.duration ?? 0) >= 3600 }
    }

    // TextEditor placeholder state
    private var annotationIsEmpty: Bool { annotation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        // Dark surface card, same style as the mock sheet
        ZStack(alignment: .bottom) {
            // Backdrop above the card. OPAQUE dark: a translucent scrim would
            // wash out over the host sheet's light-gray backdrop (we render in
            // a remote view — the page behind is never visible to us anyway).
            // Tap = dismiss the keyboard first; only a tap with no keyboard up
            // cancels (so a stray tap can't eat a typed annotation).
            Color(red: 0.055, green: 0.059, blue: 0.086)   // #0e0f16
                .ignoresSafeArea()
                .onTapGesture {
                    if annotationFocused { annotationFocused = false } else { onCancel() }
                }

            sheetContent
        }
        // Prefer dark regardless of system setting — the sheet always uses the dark palette.
        // (Belt only: the real enforcement is overrideUserInterfaceStyle in ShareViewController.)
        .preferredColorScheme(.dark)
    }

    // MARK: - Sheet

    private var sheetContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // No grab handle of our own: the system share-extension sheet
            // already draws one — two stacked handles read as broken chrome.
            headerRow
                .padding(.top, 14)
                .padding(.bottom, 13)
            previewBlock
                .padding(.bottom, 11)
            // Audio shares carry NO ramble UI (signed 2026-07-10): the voice note
            // IS the content — thoughts get appended inside the note later. The
            // sheet is just: what's coming in → significance → Save.
            if !payload.isAudio {
                annotationField
                    .padding(.bottom, 12)
            }
            SignificanceCircles(value: $significance) {}
                .padding(.bottom, 13)
            saveButton
                // UIApplication.shared is unavailable in app extensions — SwiftUI's
                // own safe-area handling covers the home-indicator inset; this is
                // just comfortable breathing room above it.
                .padding(.bottom, 16)
        }
        .padding(.horizontal, 16)
        .background(
            // Sheet surface: slightly elevated above the scrim.
            // `.container` only — ignoring the whole bottom safe area would
            // also ignore the KEYBOARD region, leaving the circles + Save
            // buried under the keyboard while typing (the 2026-06-12 finding).
            Color(red: 0.106, green: 0.110, blue: 0.157)   // #1b1d28 per mock
                .ignoresSafeArea(.container, edges: .bottom)
                .clipShape(.rect(topLeadingRadius: 22, topTrailingRadius: 22, style: .continuous))
        )
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 0.5)
                .ignoresSafeArea(.container, edges: .bottom)
        }
        .shadow(color: .black.opacity(0.5), radius: 36, y: -10)
    }

    // MARK: - Sub-views

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 8) {
            // "Sk" monogram mark, matching the mock's `.mk` gradient block
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x8e7dff), Color(hex: 0x6a59ef)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 24, height: 24)
                .overlay(
                    Text("Sk")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(.white)
                )
                .shadow(color: Color.skAccent.opacity(0.45), radius: 4, y: 1)
                .accessibilityHidden(true)

            Text(sheetTitle)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.skText)
                .lineLimit(1)

            Spacer()

            Button { onCancel() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.skTextDim)
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.07), in: .circle)
            }
            .accessibilityLabel("Dismiss")
            .accessibilityIdentifier("share-sheet-dismiss")
        }
    }

    /// Sheet title: counts the incoming items so a multi-share says out loud what
    /// will happen ("4 photos → one note", "8 voice notes · 6:12" — signed mock).
    private var sheetTitle: String {
        // B3: a mixed bundle spells out everything that will land in the one note.
        if payload.isAudio, isMixedBundle {
            let clips = payload.audioItems.count
            var parts = [clips == 1 ? "1 voice note" : "\(clips) voice notes"]
            let photos = payload.imageItems.count
            if photos > 0 { parts.append(photos == 1 ? "1 photo" : "\(photos) photos") }
            if payload.text?.isEmpty == false { parts.append("text") }
            return parts.joined(separator: " + ") + " → one note"
        }
        if payload.isAudio, payload.audioItems.count > 1 {
            let known = payload.audioItems.compactMap(\.duration)
            let total = known.reduce(0, +)
            let suffix = known.isEmpty ? "" : " · \(fmtDuration(total))"
            return "\(payload.audioItems.count) voice notes\(suffix)"
        }
        if payload.type == .image, payload.imageItems.count > 1 {
            return "\(payload.imageItems.count) photos → one note"
        }
        return "Save to Skrift"
    }

    /// B3: photos and/or chat text arrived WITH the voice notes — one note takes
    /// everything, so the 1-or-N chooser hides (like the Books route).
    private var isMixedBundle: Bool {
        payload.isAudio && (!payload.imageItems.isEmpty || payload.text?.isEmpty == false)
    }

    @ViewBuilder private var previewBlock: some View {
        if payload.isAudio {
            VStack(alignment: .leading, spacing: 8) {
                if payload.audioItems.count > 1 { clipStack } else { audioCard }
                // B3 mixed-bundle previews — the signed idioms, stacked.
                if !payload.imageItems.isEmpty {
                    if payload.imageItems.count > 1 { photoGrid } else { imageBlock }
                }
                if payload.text?.isEmpty == false { textQuoteBlock }
                // Books routing outranks the 1-or-N chooser: a book import
                // takes every clip as parts of ONE book, so the split
                // question only applies on the voice-note route. A mixed
                // bundle is ALWAYS one note (B3) — no chooser either.
                if hasLongClip { booksChooser }
                if payload.audioItems.count > 1, !(hasLongClip && sendToBooks), !isMixedBundle {
                    chooser
                }
            }
            .onAppear { if hasLongClip { sendToBooks = true } }
        } else if payload.isVideo {
            // E1 (mock m1): video gets the slim sheet instead of a silent import.
            videoPreviewCard
        } else {
            switch payload.type {
            case .url:
                urlCard
            case .text:
                textQuoteBlock
            case .image:
                if payload.imageItems.count > 1 {
                    photoGrid
                } else {
                    imageBlock
                }
            case .file:
                // E1 (mock m2): documents get the slim sheet too — no more
                // silent file card.
                docPreviewCard
            }
        }
    }

    // E1: video preview (mock m1) — thumb glyph, duration, filmed date, honesty.
    private var videoPreviewCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.skAccent.opacity(0.14))
                    .frame(width: 46, height: 34)
                    .overlay(
                        Image(systemName: "play.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.skAccent)
                    )
                VStack(alignment: .leading, spacing: 1) {
                    Text(payload.videoDuration.map { "Video · \(fmtDuration($0))" } ?? "Video")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.skText)
                    Text(payload.videoFilmedAt.map {
                        "filmed \($0.formatted(date: .abbreviated, time: .shortened)) · audio becomes the note"
                    } ?? "audio becomes the note")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.skTextFaint)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.skSurface, in: .rect(cornerRadius: 13, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.5)
            )
            honestyLine("Transcribes on-device · the video file itself isn't kept")
        }
        .accessibilityIdentifier("capture-video-card")
    }

    // E1: document preview (mock m2) — doc glyph, name, pages · size, honesty.
    private var docPreviewCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.skAccent.opacity(0.14))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "doc.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.skAccent)
                    )
                VStack(alignment: .leading, spacing: 1) {
                    Text(payload.fileName ?? "Document")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.skText)
                        .lineLimit(1)
                    Text(docSubtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.skTextFaint)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.skSurface, in: .rect(cornerRadius: 13, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.5)
            )
            honestyLine(payload.filePageCount != nil
                        ? "Its text becomes searchable in Skrift · opens inline in the note"
                        : "Opens from the note · Skrift opens on it next time")
        }
        .accessibilityIdentifier("capture-doc-card")
    }

    private var docSubtitle: String {
        var parts: [String] = []
        if let p = payload.filePageCount { parts.append(p == 1 ? "1 page" : "\(p) pages") }
        if let s = payload.fileSizeBytes {
            parts.append(ByteCountFormatter.string(fromByteCount: s, countStyle: .file))
        }
        parts.append("from Files")
        return parts.joined(separator: " · ")
    }

    private func honestyLine(_ text: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.skAccent.opacity(0.55))
                .frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 10.5))
                .foregroundStyle(Color.skTextFaint)
        }
        .padding(.leading, 2)
    }

    // Multi-audio: EVERY incoming clip, scrollable past 4 rows (device round 1:
    // "+1 more" for a single hidden row read as broken — the user expected to
    // scroll through what they grabbed). Oldest → newest.
    private var clipStack: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(payload.audioItems.enumerated()), id: \.offset) { i, item in
                        HStack(spacing: 9) {
                            Text("\(i + 1)")
                                .font(.system(size: 10, weight: .medium).monospacedDigit())
                                .foregroundStyle(Color.skTextFaint)
                                .frame(width: 16, alignment: .trailing)
                            Image(systemName: "waveform")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.skAccent.opacity(0.6))
                            Text("Voice note")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.skTextDim)
                            Spacer(minLength: 6)
                            Text(clipLabel(item))
                                .font(.system(size: 10.5).monospacedDigit())
                                .foregroundStyle(Color.skTextFaint)
                        }
                        .padding(.vertical, 7)
                        if i < payload.audioItems.count - 1 {
                            Divider().overlay(Color.white.opacity(0.05))
                        }
                    }
                }
            }
            .frame(maxHeight: 148)   // ~4.5 rows — the half row invites the scroll
            Text("oldest → newest")
                .font(.system(size: 10))
                .foregroundStyle(Color.skTextFaint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
        }
        .padding(.horizontal, 12)
        .background(Color.skSurface, in: .rect(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.5)
        )
        .accessibilityIdentifier("capture-clip-stack")
    }

    private func clipLabel(_ item: SharedAudioItem) -> String {
        var parts: [String] = []
        if let at = item.recordedAt {
            parts.append(at.formatted(date: .omitted, time: .shortened))
        }
        if let d = item.duration, d >= 1 { parts.append(fmtDuration(d)) }
        return parts.joined(separator: " · ")
    }

    // E2: a ≥1h recording defaults to the Books tab (read-along) — a lecture or
    // audiobook chapter isn't a voice note. Same card idiom as the B1 chooser.
    private var booksChooser: some View {
        HStack(spacing: 8) {
            choiceCard(
                title: "Audiobook",
                subtitle: "Read-along in the Books tab — it's a long one",
                selected: sendToBooks
            ) { sendToBooks = true }
            .accessibilityIdentifier("capture-choice-books")

            choiceCard(
                title: "Voice note",
                subtitle: "Transcribe the whole thing as a note",
                selected: !sendToBooks
            ) { sendToBooks = false }
            .accessibilityIdentifier("capture-choice-memo")
        }
    }

    // B1: One note (default — clips merged in order) vs N separate notes.
    private var chooser: some View {
        HStack(spacing: 8) {
            choiceCard(
                title: "One note",
                subtitle: "Clips stitched in order — one story, one transcript",
                selected: combineIntoOne
            ) { combineIntoOne = true }
            .accessibilityIdentifier("capture-choice-combine")

            choiceCard(
                title: "\(payload.audioItems.count) notes",
                subtitle: "Each voice note becomes its own memo",
                selected: !combineIntoOne
            ) { combineIntoOne = false }
            .accessibilityIdentifier("capture-choice-split")
        }
    }

    private func choiceCard(title: String, subtitle: String, selected: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .top) {
                    Text(title)
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(selected ? Color.white : Color.skText)
                    Spacer(minLength: 4)
                    Circle()
                        .strokeBorder(selected ? Color.skAccent : Color.white.opacity(0.25), lineWidth: 1.5)
                        .background(Circle().fill(selected ? Color.skAccent : .clear).padding(3))
                        .frame(width: 14, height: 14)
                }
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(selected ? Color.skTextDim : Color.skTextFaint)
                    .multilineTextAlignment(.leading)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
            .background(selected ? Color.skAccent.opacity(0.09) : Color.white.opacity(0.02),
                        in: .rect(cornerRadius: 13, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(selected ? Color.skAccent.opacity(0.55) : Color.white.opacity(0.12),
                                  lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // B2: multi-photo grid — first 4 tiles, "+N" on the last when more.
    private var photoGrid: some View {
        let items = payload.imageItems
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
            ForEach(Array(items.prefix(4).enumerated()), id: \.offset) { i, item in
                ZStack(alignment: .bottomTrailing) {
                    if let img = UIImage(data: item.data) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 74)
                            .frame(maxWidth: .infinity)
                            .clipShape(.rect(cornerRadius: 11, style: .continuous))
                    } else {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(Color.skElev)
                            .frame(height: 74)
                    }
                    if i == 3, items.count > 4 {
                        Text("+\(items.count - 4)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(.black.opacity(0.5), in: .capsule)
                            .padding(5)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.5)
                )
            }
        }
        .accessibilityIdentifier("capture-photo-grid")
        .accessibilityLabel("\(items.count) photos, combined into one note")
    }

    // Audio: slim card (waveform glyph, "Voice note · 0:41") + the honesty line —
    // the import happens on the app's next foreground drain, and the app then
    // opens on the note (mock share-ingest-wave1.html state 1, signed 2026-07-10).
    private var audioCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.skAccent.opacity(0.14))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "waveform")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.skAccent)
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(audioTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.skText)
                        .lineLimit(1)
                    Text("Audio · shared \(Date().formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.skTextFaint)
                }
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.skSurface, in: .rect(cornerRadius: 13, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.5)
            )

            HStack(spacing: 6) {
                Circle()
                    .fill(Color.skAccent.opacity(0.55))
                    .frame(width: 6, height: 6)
                Text("Transcribes on-device · Skrift opens on it next time")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.skTextFaint)
            }
            .padding(.leading, 2)
        }
        .accessibilityIdentifier("capture-audio-card")
        .accessibilityLabel(audioTitle)
    }

    private var audioTitle: String {
        if let d = payload.audioItems.first?.duration, d >= 1 {
            return "Voice note · \(fmtDuration(d))"
        }
        return "Voice note"
    }

    // URL: link card with globe glyph, title, domain
    private var urlCard: some View {
        HStack(spacing: 10) {
            // Globe glyph — favicon would require networking, which the extension avoids.
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.skAccent.opacity(0.14))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: "globe")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color(red: 0.376, green: 0.647, blue: 0.980)) // blue accent
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(payload.urlTitle ?? urlDomain ?? "Link")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.skText)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let domain = urlDomain {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.skTextFaint)
                        Text(domain)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.skTextFaint)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.skSurface, in: .rect(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.5)
        )
        .accessibilityIdentifier("capture-link-card")
        .accessibilityLabel("Link: \(payload.urlTitle ?? urlDomain ?? "Link")")
    }

    // Text: italic quoted snippet with an accent left border
    private var textQuoteBlock: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.skAccent.opacity(0.5))
                .frame(width: 2)
                .padding(.vertical, 2)
            Text(payload.text ?? "")
                .font(.system(size: 13, weight: .regular).italic())
                .foregroundStyle(Color.skTextDim)
                .lineLimit(4)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.skSurface, in: .rect(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.5)
        )
        .accessibilityIdentifier("capture-text-preview")
    }

    // Image: thumbnail from the loaded data
    private var imageBlock: some View {
        Group {
            if let data = payload.imageItems.first?.data, let uiImg = UIImage(data: data) {
                Image(uiImage: uiImg)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                    .clipShape(.rect(cornerRadius: 13, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.5)
                    )
            } else {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color.skElev)
                    .frame(height: 80)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 24))
                            .foregroundStyle(Color.skTextFaint)
                    )
            }
        }
        .accessibilityIdentifier("capture-image-preview")
    }

    // Typed thoughts only. Voice recording in share extensions is BLOCKED by
    // iOS at the entitlement level — mediaserverd: "NOT allowed to start
    // recording because it is an extension and doesn't have entitlements to
    // record audio" (device rounds 2–3, permission GRANTED yet record()=false;
    // Apple forums 742601/108435 show the same wall). The old record button
    // was a dead affordance that never worked on hardware; voice thoughts land
    // in the app after the jump-open instead.
    private var annotationField: some View {
        VStack(alignment: .leading, spacing: 7) {
            typeField
            Text("Voice thoughts? Add them in Skrift after saving — share sheets can't record.")
                .font(.system(size: 10.5))
                .foregroundStyle(Color.skTextFaint)
                .padding(.leading, 2)
        }
    }

    private var typeField: some View {
        ZStack(alignment: .topLeading) {
            if annotationIsEmpty {
                Text("Add a thought (optional)…")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.skTextFaint)
                    .padding(.top, 9).padding(.leading, 12)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            TextEditor(text: $annotation)
                .font(.system(size: 14))
                .foregroundStyle(Color.skText)
                .tint(Color.skAccent)
                .frame(minHeight: 54, maxHeight: 96)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .focused($annotationFocused)
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { annotationFocused = false }
                            .font(.system(size: 14, weight: .semibold))
                    }
                }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.skSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(annotationFocused ? Color.skAccent.opacity(0.45) : Color.white.opacity(0.09),
                                      lineWidth: 0.5)
                )
        )
        .accessibilityIdentifier("capture-annotation-field")
    }

    private func fmtDuration(_ t: TimeInterval) -> String {
        let s = Int(t.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// Save label re-states the multi-audio choice live (signed mock):
    /// "Save as one note" ⇄ "Save N notes".
    private var saveLabel: String {
        guard payload.isAudio, payload.audioItems.count > 1 else { return "Save to Skrift" }
        return combineIntoOne ? "Save as one note" : "Save \(payload.audioItems.count) notes"
    }

    private var saveButton: some View {
        Button { saveTapped() } label: {
            Text(saveLabel)
                .font(.system(size: 14.5, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color.skAccent, in: .rect(cornerRadius: 12, style: .continuous))
                .shadow(color: Color.skAccent.opacity(0.45), radius: 8, y: 1)
        }
        .accessibilityIdentifier("capture-save-button")
    }

    // MARK: - Helpers

    private var urlDomain: String? {
        guard let urlStr = payload.url, let url = URL(string: urlStr) else { return nil }
        return url.host?.replacingOccurrences(of: "www.", with: "")
    }

    private func saveTapped() {
        // Audio share: slim "audio" entries — no annotation/dictation (no ramble
        // UI on audio shares), just significance. Combine (default) = ONE entry
        // carrying every clip name in play order → one merged memo; split = one
        // entry per clip → N memos. The host maps clips to entries by index.
        if payload.isAudio {
            let items = payload.audioItems
            let imageItems = payload.imageItems
            let sharedAt = ISO8601.string(from: Date())
            // Clip dates ride the entry, index-aligned to the names ("" = unknown)
            // — the import dates the memo to the voice note, not the share moment.
            func iso(_ item: SharedAudioItem) -> String {
                item.recordedAt.map { ISO8601.string(from: $0) } ?? ""
            }
            func entry(id: UUID, names: [String], dates: [String]) -> CaptureInboxEntry {
                CaptureInboxEntry(
                    id: id, type: "audio", url: nil, urlTitle: nil,
                    // B3: the bundle's chat text rides the entry → the memo's
                    // annotation (leads the note above the transcript).
                    text: payload.text,
                    imageFileName: nil, mimeType: nil, annotationText: nil,
                    significance: significance, sharedAt: sharedAt,
                    audioFileNames: names, audioRecordedAts: dates,
                    // E2: ≥1h clips route to Books unless overridden in the sheet.
                    routeToBooks: (hasLongClip && sendToBooks) ? true : nil,
                    // B3: bundled photos ride the same entry, index-aligned datas.
                    imageFileNames: imageItems.isEmpty ? nil : imageItems.map(\.fileName),
                    imageRecordedAts: imageItems.isEmpty ? nil
                        : imageItems.map { $0.recordedAt.map { ISO8601.string(from: $0) } ?? "" }
                )
            }
            func ext(_ item: SharedAudioItem) -> String {
                item.url.pathExtension.isEmpty ? "m4a" : item.url.pathExtension
            }
            // A Books-routed share is always ONE entry: the clips become the
            // parts of one book (multi-file audiobook), never N notes. A mixed
            // bundle (B3) is likewise always one note.
            if combineIntoOne || items.count == 1 || (hasLongClip && sendToBooks) || isMixedBundle {
                let id = UUID()
                let names = items.enumerated().map { "audio_\(id.uuidString)_\($0.offset).\(ext($0.element))" }
                onSave([entry(id: id, names: names, dates: items.map(iso))],
                       imageItems.map(\.data), nil)
            } else {
                let entries = items.map { item -> CaptureInboxEntry in
                    let id = UUID()
                    return entry(id: id, names: ["audio_\(id.uuidString)_0.\(ext(item))"],
                                 dates: [iso(item)])
                }
                onSave(entries, [], nil)
            }
            return
        }

        // No dictation from the sheet — iOS blocks extension recording (above);
        // the entry field stays nil and CaptureDictation remains drain-side for
        // any legacy pending entries.
        let dictationData: Data? = nil

        // E1 (mock m1): video rides its own entry type — the typed thought +
        // significance now travel with it (the silent import lost both, A13).
        if payload.isVideo, let videoURL = payload.videoURL {
            let id = UUID()
            let ext = videoURL.pathExtension.isEmpty ? "mov" : videoURL.pathExtension
            let thought = annotation.trimmingCharacters(in: .whitespacesAndNewlines)
            onSave([CaptureInboxEntry(
                id: id, type: "video", url: nil, urlTitle: nil, text: nil,
                imageFileName: nil, mimeType: nil,
                annotationText: thought.isEmpty ? nil : thought,
                significance: significance, sharedAt: ISO8601.string(from: Date()),
                videoFileName: "video_\(id.uuidString).\(ext)"
            )], [], nil)
            return
        }
        // E1 (mock m2): documents likewise — the sheet's thought becomes the
        // capture's annotation body, significance flags it for sync.
        if payload.type == .file, payload.fileURL != nil {
            let id = UUID()
            let ext = payload.fileURL?.pathExtension.isEmpty == false
                ? payload.fileURL!.pathExtension : "pdf"
            let thought = annotation.trimmingCharacters(in: .whitespacesAndNewlines)
            onSave([CaptureInboxEntry(
                id: id, type: "file", url: nil, urlTitle: nil, text: nil,
                imageFileName: nil, mimeType: payload.mimeType,
                annotationText: thought.isEmpty ? nil : thought,
                significance: significance, sharedAt: ISO8601.string(from: Date()),
                fileName: "file_\(id.uuidString).\(ext)",
                fileDisplayName: payload.fileName
            )], [], nil)
            return
        }

        let trimmed = annotation.trimmingCharacters(in: .whitespacesAndNewlines)
        let imageItems = payload.imageItems
        let entry = CaptureInboxEntry(
            id: UUID(),
            type: payload.type.rawValue,
            url: payload.url,
            urlTitle: payload.urlTitle,
            text: payload.text,
            // Legacy single field stays the FIRST image (capture detail + Mac read it).
            imageFileName: imageItems.first?.fileName,
            mimeType: payload.mimeType,
            annotationText: trimmed.isEmpty ? nil : trimmed,
            significance: significance,
            sharedAt: ISO8601.string(from: Date()),
            dictationFileName: dictationData != nil ? "dictation.m4a" : nil,
            // The names array carries EVERY image (single included) — the write
            // path stores them all from `imageDatas`, index-aligned.
            imageFileNames: imageItems.isEmpty ? nil : imageItems.map(\.fileName),
            // EXIF taken-dates, aligned to the names ("" = none) — the drainer
            // dates the capture to the earliest photo, not the share moment (A4).
            imageRecordedAts: imageItems.isEmpty ? nil
                : imageItems.map { $0.recordedAt.map { ISO8601.string(from: $0) } ?? "" }
        )
        onSave([entry], imageItems.map(\.data), dictationData)
    }
}
