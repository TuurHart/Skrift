import CoreGraphics
import ImageIO
import PDFKit
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Paints a note block as one image for the editor's text attachment, the SAME painter on the
/// phone, iPad and Mac (D199, D202, D224, mocks Q384 and Q542). Every size, word and colour comes
/// from `NoteAttachment`; this only draws. SMALL = the picture itself, longest side a third of
/// the text width, never cropped (a photo, a video's frame with its play mark, a PDF's first page);
/// a file with no preview keeps Apple's grey card (name on two lines, kind · size, file icon).
/// LARGE = a video's poster with the play button and duration (cut at `maxVideoHeight`), a PDF's
/// first page, a photo at the full text width.
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

    /// A video or file block in a text column `column` wide (`wide` = iPad / Mac, which cap it).
    /// A video's poster comes from `NotePoster` only (never decoded here, so a note with a video
    /// opens without touching the file on the main thread); until it lands the block draws without
    /// its picture and the editor swaps it in on `NotePoster.ready`.
    static func image(_ entry: NoteAttachmentEntry, size: NoteAttachment.Size, column: CGFloat, wide: Bool,
                      maxVideoHeight: CGFloat = NoteAttachment.phoneVideoMaxHeight,
                      fileURL: URL?, dark: Bool) -> Image {
        let frame = entry.kind == NoteAttachment.Kind.video ? fileURL.flatMap { NotePoster.shared.frame(for: $0) }.map(image) : nil
        let key = "\(entry.filename)|\(size.rawValue)|\(Int(column))|\(wide)|\(Int(maxVideoHeight))|\(dark)|\(fileURL != nil)|\(frame != nil)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let made: Image
        let mediaWidth = NoteAttachment.blockWidth(column: column, wide: wide, largeMedia: true)
        let pageWidth = NoteAttachment.blockWidth(column: column, wide: wide, largeMedia: false)
        let pictureColumn = NoteAttachment.pictureColumn(column: column, wide: wide)
        if size == .large, entry.kind == NoteAttachment.Kind.video, fileURL != nil {
            made = videoBlock(entry, width: mediaWidth, maxHeight: maxVideoHeight, frame: frame)
        } else if size == .large, NoteAttachment.isPDF(entry), let url = fileURL, let page = pdfPage(url, width: pageWidth) {
            made = page
        } else if size == .small, entry.kind == NoteAttachment.Kind.video, fileURL != nil {
            made = smallVideo(frame: frame, column: pictureColumn)
        } else if size == .small, NoteAttachment.isPDF(entry), let url = fileURL, let page = smallPDF(url, column: pictureColumn) {
            made = page
        } else {
            made = card(NoteAttachment.card(entry), width: pageWidth, thumb: frame, dark: dark)
        }
        cache.setObject(made, forKey: key)
        return made
    }

    /// A photo's picture at its size (Q545): small a third of `column` on its longest side, large the
    /// full `column`, whole either way. `source` is any decoded copy of the photo, drawn to fit.
    static func picture(_ source: Image, size: NoteAttachment.Size, column: CGFloat) -> Image {
        let s = NoteAttachment.pictureSize(natural: source.size, size: size, column: column)
        let radius = size == .small ? NoteAttachment.smallPictureCornerRadius : min(s.width, s.height) * NoteLook.photoCornerFraction
        return render(s) {
            let rect = CGRect(origin: .zero, size: s)
            rounded(rect, radius).addClip()
            draw(source, in: rect)
        }
    }

    /// The pixel size of a picture file with its orientation applied, read from the header only.
    static func pixelSize(of url: URL) -> CGSize? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue, w > 0, h > 0 else { return nil }
        let turned = [5, 6, 7, 8].contains((props[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1)
        return turned ? CGSize(width: h, height: w) : CGSize(width: w, height: h)
    }

    /// The captured PDF drawn small (D224): its first page, longest side a third of `column`.
    /// nil when the file has no readable page (the caller keeps the card).
    static func capturedPDF(fileURL: URL, column: CGFloat) -> Image? {
        let key = "pdfpic|\(Int(column))|\(fileURL.lastPathComponent)|\(stamp(fileURL).key)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let made = smallPDF(fileURL, column: column) else { return nil }
        cache.setObject(made, forKey: key)
        return made
    }

    /// Any other captured (shared) document drawn as the card (mock pick 4: it replaces the old
    /// capture card and its Open button): name, kind · size, the file icon.
    static func fileCard(name: String, fileURL: URL?, width: CGFloat, dark: Bool) -> Image {
        let file = stamp(fileURL)
        return cached("file|\(name)|\(Int(width))|\(dark)|\(file.key)") {
            card(NoteAttachment.capturedFileCard(name: name, byteCount: file.bytes), width: width, thumb: nil, dark: dark)
        }
    }

    private static func cached(_ key: String, _ make: () -> Image) -> Image {
        if let hit = cache.object(forKey: key as NSString) { return hit }
        let made = make()
        cache.setObject(made, forKey: key as NSString)
        return made
    }

    /// One stat per draw: the size goes on the card, size + change time key the cache (a
    /// marked-up photo draws fresh).
    private static func stamp(_ url: URL?) -> (bytes: Int?, key: String) {
        guard let url, let a = try? FileManager.default.attributesOfItem(atPath: url.path) else { return (nil, "-") }
        let bytes = a[.size] as? Int
        let changed = (a[.modificationDate] as? Date)?.timeIntervalSinceReferenceDate ?? 0
        return (bytes, "\(bytes ?? 0)@\(changed)")
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

    // MARK: video (large)

    private static func videoBlock(_ entry: NoteAttachmentEntry, width: CGFloat, maxHeight: CGFloat, frame: Image?) -> Image {
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
            playMark(in: rect, diameter: 62)
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

    // MARK: small video (D224): a small frame of itself with its play mark

    private static func smallVideo(frame: Image?, column: CGFloat) -> Image {
        let size = NoteAttachment.pictureSize(natural: frame?.size, size: .small, column: column)
        return render(size) {
            let rect = CGRect(origin: .zero, size: size)
            rounded(rect, NoteAttachment.smallPictureCornerRadius).addClip()
            Color.black.setFill(); Path(rect: rect).fill()
            if let frame { draw(frame, in: rect) }      // the frame's own shape, so nothing is cut
            playMark(in: rect, diameter: max(22, min(size.width, size.height) * 0.4))
        }
    }

    /// The frosted disc with its play triangle, centred in `rect`.
    private static func playMark(in rect: CGRect, diameter d: CGFloat) {
        let disc = CGRect(x: rect.midX - d / 2, y: rect.midY - d / 2, width: d, height: d)
        Color.white.withAlphaComponent(0.62).setFill()
        Path(ovalIn: disc).fill()
        let k = d / 62
        let tri = Path()
        tri.move(to: CGPoint(x: disc.midX - 8 * k, y: disc.midY - 13 * k))
        #if canImport(UIKit)
        tri.addLine(to: CGPoint(x: disc.midX - 8 * k, y: disc.midY + 13 * k))
        tri.addLine(to: CGPoint(x: disc.midX + 14 * k, y: disc.midY))
        #else
        tri.line(to: CGPoint(x: disc.midX - 8 * k, y: disc.midY + 13 * k))
        tri.line(to: CGPoint(x: disc.midX + 14 * k, y: disc.midY))
        #endif
        tri.close()
        Color(white: 0.23, alpha: 1).setFill(); tri.fill()
    }

    // MARK: PDF (large, pick 7: first page, 14 pt corners, 1 pt border; small, D224: the same page, a third)

    private static func pdfPage(_ url: URL, width: CGFloat) -> Image? {
        guard let doc = PDFDocument(url: url), let page = doc.page(at: 0) else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let size = NoteAttachment.pictureSize(natural: bounds.size, size: .large, column: width)
        return pdfPicture(page, size: size, radius: NoteAttachment.mediaCornerRadius, thumbScale: 1)
    }

    private static func smallPDF(_ url: URL, column: CGFloat) -> Image? {
        guard let doc = PDFDocument(url: url), let page = doc.page(at: 0) else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let size = NoteAttachment.pictureSize(natural: bounds.size, size: .small, column: column)
        return pdfPicture(page, size: size, radius: NoteAttachment.smallPictureCornerRadius, thumbScale: 3)
    }

    private static func pdfPicture(_ page: PDFPage, size: CGSize, radius: CGFloat, thumbScale: CGFloat) -> Image {
        let thumb = page.thumbnail(of: CGSize(width: size.width * thumbScale, height: size.height * thumbScale), for: .mediaBox)
        return render(size) {
            let rect = CGRect(origin: .zero, size: size)
            let path = rounded(rect.insetBy(dx: 0.5, dy: 0.5), radius)
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
