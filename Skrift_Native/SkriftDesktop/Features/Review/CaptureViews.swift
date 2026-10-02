import SwiftUI
import AppKit

// MARK: - CaptureSourceStrip

/// Toolbar replacement for captures (mock state 3): capture-type glyph, a label
/// ("Shared link · domain"), and an "Open ↗" button that opens the URL in the
/// default browser. Replaces the audio transport — captures have no audio to play.
struct CaptureSourceStrip: View {
    let file: PipelineFile

    private var sc: SharedContent? { file.sharedContent }

    private var label: String {
        switch sc?.type {
        case .url:
            let domain = sc?.url.flatMap { URL(string: $0)?.host } ?? ""
            return "Shared link\(domain.isEmpty ? "" : " · \(domain)")"
        case .text: return "Shared text"
        case .image: return "Shared image"
        case .file: return "Shared file"
        case nil: return "Capture"
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

    private var sc: SharedContent? { file.sharedContent }

    /// Honest about the polish: the sentence follows the row's real state (done / pending /
    /// unrated), never a blanket "Enhancement-lite still ran" (Q143, capture-drain-13).
    private var bannerText: String {
        let polish = CaptureBannerCopy.polish(rated: NoteConsent.isRated(file),
                                              enhanced: file.enhanceStatus == .done)
        return CaptureBannerCopy.text(shared: sc?.type, polish: polish)
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

    private var sc: SharedContent? { file.sharedContent }

    /// The synced `.file` document, materialized under the capture folder's `files/` (3b) —
    /// the single file there. nil until the document asset arrives (then the card gains "Open").
    private var documentURL: URL? { file.captureDocumentURL }

    @State private var textExpanded = false
    @State private var textShowAll = false

    // MARK: link — thumbnail, title, description, domain (phone `captureURLCard`)

    @ViewBuilder private func linkCard(_ sc: SharedContent) -> some View {
        let domain = sc.url.flatMap { URL(string: $0)?.host }
        HStack(alignment: .top, spacing: 12) {
            if let thumbURL = file.captureThumbnailURL, let thumb = NSImage(contentsOf: thumbURL) {
                Image(nsImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.blue.opacity(0.13))
                    .frame(width: 36, height: 36)
                    .overlay(Image(systemName: "globe")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.blue))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text((sc.urlTitle?.isEmpty == false ? sc.urlTitle : nil) ?? domain ?? "Link")
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                if let desc = sc.urlDescription, !desc.isEmpty {
                    Text(desc)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(3)
                }
                if let url = sc.url, !url.isEmpty {
                    Text(url)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.blue)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
        }
    }

    // MARK: image — the photos themselves, stacked in order (phone `captureImageEmbed`)

    @ViewBuilder private func imageBlock(_ sc: SharedContent) -> some View {
        let urls = file.captureImageURLs
        if urls.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "photo")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textMuted)
                Text(sc.fileName ?? "image")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(urls, id: \.self) { url in
                    if let img = NSImage(contentsOf: url) {
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 360)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(Theme.hairline.opacity(0.12), lineWidth: 0.5))
                            .onTapGesture { NSWorkspace.shared.open(url) }
                            .help("Open the picture")
                    }
                }
            }
        }
    }

    // MARK: file — a PDF inline (first page, page chip, text disclosure); else the card

    @ViewBuilder private func fileBlock(_ sc: SharedContent) -> some View {
        let doc = documentURL
        if let doc, let page = CapturePDFPreview.firstPage(at: doc) {
            VStack(alignment: .leading, spacing: 10) {
                // Explicit fitted size: `scaledToFit` inside a max-frame leaves the frame at the
                // full max width and centres the page in it.
                let fit = min(420 / page.image.size.width, 520 / page.image.size.height, 1)
                Image(nsImage: page.image)
                    .resizable()
                    .frame(width: page.image.size.width * fit, height: page.image.size.height * fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .shadow(color: .black.opacity(0.18), radius: 4, y: 1)
                    .overlay(alignment: .bottomTrailing) {
                        Text(CapturePDFPreview.pageCountLabel(page.pageCount))
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.black.opacity(0.62), in: Capsule())
                            .padding(8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                .onTapGesture { NSWorkspace.shared.open(doc) }
                .help("Open the PDF")
                HStack(spacing: 8) {
                    Text(sc.fileName ?? "PDF")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    openButton(doc)
                }
                if let text = sc.text, !text.isEmpty {
                    pdfTextDisclosure(text, pageCount: page.pageCount)
                }
            }
        } else {
            fileCard(sc, doc: doc)
        }
    }

    private func openButton(_ doc: URL) -> some View {
        Button("Open") { NSWorkspace.shared.open(doc) }
            .buttonStyle(.plain)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Theme.accent.opacity(0.12), in: Capsule())
    }

    /// Non-PDF documents, a PDF that has not synced yet, or one PDFKit cannot read.
    private func fileCard(_ sc: SharedContent, doc: URL?) -> some View {
        let kind = (sc.mimeType?.contains("pdf") == true) ? "PDF" : (sc.mimeType ?? "Document")
        return HStack(spacing: 10) {
            Image(systemName: "doc.richtext")
                .font(.system(size: 22))
                .foregroundStyle(Theme.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(sc.fileName ?? "Shared document")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(doc != nil ? "\(kind) · captured in the note"
                                : "\(kind) · on your iPhone — its text is captured in the note")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textMuted)
            }
            if let doc {
                Spacer(minLength: 8)
                openButton(doc)
            }
        }
    }

    /// The extracted PDF text, in the note: a quiet collapsed row; opened it shows the first
    /// stretch faded out, with "Show all N pages" for the whole text (phone `PDFTextDisclosure`).
    private func pdfTextDisclosure(_ text: String, pageCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.16)) { textExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "text.justify.left")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    Text("Text from the PDF")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: 4)
                    Text(CapturePDFPreview.pageCountLabel(pageCount))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textMuted)
                    Image(systemName: textExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.textMuted)
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if textExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    if textShowAll {
                        ScrollView {
                            Text(text)
                                .font(.system(size: 13))
                                .lineSpacing(3)
                                .foregroundStyle(Theme.textSecondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 360)
                        .padding(.horizontal, 14)
                    } else {
                        Text(String(text.prefix(1200)))
                            .font(.system(size: 13))
                            .lineSpacing(3)
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .mask(LinearGradient(stops: [.init(color: .black, location: 0),
                                                         .init(color: .black, location: 0.78),
                                                         .init(color: .clear, location: 1)],
                                                 startPoint: .top, endPoint: .bottom))
                            .frame(maxHeight: 150, alignment: .top)
                            .clipped()
                            .padding(.horizontal, 14)
                    }
                    Button {
                        withAnimation(.easeOut(duration: 0.16)) { textShowAll.toggle() }
                    } label: {
                        Text(textShowAll ? "Show less"
                             : (pageCount == 1 ? "Show the whole page" : "Show all \(pageCount) pages"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .background(Theme.surface.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(Theme.hairline.opacity(0.09), lineWidth: 0.5))
    }

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
                case .url:
                    linkCard(sc)
                case .text:
                    Text(sc.text ?? "")
                        .font(.system(size: 13.5))
                        .italic()
                        .foregroundStyle(Theme.textPrimary.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                case .image:
                    imageBlock(sc)
                case .file:
                    fileBlock(sc)
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
