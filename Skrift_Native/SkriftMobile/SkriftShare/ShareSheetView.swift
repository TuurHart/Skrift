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
    @State private var recorder = ShareDictationRecorder()
    @FocusState private var annotationFocused: Bool
    /// B1 chooser: N shared voice notes → one note (default, clips merged in
    /// order) or N separate notes. Only shown when 2+ audio clips arrived.
    @State private var combineIntoOne = true

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

    @ViewBuilder private var previewBlock: some View {
        if payload.isAudio {
            if payload.audioItems.count > 1 {
                VStack(alignment: .leading, spacing: 8) {
                    clipStack
                    chooser
                }
            } else {
                audioCard
            }
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
                // File captures not shown in the share sheet v1 (activation rule
                // doesn't include files; this is a defensive fallback).
                EmptyView()
            }
        }
    }

    // Multi-audio: a compact preview of the incoming clips (first 3 + "+N more",
    // oldest → newest) so the user sees what they grabbed before saving.
    private var clipStack: some View {
        VStack(spacing: 0) {
            ForEach(Array(payload.audioItems.prefix(3).enumerated()), id: \.offset) { i, item in
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
                if i < min(payload.audioItems.count, 3) - 1 {
                    Divider().overlay(Color.white.opacity(0.05))
                }
            }
            if payload.audioItems.count > 3 {
                Text("+ \(payload.audioItems.count - 3) more · oldest → newest")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.skTextFaint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
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

    // Capture-your-thoughts: a PROMINENT record button (primary — like the
    // record FAB everywhere else in the app), with the text field secondary
    // below. The earlier tiny mic-in-the-corner got missed; recording is the
    // point here ("typing is for caveman" — 2026-06-13 device feedback).
    private var annotationField: some View {
        VStack(alignment: .leading, spacing: 8) {
            recordButton
            if recorder.state == .denied {
                Text("Microphone access is off for Skrift — enable it to record, or type below.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.skTextFaint)
            }
            if case .recorded = recorder.state {
                Button { recorder.discard() } label: {
                    Text("Discard voice note")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.skTextFaint)
                }
                .accessibilityIdentifier("capture-dictation-discard")
            }
            typeField
        }
    }

    /// The big record control — idle / recording (live timer) / recorded
    /// (re-record). Tapping toggles: record → stop → re-record.
    private var recordButton: some View {
        Button { recorder.toggleRecord() } label: {
            HStack(spacing: 9) {
                Image(systemName: recordIcon).font(.system(size: 15, weight: .bold))
                Text(recordLabel).font(.system(size: 15, weight: .bold))
                if case .recorded = recorder.state {
                    Spacer(minLength: 8)
                    Text("Re-record").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .padding(.horizontal, 14)
            .background(recordColor, in: .rect(cornerRadius: 13, style: .continuous))
            .shadow(color: recordColor.opacity(0.4), radius: 8, y: 1)
        }
        .accessibilityIdentifier("capture-dictation-record")
        .accessibilityLabel(recordLabel)
    }

    private var recordIcon: String {
        switch recorder.state {
        case .recording: return "stop.fill"
        case .recorded:  return "checkmark.circle.fill"
        default:         return "mic.fill"
        }
    }
    private var recordLabel: String {
        switch recorder.state {
        case .recording:       return "Stop · \(fmtDuration(recorder.elapsed))"
        case .recorded(let d): return "Voice note · \(fmtDuration(d))"
        default:               return "Record your thoughts"
        }
    }
    private var recordColor: Color {
        switch recorder.state {
        case .recording: return Color.red.opacity(0.9)
        case .recorded:  return Color.skAccent.opacity(0.85)
        default:         return Color.skAccent
        }
    }

    /// Secondary "…or type" field — no longer the primary affordance.
    private var typeField: some View {
        ZStack(alignment: .topLeading) {
            if annotationIsEmpty {
                Text("…or type instead (optional)")
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
            let sharedAt = ISO8601.string(from: Date())
            func entry(id: UUID, names: [String]) -> CaptureInboxEntry {
                CaptureInboxEntry(
                    id: id, type: "audio", url: nil, urlTitle: nil, text: nil,
                    imageFileName: nil, mimeType: nil, annotationText: nil,
                    significance: significance, sharedAt: sharedAt,
                    audioFileNames: names
                )
            }
            func ext(_ item: SharedAudioItem) -> String {
                item.url.pathExtension.isEmpty ? "m4a" : item.url.pathExtension
            }
            if combineIntoOne || items.count == 1 {
                let id = UUID()
                let names = items.enumerated().map { "audio_\(id.uuidString)_\($0.offset).\(ext($0.element))" }
                onSave([entry(id: id, names: names)], [], nil)
            } else {
                let entries = items.map { item -> CaptureInboxEntry in
                    let id = UUID()
                    return entry(id: id, names: ["audio_\(id.uuidString)_0.\(ext(item))"])
                }
                onSave(entries, [], nil)
            }
            return
        }

        // Save while still talking = keep the take: stop, then read it.
        if recorder.state == .recording { recorder.toggleRecord() }
        let dictationData = recorder.recordedData

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
            imageFileNames: imageItems.isEmpty ? nil : imageItems.map(\.fileName)
        )
        onSave([entry], imageItems.map(\.data), dictationData)
    }
}
