import SwiftUI
import AppKit
import QuickLookUI
import UniformTypeIdentifiers

/// The note body's photo pieces on the Mac (Q325, mock Q128-mac-note-photos, D181/D182):
/// the card for a photo whose file has not arrived, the Quick Look viewer, and what a paste or
/// drop may carry. The rules (states, copy, sizes) live in the shared `NotePhoto`.

/// The phone's `ImageEmbed` card, drawn as an attachment image: a dark gradient, 160pt tall,
/// with a spinner and "Downloading from iCloud…" while the file is on its way, or the plain
/// photo glyph when no file is coming.
enum NotePhotoCard {
    /// The mock draws the card at most 360pt wide (the Mac thumbnail's width).
    static let maxWidth: CGFloat = 360

    static func width(column: CGFloat) -> CGFloat {
        column > 0 && column < 4000 ? min(column, maxWidth) : maxWidth
    }

    static func image(_ slot: NotePhoto.Slot, width: CGFloat) -> NSImage {
        let size = NSSize(width: width, height: NotePhoto.cardHeight)
        return NSImage(size: size, flipped: false) { rect in
            let ink = BodyTextView.hexColor(NotePhoto.cardInkHex)
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
                                    xRadius: NotePhoto.cardCornerRadius, yRadius: NotePhoto.cardCornerRadius)
            NSGradient(starting: BodyTextView.hexColor(NotePhoto.cardGradientHex.0),
                       ending: BodyTextView.hexColor(NotePhoto.cardGradientHex.1))?.draw(in: path, angle: -45)
            NSColor(Theme.hairline).setStroke()
            path.lineWidth = 1
            path.stroke()

            switch slot {
            case .missing:
                let config = NSImage.SymbolConfiguration(pointSize: 30, weight: .regular)
                    .applying(.init(paletteColors: [ink]))
                if let glyph = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)?
                    .withSymbolConfiguration(config) {
                    let g = glyph.size
                    glyph.draw(in: NSRect(x: rect.midX - g.width / 2, y: rect.midY - g.height / 2,
                                          width: g.width, height: g.height))
                }
            default:
                let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: ink]
                let label = NotePhoto.downloadingCopy as NSString
                let text = label.size(withAttributes: attrs)
                let ring: CGFloat = 18, gap: CGFloat = 8
                let top = rect.midY + (ring + gap + text.height) / 2
                // Spinner: a faint ring with its top quarter lit (a still of the phone's spinner).
                let centre = NSPoint(x: rect.midX, y: top - ring / 2)
                let r = ring / 2 - 1
                let faint = NSBezierPath(ovalIn: NSRect(x: centre.x - r, y: centre.y - r, width: 2 * r, height: 2 * r))
                ink.withAlphaComponent(0.3).setStroke()
                faint.lineWidth = 2
                faint.stroke()
                let arc = NSBezierPath()
                arc.appendArc(withCenter: centre, radius: r, startAngle: 45, endAngle: 135)
                ink.setStroke()
                arc.lineWidth = 2
                arc.lineCapStyle = .round
                arc.stroke()
                label.draw(at: NSPoint(x: rect.midX - text.width / 2, y: top - ring - gap - text.height),
                           withAttributes: attrs)
            }
            return true
        }
    }
}

/// macOS Quick Look for a note photo: zoom from the photo, and Quick Look's own Markup, which
/// saves into the file. When the panel lets go of the note, a changed file is reported so the
/// memo's photo row is re-mirrored (the phone gets the marked-up photo). The responder chain
/// hands the panel over (`SelfSizingTextView.beginPreviewPanelControl`).
@MainActor
final class NotePhotoViewer: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = NotePhotoViewer()

    private(set) var url: URL?
    private var sourceFrame: (() -> NSRect)?
    private var sourceImage: NSImage?
    private var stamp: Date?
    private var onEdited: ((URL) -> Void)?

    func show(url: URL, sourceFrame: @escaping () -> NSRect, sourceImage: NSImage?,
              onEdited: @escaping (URL) -> Void) {
        self.url = url
        self.sourceFrame = sourceFrame
        self.sourceImage = sourceImage
        self.onEdited = onEdited
        stamp = Self.modified(url)
        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible { panel.reloadData() } else { panel.makeKeyAndOrderFront(nil) }
    }

    /// The panel let go of the note's text view: report a markup save.
    func finished() {
        guard let url, let report = onEdited else { return }
        let changed = Self.modified(url) != stamp
        self.url = nil
        onEdited = nil
        if changed { report(url) }
    }

    private static func modified(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    // MARK: QLPreviewPanelDataSource

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { url == nil ? 0 : 1 }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        MainActor.assumeIsolated { (url ?? URL(fileURLWithPath: "/")) as NSURL }
    }

    // MARK: QLPreviewPanelDelegate — the zoom lifts off the photo itself

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, sourceFrameOnScreenFor item: (any QLPreviewItem)!) -> NSRect {
        MainActor.assumeIsolated { sourceFrame?() ?? .zero }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, transitionImageFor item: (any QLPreviewItem)!,
                                  contentRect: UnsafeMutablePointer<NSRect>!) -> Any! {
        MainActor.assumeIsolated { sourceImage }
    }
}

/// What a paste or drop carries that the note can take as photos.
enum NotePhotoPayload {
    /// Image files named on the pasteboard (a Finder copy, a file drop), as bytes.
    static func fileImages(_ pb: NSPasteboard) -> [Data] {
        let urls = (pb.readObjects(forClasses: [NSURL.self],
                                   options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        return urls.compactMap { url in
            guard NotePhoto.acceptedExtensions.contains(url.pathExtension.lowercased()) else { return nil }
            return try? Data(contentsOf: url, options: .mappedIfSafe)
        }
    }

    /// Raw picture data (a screenshot, an image copied from a page).
    static func imageData(_ pb: NSPasteboard) -> Data? {
        pb.data(forType: .png) ?? pb.data(forType: .tiff)
    }

    /// The photos a paste/drop should become, in order. A Finder copy carries both the file and
    /// its name as text, so files win; plain text (or text beside an image, as a web page copy
    /// carries) stays a normal text paste.
    static func photos(_ pb: NSPasteboard) -> [Data] {
        let files = fileImages(pb)
        if !files.isEmpty { return files }
        if let text = pb.string(forType: .string), !text.isEmpty { return [] }
        return imageData(pb).map { [$0] } ?? []
    }
}
