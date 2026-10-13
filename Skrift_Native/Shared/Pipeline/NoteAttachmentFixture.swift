#if DEBUG
import Foundation
import AVFoundation
import CoreGraphics
import CoreVideo

/// DEBUG files for the attachment screenshots and tests (Q391): a short real `.mov`, a DXF and a
/// one-page PDF, made in code so no binary fixture is checked in. Both apps' seeders and the Mac
/// tests call the same writers.
enum NoteAttachmentFixture {

    /// The seeded note's body (mock Q384's "Engine tick" note, shortened): text, a large video,
    /// a photo, a DXF card and a PDF card.
    static let body = """
    Rui opened the bonnet so I could film it idling. Listen for the tick in the first ten seconds; that's the one Rui means.

    [[vid_001]]

    He thinks it's the cam chain tensioner. The part number on the old one:

    [[img_001]]

    The loom drawing for the new fan, to cut at the makerspace, and his quote:

    [[file_001]]

    [[file_002]]

    Order the tensioner on Friday. Ask whether the fan bracket fits the 124 too.
    """

    static let videoName = "engine-idle.mov"
    static let dxfName = "fan-loom-bracket-rev-c.dxf"
    static let pdfName = "orcamento-oficina.pdf"

    /// The three entries `body` points at, written beside `dir` under their shared filenames.
    /// Returns the manifest (vid_001, file_001, file_002 in that order) and the large list.
    static func write(into dir: URL, owner: UUID) -> (manifest: [NoteAttachmentEntry], large: [String]) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let vid = NoteAttachment.filename(owner: owner, number: 1, kind: NoteAttachment.Kind.video, ext: "mov")
        let dxf = NoteAttachment.filename(owner: owner, number: 2, kind: NoteAttachment.Kind.file, ext: "dxf")
        let pdf = NoteAttachment.filename(owner: owner, number: 3, kind: NoteAttachment.Kind.file, ext: "pdf")
        let seconds = 2.0
        writeMovie(to: dir.appendingPathComponent(vid), seconds: seconds)
        writeDXF(to: dir.appendingPathComponent(dxf))
        writePDF(to: dir.appendingPathComponent(pdf))
        func bytes(_ n: String) -> Int {
            (try? FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent(n).path)[.size] as? Int) ?? 0
        }
        let manifest = [
            NoteAttachmentEntry(kind: NoteAttachment.Kind.video, filename: vid, name: videoName,
                                uti: "com.apple.quicktime-movie", byteCount: bytes(vid), durationSeconds: seconds),
            NoteAttachmentEntry(kind: NoteAttachment.Kind.file, filename: dxf, name: dxfName,
                                uti: NoteAttachment.uti(forFilename: dxfName), byteCount: bytes(dxf)),
            NoteAttachmentEntry(kind: NoteAttachment.Kind.file, filename: pdf, name: pdfName,
                                uti: "com.adobe.pdf", byteCount: bytes(pdf)),
        ]
        return (manifest, [vid])
    }

    /// A landscape 640×360 H.264 movie: a dark engine-bay gradient with a moving bar, `seconds` long.
    /// Synchronous (the writer finishes before this returns).
    static func writeMovie(to url: URL, seconds: Double = 2, size: CGSize = CGSize(width: 640, height: 360)) {
        try? FileManager.default.removeItem(at: url)
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mov) else { return }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height),
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: Int(size.width), kCVPixelBufferHeightKey as String: Int(size.height),
        ])
        writer.add(input)
        guard writer.startWriting() else { return }
        writer.startSession(atSourceTime: .zero)
        let fps: Int32 = 10
        let frames = Int(seconds * Double(fps))
        for i in 0..<frames {
            while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }
            guard let pool = adaptor.pixelBufferPool else { break }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let pb = buffer else { break }
            draw(into: pb, size: size, t: CGFloat(i) / CGFloat(max(1, frames - 1)))
            adaptor.append(pb, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: fps))
        }
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
    }

    private static func draw(into pb: CVPixelBuffer, size: CGSize, t: CGFloat) {
        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }
        guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: Int(size.width), height: Int(size.height),
                                  bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else { return }
        let colors = [CGColor(red: 0.16, green: 0.20, blue: 0.24, alpha: 1), CGColor(red: 0.42, green: 0.36, blue: 0.28, alpha: 1)]
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1]) {
            ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
        }
        // The engine block and a belt that moves frame to frame.
        ctx.setFillColor(CGColor(red: 0.08, green: 0.09, blue: 0.10, alpha: 1))
        ctx.fill(CGRect(x: size.width * 0.22, y: size.height * 0.22, width: size.width * 0.56, height: size.height * 0.5))
        ctx.setStrokeColor(CGColor(red: 0.85, green: 0.78, blue: 0.62, alpha: 1))
        ctx.setLineWidth(10)
        ctx.strokeEllipse(in: CGRect(x: size.width * 0.30, y: size.height * 0.32, width: 110, height: 110))
        ctx.setFillColor(CGColor(red: 0.95, green: 0.55, blue: 0.20, alpha: 1))
        ctx.fill(CGRect(x: size.width * (0.25 + 0.4 * t), y: size.height * 0.78, width: 60, height: 14))
    }

    /// A small ASCII DXF (one line, one circle) — enough for the card's kind and size.
    static func writeDXF(to url: URL) {
        var s = "0\nSECTION\n2\nENTITIES\n"
        for i in 0..<120 {
            s += "0\nLINE\n8\n0\n10\n\(i)\n20\n0\n11\n\(i + 40)\n21\n80\n"
        }
        s += "0\nCIRCLE\n8\n0\n10\n50\n20\n50\n40\n25\n0\nENDSEC\n0\nEOF\n"
        try? s.data(using: .utf8)?.write(to: url)
    }

    /// A one-page A4 PDF with a heading and lines, drawn with Core Graphics.
    static func writePDF(to url: URL) {
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
        ctx.beginPDFPage(nil)
        ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(box)
        ctx.setFillColor(CGColor(red: 0.78, green: 0.27, blue: 0.24, alpha: 1))
        ctx.fill(CGRect(x: 48, y: 760, width: 220, height: 28))
        ctx.setFillColor(CGColor(gray: 0.82, alpha: 1))
        for i in 0..<22 { ctx.fill(CGRect(x: 48, y: 700 - CGFloat(i) * 26, width: i % 4 == 3 ? 300 : 499, height: 9)) }
        ctx.endPDFPage()
        ctx.closePDF()
    }
}
#endif
