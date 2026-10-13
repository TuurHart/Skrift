import AVFoundation
import PDFKit
import SwiftUI
import UIKit

/// Draws a note attachment block as one image for the editor's text attachment (D199, D202, mock
/// Q384). Every size, word and colour comes from `NoteAttachment` (Shared); this only paints.
/// SMALL = Apple's grey card (name on two lines, kind · size, icon or poster on the right).
/// LARGE = a video's poster with the play button and duration (cut at 420 pt), a PDF's first page,
/// any other file the card.
enum NoteAttachmentArt {

    private static let cache = NSCache<NSString, UIImage>()

    static func image(_ entry: NoteAttachmentEntry, size: NoteAttachment.Size, width: CGFloat,
                      fileURL: URL?, dark: Bool) -> UIImage {
        let key = "\(entry.filename)|\(size.rawValue)|\(Int(width))|\(dark)|\(fileURL != nil)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let made: UIImage
        if size == .large, entry.kind == NoteAttachment.Kind.video, let url = fileURL {
            made = videoBlock(entry, width: width, url: url)
        } else if size == .large, NoteAttachment.isPDF(entry), let url = fileURL, let page = pdfPage(url, width: width) {
            made = page
        } else {
            made = card(entry, width: width, fileURL: fileURL, dark: dark)
        }
        cache.setObject(made, forKey: key)
        return made
    }

    // MARK: video (large)

