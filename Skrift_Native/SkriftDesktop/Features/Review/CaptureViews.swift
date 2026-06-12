import SwiftUI
import AppKit

// MARK: - CaptureSourceStrip

/// Toolbar replacement for captures (mock state 3): capture-type glyph, a label
/// ("Shared link · domain"), and an "Open ↗" button that opens the URL in the
/// default browser. Replaces the audio transport — captures have no audio to play.
struct CaptureSourceStrip: View {
    let file: PipelineFile

    private var sc: SharedContent? { SharedContent.decode(from: file.audioMetadataJSON) }

    private var label: String {
        switch sc?.type {
        case "url":
            let domain = sc?.url.flatMap { URL(string: $0)?.host } ?? ""
            return "Shared link\(domain.isEmpty ? "" : " · \(domain)")"
        case "text": return "Shared text"
        case "image": return "Shared image"
        case "file": return "Shared file"
        default: return "Capture"
        }
    }

    private var urlToOpen: URL? {
        guard let urlStr = sc?.url, !urlStr.isEmpty else { return nil }
        return URL(string: urlStr)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: file.sourceSymbol)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textMuted)

            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)

            if let url = urlToOpen {
                Button(action: { NSWorkspace.shared.open(url) }) {
                    Text("Open ↗")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 2)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Theme.accent.opacity(0.35), lineWidth: 0.5)
                        )
                        .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - CaptureBanner

/// Informational banner shown inside the note column for all captures (mock state 3).
/// Explains what the pipeline skipped (ASR + diarization) and what still ran
/// (enhancement-lite: title, tags, summary + name-linking on the annotation).
/// The wording adapts slightly per capture type.
struct CaptureBanner: View {
    let file: PipelineFile

    private var sc: SharedContent? { SharedContent.decode(from: file.audioMetadataJSON) }

    private var bannerText: String {
        let typePhrase: String
        switch sc?.type {
        case "url":   typePhrase = "The URL exports to Obsidian intact."
        case "text":  typePhrase = "The snippet exports as a blockquote above your annotation."
        case "image": typePhrase = "The image is copied to your vault attachments folder."
        default:      typePhrase = "The shared content exports to Obsidian alongside your annotation."
        }
        return "Capture — skipped transcription & diarization. Enhancement-lite still ran: title, tags, summary + name-linking on your annotation. \(typePhrase)"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 13))
                .foregroundStyle(Theme.blue)
                .padding(.top, 1)

            Text(bannerText)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .background(Theme.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(Theme.blue.opacity(0.22), lineWidth: 0.5)
        )
    }
}

// MARK: - CaptureSharedContentBlock

/// The shared-content card pinned above the annotation body (mock state 3
/// `sharedblock`): bordered, blue-tinted left edge, a "SHARED CONTENT" kicker,
/// then the content per type — url: glyph + bold title + monospaced URL;
/// text: the snippet as an italic quote; image: the file reference (the pixels
/// live in the working folder and export as an `![[embed]]`). This mirrors in
/// the REVIEW what `Compiler.captureSharedBlock` pins in the EXPORT.
struct CaptureSharedContentBlock: View {
    let file: PipelineFile

    private var sc: SharedContent? { SharedContent.decode(from: file.audioMetadataJSON) }

    var body: some View {
        if let sc {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 6) {
                    Image(systemName: file.sourceSymbol)
                        .font(.system(size: 9))
                    Text("SHARED CONTENT")
                        .font(.system(size: 10, weight: .medium))
                        .kerning(0.7)
                }
                .foregroundStyle(Theme.textMuted)

                switch sc.type {
                case "url":
                    VStack(alignment: .leading, spacing: 2) {
                        if let title = sc.urlTitle, !title.isEmpty {
                            Text(title)
                                .font(.system(size: 14.5, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                        }
                        if let url = sc.url, !url.isEmpty {
                            Text(url)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Theme.blue)
                                .textSelection(.enabled)
                        }
                    }
                case "text":
                    Text(sc.text ?? "")
                        .font(.system(size: 13.5))
                        .italic()
                        .foregroundStyle(Theme.textPrimary.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                case "image":
                    HStack(spacing: 8) {
                        Image(systemName: "photo")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.textMuted)
                        Text(sc.fileName ?? "image")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Theme.textSecondary)
                    }
                default:
                    Text(sc.fileName ?? "Shared file")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.blue.opacity(0.04), in: RoundedRectangle(cornerRadius: 11))
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .stroke(Theme.hairline.opacity(0.09), lineWidth: 0.5)
            )
            .overlay(alignment: .leading) {
                UnevenRoundedRectangle(topLeadingRadius: 11, bottomLeadingRadius: 11)
                    .fill(Theme.blue.opacity(0.55))
                    .frame(width: 2.5)
            }
        }
    }
}
