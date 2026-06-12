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