    static func poster(_ url: URL, maxSide: CGFloat) -> UIImage? {
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: maxSide * 2, height: maxSide * 2)
        guard let cg = try? gen.copyCGImage(at: CMTime(seconds: 0.1, preferredTimescale: 600), actualTime: nil) else { return nil }
        return UIImage(cgImage: cg)
    }

    private static func videoBlock(_ entry: NoteAttachmentEntry, width: CGFloat, url: URL) -> UIImage {
        let frame = poster(url, maxSide: width)
        let h = NoteAttachment.videoHeight(width: width, natural: frame?.size, maxHeight: NoteAttachment.phoneVideoMaxHeight)
        let size = CGSize(width: width, height: h)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let rect = CGRect(origin: .zero, size: size)
            UIBezierPath(roundedRect: rect, cornerRadius: NoteAttachment.mediaCornerRadius).addClip()
            UIColor.black.setFill(); ctx.fill(rect)
            if let frame {
                // Aspect-fill, cropped to the middle (pick 2).
                let scale = max(width / frame.size.width, h / frame.size.height)
                let fw = frame.size.width * scale, fh = frame.size.height * scale
                frame.draw(in: CGRect(x: (width - fw) / 2, y: (h - fh) / 2, width: fw, height: fh))
            }
            // The play button: a 62 pt frosted disc, centred.
            let d: CGFloat = 62
            let disc = CGRect(x: (width - d) / 2, y: (h - d) / 2, width: d, height: d)
            UIColor.white.withAlphaComponent(0.62).setFill()
            UIBezierPath(ovalIn: disc).fill()
            let tri = UIBezierPath()
            tri.move(to: CGPoint(x: disc.midX - 8, y: disc.midY - 13))
            tri.addLine(to: CGPoint(x: disc.midX - 8, y: disc.midY + 13))
            tri.addLine(to: CGPoint(x: disc.midX + 14, y: disc.midY))
            tri.close()
            UIColor(white: 0.23, alpha: 1).setFill(); tri.fill()
            // The duration label, bottom right (pick 5).
            if let label = NoteAttachment.durationLabel(entry) {
                let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .bold),
                                                            .foregroundColor: UIColor.white]
                let t = label as NSString
                let ts = t.size(withAttributes: attrs)
                let pill = CGRect(x: width - ts.width - 16 - 9, y: h - ts.height - 6 - 9, width: ts.width + 16, height: ts.height + 6)
                UIColor.black.withAlphaComponent(0.55).setFill()
                UIBezierPath(roundedRect: pill, cornerRadius: 7).fill()
                t.draw(at: CGPoint(x: pill.minX + 8, y: pill.minY + 3), withAttributes: attrs)
            }
        }
    }

    // MARK: PDF (large, pick 7: first page, 14 pt corners, 1 pt border)

    private static func pdfPage(_ url: URL, width: CGFloat) -> UIImage? {
        guard let doc = PDFDocument(url: url), let page = doc.page(at: 0) else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0 else { return nil }
        let size = CGSize(width: width, height: (width * bounds.height / bounds.width).rounded())
        let thumb = page.thumbnail(of: size, for: .mediaBox)
        return UIGraphicsImageRenderer(size: size).image { _ in
            let rect = CGRect(origin: .zero, size: size)
            let path = UIBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: NoteAttachment.mediaCornerRadius)
            path.addClip()
            UIColor.white.setFill(); UIRectFill(rect)
            thumb.draw(in: rect)
            UIColor.black.withAlphaComponent(0.09).setStroke(); path.lineWidth = 1; path.stroke()
        }
    }

    // MARK: the grey card (small, pick 4)

    private static func hex(_ v: UInt32) -> UIColor {
        UIColor(red: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: 1)
    }

    private static func card(_ entry: NoteAttachmentEntry, width: CGFloat, fileURL: URL?, dark: Bool) -> UIImage {
        let size = CGSize(width: width, height: NoteAttachment.cardMinHeight)
        let iconW: CGFloat = entry.kind == NoteAttachment.Kind.video ? NoteAttachment.cardThumbSize.width : 36
        let thumb = entry.kind == NoteAttachment.Kind.video ? fileURL.flatMap { poster($0, maxSide: 60) } : nil
        return UIGraphicsImageRenderer(size: size).image { _ in
            let rect = CGRect(origin: .zero, size: size)
            hex(dark ? NoteAttachment.cardFillDarkHex : NoteAttachment.cardFillLightHex).setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: NoteAttachment.cardCornerRadius).fill()
            let textW = width - 14 - 12 - iconW - 12
            let para = NSMutableParagraphStyle(); para.lineBreakMode = .byCharWrapping
            let title = NSAttributedString(string: entry.name, attributes: [
                .font: UIFont.systemFont(ofSize: NoteAttachment.cardTitleSize, weight: .semibold),
                .foregroundColor: UIColor(Color.skText), .paragraphStyle: para])
            let sub = NSAttributedString(string: NoteAttachment.subtitle(entry), attributes: [
                .font: UIFont.systemFont(ofSize: NoteAttachment.cardSubtitleSize),
                .foregroundColor: UIColor(Color.skTextDim)])
            let titleH = min(title.boundingRect(with: CGSize(width: textW, height: 40), options: .usesLineFragmentOrigin, context: nil).height, 38)
            let subH = sub.size().height
            let top = (size.height - titleH - 2 - subH) / 2
            title.draw(with: CGRect(x: 14, y: top, width: textW, height: titleH), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
            sub.draw(with: CGRect(x: 14, y: top + titleH + 2, width: textW, height: subH), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
            if let thumb {
                let t = CGRect(x: width - 12 - iconW, y: (size.height - iconW) / 2, width: iconW, height: iconW)
                UIGraphicsGetCurrentContext()?.saveGState()
                UIBezierPath(roundedRect: t, cornerRadius: 6).addClip()
                let s = max(iconW / thumb.size.width, iconW / thumb.size.height)
                thumb.draw(in: CGRect(x: t.midX - thumb.size.width * s / 2, y: t.midY - thumb.size.height * s / 2,
                                      width: thumb.size.width * s, height: thumb.size.height * s))
                UIGraphicsGetCurrentContext()?.restoreGState()
            } else {
                // The file icon: a white page with a folded corner, three grey lines and the badge.
                let page = CGRect(x: width - 12 - 36, y: (size.height - 46) / 2, width: 36, height: 46)
                UIColor.white.setFill(); UIBezierPath(roundedRect: page, cornerRadius: 4).fill()
                UIColor.black.withAlphaComponent(0.18).setStroke()
                let border = UIBezierPath(roundedRect: page, cornerRadius: 4); border.lineWidth = 0.5; border.stroke()
                hex(0xd5d7de).setFill()
                for i in 0..<3 { UIRectFill(CGRect(x: page.minX + 6, y: page.minY + 12 + CGFloat(i) * 5, width: 22, height: 2)) }
                let badge = NoteAttachment.badge(entry) as NSString
                let battrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 8.5, weight: .heavy), .foregroundColor: UIColor.white]
                let bs = badge.size(withAttributes: battrs)
                let b = CGRect(x: page.minX + 3, y: page.maxY - 5 - bs.height - 2, width: page.width - 6, height: bs.height + 2)
                hex(NoteAttachment.badgeHex(entry)).setFill(); UIBezierPath(roundedRect: b, cornerRadius: 2).fill()
                badge.draw(at: CGPoint(x: b.midX - bs.width / 2, y: b.minY + 1), withAttributes: battrs)
            }
        }
    }
}
