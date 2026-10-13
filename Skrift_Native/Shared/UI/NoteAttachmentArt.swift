import AVFoundation
import PDFKit
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Paints a note block as one image for the editor's text attachment, the SAME painter on the
/// phone, iPad and Mac (D199, D202, mock Q384). Every size, word and colour comes from
/// `NoteAttachment`; this only draws. SMALL = Apple's grey card (name on two lines, kind · size,
/// icon or picture on the right). LARGE = a video's poster with the play button and duration
/// (cut at `maxVideoHeight`), a PDF's first page; any other file stays the card.
enum NoteAttachmentArt {

    #if canImport(UIKit)
    typealias Image = UIImage
    typealias Color = UIColor
    typealias Font = UIFont
    typealias Path = UIBezierPath
    #else
    typealias Image = NSImage
    typealias Color = NSColor
    typealias Font = NSFont
    typealias Path = NSBezierPath
    #endif

    private static let cache = NSCache<NSString, Image>()

    /// A video or file block.
    static func image(_ entry: NoteAttachmentEntry, size: NoteAttachment.Size, width: CGFloat,
                      maxVideoHeight: CGFloat = NoteAttachment.phoneVideoMaxHeight,
                      fileURL: URL?, dark: Bool) -> Image {
        let key = "\(entry.filename)|\(size.rawValue)|\(Int(width))|\(Int(maxVideoHeight))|\(dark)|\(fileURL != nil)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let made: Image
        if size == .large, entry.kind == NoteAttachment.Kind.video, let url = fileURL {
            made = videoBlock(entry, width: width, maxHeight: maxVideoHeight, url: url)
        } else if size == .large, NoteAttachment.isPDF(entry), let url = fileURL, let page = pdfPage(url, width: width) {
            made = page
        } else {
            let thumb = entry.kind == NoteAttachment.Kind.video ? fileURL.flatMap { poster($0, maxSide: 60) } : nil
            made = card(NoteAttachment.card(entry), width: width, thumb: thumb, dark: dark)
        }
        cache.setObject(made, forKey: key)
        return made
    }

    /// A photo drawn small (D202): the grey card with the photo on the right.
    static func photoCard(filename: String, fileURL: URL?, width: CGFloat, dark: Bool) -> Image {
        let bytes = fileURL.flatMap { (try? FileManager.default.attributesOfItem(atPath: $0.path)[.size]) as? Int }
        let thumb = fileURL.flatMap { loadImage($0) }
        return card(NoteAttachment.photoCard(filename: filename, byteCount: bytes), width: width, thumb: thumb, dark: dark)
    }

    /// The captured PDF drawn small (D202): the grey card, "PDF document · N pages".
    static func pdfCard(name: String, pages: Int?, fileURL: URL?, width: CGFloat, dark: Bool) -> Image {
        let bytes = fileURL.flatMap { (try? FileManager.default.attributesOfItem(atPath: $0.path)[.size]) as? Int }
        return card(NoteAttachment.pdfCard(name: name, pages: pages, byteCount: bytes), width: width, thumb: nil, dark: dark)
    }

    // MARK: drawing shim (one painter, two platforms)

    private static func render(_ size: CGSize, _ draw: @escaping () -> Void) -> Image {
        #if canImport(UIKit)
        return UIGraphicsImageRenderer(size: size).image { _ in draw() }
        #else
        // Flipped, so the y-down geometry below is the same on both platforms.
        let img = NSImage(size: size, flipped: true) { _ in draw(); return true }
        return img
        #endif
    }

    private static func rounded(_ r: CGRect, _ radius: CGFloat) -> Path {
        #if canImport(UIKit)
        return UIBezierPath(roundedRect: r, cornerRadius: radius)
        #else
        return NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
        #endif
    }

    private static func draw(_ image: Image, in r: CGRect) {
        #if canImport(UIKit)
        image.draw(in: r)
        #else
        image.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        #endif
    }

    private static func hex(_ v: UInt32, alpha: CGFloat = 1) -> Color {
        Color(red: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: alpha)
    }

    private static func ink(_ pair: DriftedPair, dark: Bool) -> Color {
        #if canImport(UIKit)
        let p = pair.phone
        #else
        let p = pair.mac
        #endif
        return hex(dark ? p.dark : p.light)
    }

