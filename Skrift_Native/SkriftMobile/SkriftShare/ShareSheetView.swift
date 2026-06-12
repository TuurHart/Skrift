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
    let onSave: (CaptureInboxEntry, _ imageData: Data?, _ dictationData: Data?) -> Void
    let onCancel: () -> Void

    @State private var annotation: String = ""
    @State private var significance: Double = 0
    @State private var recorder = ShareDictationRecorder()
    @FocusState private var annotationFocused: Bool

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
            annotationField
                .padding(.bottom, 12)
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

            Text("Save to Skrift")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.skText)

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

    @ViewBuilder private var previewBlock: some View {
        switch payload.type {
        case .url:
            urlCard
        case .text:
            textQuoteBlock
        case .image:
            imageBlock
        case .file:
            // File captures not shown in the share sheet v1 (activation rule
            // doesn't include files; this is a defensive fallback).
            EmptyView()
        }
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
            if let data = payload.imageData, let uiImg = UIImage(data: data) {
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

    // Annotation TextEditor with a layered placeholder + the dictation mic
    // (mock state 1: small mic bottom-right of the field — "uses the same
    // on-device transcriber as memos"; the transcription itself runs in the
    // main app on drain, the extension only records).
    private var annotationField: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                // TextEditor doesn't support native placeholder before iOS 17 — overlay.
                if annotationIsEmpty {
                    Text("Add your thoughts… (optional)")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.skTextFaint)
                        .padding(.top, 11)
                        .padding(.leading, 13)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                TextEditor(text: $annotation)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.skText)
                    .tint(Color.skAccent)
                    // maxHeight matters: an uncapped TextEditor greedily fills the
                    // whole sheet (the giant-white-box 2026-06-12 finding).
                    .frame(minHeight: 74, maxHeight: 110)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .padding(.trailing, 30)   // keep text clear of the mic
                    .focused($annotationFocused)
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Done") { annotationFocused = false }
                                .font(.system(size: 14, weight: .semibold))
                        }
                    }
            }
            .overlay(alignment: .bottomTrailing) { micButton }
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color.skSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .strokeBorder(
                                recorder.state == .recording ? Color.red.opacity(0.55)
                                : annotationFocused ? Color.skAccent.opacity(0.45)
                                : Color.white.opacity(0.09),
                                lineWidth: 0.5)
                    )
            )
            .accessibilityIdentifier("capture-annotation-field")

            dictationStatusRow
        }
    }

    /// Mic / stop toggle pinned to the field's bottom-right (mock `.annot .mic`).
    private var micButton: some View {
        Button { recorder.toggleRecord() } label: {
            Group {
                if recorder.state == .recording {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(Color.red.opacity(0.85), in: .circle)
                } else {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.skTextDim)
                        .frame(width: 26, height: 26)
                        .background(Color.white.opacity(0.06), in: .circle)
                }
            }
        }
        .padding(8)
        .accessibilityLabel(recorder.state == .recording ? "Stop dictation" : "Dictate")
        .accessibilityIdentifier("capture-dictation-mic")
    }

    /// One-line status under the field: live elapsed while recording, a
    /// voice-note chip (with discard) once recorded, a hint when mic denied.
    @ViewBuilder private var dictationStatusRow: some View {
        switch recorder.state {
        case .idle:
            EmptyView()
        case .denied:
            Text("Microphone access is off for Skrift — dictation unavailable.")
                .font(.system(size: 11))
                .foregroundStyle(Color.skTextFaint)
        case .recording:
            HStack(spacing: 6) {
                Circle().fill(Color.red).frame(width: 6, height: 6)
                Text("Recording… \(fmtDuration(recorder.elapsed)) — tap ■ to stop")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.skTextDim)
            }
            .accessibilityIdentifier("capture-dictation-recording")
        case .recorded(let duration):
            HStack(spacing: 6) {
                Image(systemName: "waveform")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.skAccent)
                Text("Voice note · \(fmtDuration(duration)) — transcribes when you open Skrift")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.skTextDim)
                    .lineLimit(1)
                Button { recorder.discard() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.skTextFaint)
                }
                .accessibilityLabel("Discard voice note")
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.skAccent.opacity(0.10), in: .capsule)
            .accessibilityIdentifier("capture-dictation-chip")
        }
    }

    private func fmtDuration(_ t: TimeInterval) -> String {
        let s = Int(t.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private var saveButton: some View {
        Button { saveTapped() } label: {
            Text("Save to Skrift")   // mock state-1 label
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
        // Save while still talking = keep the take: stop, then read it.
        if recorder.state == .recording { recorder.toggleRecord() }
        let dictationData = recorder.recordedData

        let trimmed = annotation.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = CaptureInboxEntry(
            id: UUID(),
            type: payload.type.rawValue,
            url: payload.url,
            urlTitle: payload.urlTitle,
            text: payload.text,
            imageFileName: payload.imageFileName,
            mimeType: payload.mimeType,
            annotationText: trimmed.isEmpty ? nil : trimmed,
            significance: significance,
            sharedAt: ISO8601.string(from: Date()),
            dictationFileName: dictationData != nil ? "dictation.m4a" : nil
        )
        onSave(entry, payload.imageData, dictationData)
    }
}
