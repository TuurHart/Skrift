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
    let onSave: (CaptureInboxEntry, Data?) -> Void
    let onCancel: () -> Void

    @State private var annotation: String = ""
    @State private var significance: Double = 0
    @FocusState private var annotationFocused: Bool

    // TextEditor placeholder state
    private var annotationIsEmpty: Bool { annotation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        // Dark surface card, same style as the mock sheet
        ZStack(alignment: .bottom) {
            // Scrim behind the sheet
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { onCancel() }

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                sheetContent
            }
            .ignoresSafeArea(edges: .bottom)
        }
        // Prefer dark regardless of system setting — the sheet always uses the dark palette.
        .preferredColorScheme(.dark)
    }

    // MARK: - Sheet

    private var sheetContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            grabHandle
            headerRow
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
            // Sheet surface: slightly elevated above the scrim
            Color(red: 0.106, green: 0.110, blue: 0.157)   // #1b1d28 per mock
                .ignoresSafeArea(edges: .bottom)
                .clipShape(.rect(topLeadingRadius: 22, topTrailingRadius: 22, style: .continuous))
        )
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 0.5)
                .ignoresSafeArea(edges: .bottom)
        }
        .shadow(color: .black.opacity(0.5), radius: 36, y: -10)
    }

    // MARK: - Sub-views

    private var grabHandle: some View {
        Capsule()
            .fill(Color.white.opacity(0.18))
            .frame(width: 36, height: 4)
            .frame(maxWidth: .infinity)
            .padding(.top, 11)
            .padding(.bottom, 12)
            .accessibilityHidden(true)
    }

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

    // Annotation TextEditor with a layered placeholder
    private var annotationField: some View {
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
                .frame(minHeight: 74)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .focused($annotationFocused)
        }
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.skSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(
                            annotationFocused ? Color.skAccent.opacity(0.45) : Color.white.opacity(0.09),
                            lineWidth: 0.5)
                )
        )
        .accessibilityIdentifier("capture-annotation-field")
    }

    private var saveButton: some View {
        Button { saveTapped() } label: {
            Text("Save")
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
            sharedAt: ISO8601.string(from: Date())
        )
        onSave(entry, payload.imageData)
    }
}