    private static func image(_ cg: CGImage) -> Image {
        #if canImport(UIKit)
        return UIImage(cgImage: cg)
        #else
        return NSImage(cgImage: cg, size: CGSize(width: cg.width, height: cg.height))
        #endif
    }

    /// A downscaled picture (ImageIO decodes at thumbnail size).
    private static func loadImage(_ url: URL, maxPixel: CGFloat = 160) -> Image? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                  kCGImageSourceCreateThumbnailWithTransform: true,
              ] as CFDictionary) else { return nil }
        return image(cg)
    }

    // MARK: video (large)

    static func poster(_ url: URL, maxSide: CGFloat) -> Image? {
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: maxSide * 2, height: maxSide * 2)
        guard let cg = try? gen.copyCGImage(at: CMTime(seconds: 0.1, preferredTimescale: 600), actualTime: nil) else { return nil }
        return image(cg)
    }

    private static func videoBlock(_ entry: NoteAttachmentEntry, width: CGFloat, maxHeight: CGFloat, url: URL) -> Image {
        let frame = poster(url, maxSide: width)
        let h = NoteAttachment.videoHeight(width: width, natural: frame?.size, maxHeight: maxHeight)
        let size = CGSize(width: width, height: h)
        return render(size) {
            let rect = CGRect(origin: .zero, size: size)
            rounded(rect, NoteAttachment.mediaCornerRadius).addClip()
            Color.black.setFill(); Path(rect: rect).fill()
            if let frame {
                // Aspect-fill, cropped to the middle (pick 2).
                let scale = max(width / frame.size.width, h / frame.size.height)
                let fw = frame.size.width * scale, fh = frame.size.height * scale
                draw(frame, in: CGRect(x: (width - fw) / 2, y: (h - fh) / 2, width: fw, height: fh))
            }
            // The play button: a 62 pt frosted disc, centred.
            let d: CGFloat = 62
            let disc = CGRect(x: (width - d) / 2, y: (h - d) / 2, width: d, height: d)
            Color.white.withAlphaComponent(0.62).setFill()
            Path(ovalIn: disc).fill()
            let tri = Path()
            tri.move(to: CGPoint(x: disc.midX - 8, y: disc.midY - 13))
            #if canImport(UIKit)
            tri.addLine(to: CGPoint(x: disc.midX - 8, y: disc.midY + 13))
            tri.addLine(to: CGPoint(x: disc.midX + 14, y: disc.midY))
            #else
            tri.line(to: CGPoint(x: disc.midX - 8, y: disc.midY + 13))
            tri.line(to: CGPoint(x: disc.midX + 14, y: disc.midY))
            #endif
            tri.close()
            Color(white: 0.23, alpha: 1).setFill(); tri.fill()
            // The duration label, bottom right (pick 5).
            if let label = NoteAttachment.durationLabel(entry) {
                let attrs: [NSAttributedString.Key: Any] = [.font: Font.monospacedDigitSystemFont(ofSize: 10.5, weight: .bold),
                                                            .foregroundColor: Color.white]
                let t = label as NSString
                let ts = t.size(withAttributes: attrs)
                let pill = CGRect(x: width - ts.width - 16 - 9, y: h - ts.height - 6 - 9, width: ts.width + 16, height: ts.height + 6)
                Color.black.withAlphaComponent(0.55).setFill()
                rounded(pill, 7).fill()
                t.draw(at: CGPoint(x: pill.minX + 8, y: pill.minY + 3), withAttributes: attrs)
            }
        }
    }

    // MARK: PDF (large, pick 7: first page, 14 pt corners, 1 pt border)

    private static func pdfPage(_ url: URL, width: CGFloat) -> Image? {
        guard let doc = PDFDocument(url: url), let page = doc.page(at: 0) else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0 else { return nil }
        let size = CGSize(width: width, height: (width * bounds.height / bounds.width).rounded())
        let thumb = page.thumbnail(of: size, for: .mediaBox)
        return render(size) {
            let rect = CGRect(origin: .zero, size: size)
            let path = rounded(rect.insetBy(dx: 0.5, dy: 0.5), NoteAttachment.mediaCornerRadius)
            path.addClip()
            Color.white.setFill(); Path(rect: rect).fill()
            draw(thumb, in: rect)
            Color.black.withAlphaComponent(0.09).setStroke(); path.lineWidth = 1; path.stroke()
        }
    }

    // MARK: the grey card (small, pick 4)

    static func card(_ card: NoteAttachment.Card, width: CGFloat, thumb: Image?, dark: Bool) -> Image {
        let size = CGSize(width: width, height: NoteAttachment.cardMinHeight)
        let iconW: CGFloat = card.thumb ? NoteAttachment.cardThumbSize.width : 36
        let titleInk = ink(Palette.textPrimary, dark: dark)
        let subInk = ink(Palette.textSecondary, dark: dark)
        return render(size) {
            let rect = CGRect(origin: .zero, size: size)
            hex(dark ? NoteAttachment.cardFillDarkHex : NoteAttachment.cardFillLightHex).setFill()
            rounded(rect, NoteAttachment.cardCornerRadius).fill()
            let textW = width - 14 - 12 - iconW - 12
            let para = NSMutableParagraphStyle(); para.lineBreakMode = .byCharWrapping
            let title = NSAttributedString(string: card.title, attributes: [
                .font: Font.systemFont(ofSize: NoteAttachment.cardTitleSize, weight: .semibold),
                .foregroundColor: titleInk, .paragraphStyle: para])
            let sub = NSAttributedString(string: card.subtitle, attributes: [
                .font: Font.systemFont(ofSize: NoteAttachment.cardSubtitleSize), .foregroundColor: subInk])
            let titleH = min(ceil(title.boundingRect(with: CGSize(width: textW, height: 40), options: .usesLineFragmentOrigin, context: nil).height), 38)
            let subH = ceil(sub.size().height)
            let top = (size.height - titleH - 2 - subH) / 2
            title.draw(with: CGRect(x: 14, y: top, width: textW, height: titleH), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
            sub.draw(with: CGRect(x: 14, y: top + titleH + 2, width: textW, height: subH), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
            if card.thumb {
                let t = CGRect(x: width - 12 - iconW, y: (size.height - iconW) / 2, width: iconW, height: iconW)
                hex(0xd5d7de).setFill(); rounded(t, 6).fill()
                if let thumb, thumb.size.width > 0, thumb.size.height > 0 {
                    #if canImport(UIKit)
                    UIGraphicsGetCurrentContext()?.saveGState()
                    #else
                    NSGraphicsContext.current?.saveGraphicsState()
                    #endif
                    rounded(t, 6).addClip()
                    let s = max(iconW / thumb.size.width, iconW / thumb.size.height)
                    draw(thumb, in: CGRect(x: t.midX - thumb.size.width * s / 2, y: t.midY - thumb.size.height * s / 2,
                                           width: thumb.size.width * s, height: thumb.size.height * s))
                    #if canImport(UIKit)
                    UIGraphicsGetCurrentContext()?.restoreGState()
                    #else
                    NSGraphicsContext.current?.restoreGraphicsState()
                    #endif
                }
            } else {
                // The file icon: a white page, three grey lines and the badge.
                let page = CGRect(x: width - 12 - 36, y: (size.height - 46) / 2, width: 36, height: 46)
                Color.white.setFill(); rounded(page, 4).fill()
                Color.black.withAlphaComponent(0.18).setStroke()
                let border = rounded(page, 4); border.lineWidth = 0.5; border.stroke()
                hex(0xd5d7de).setFill()
                for i in 0..<3 { Path(rect: CGRect(x: page.minX + 6, y: page.minY + 12 + CGFloat(i) * 5, width: 22, height: 2)).fill() }
                let badge = card.badge as NSString
                let battrs: [NSAttributedString.Key: Any] = [.font: Font.systemFont(ofSize: 8.5, weight: .heavy), .foregroundColor: Color.white]
                let bs = badge.size(withAttributes: battrs)
                let b = CGRect(x: page.minX + 3, y: page.maxY - 5 - bs.height - 2, width: page.width - 6, height: bs.height + 2)
                hex(card.badgeHex).setFill(); rounded(b, 2).fill()
                badge.draw(at: CGPoint(x: b.midX - bs.width / 2, y: b.minY + 1), withAttributes: battrs)
            }
        }
    }
}
