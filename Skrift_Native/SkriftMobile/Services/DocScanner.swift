import Foundation
import UIKit
import PDFKit

/// In-app document scanning (note feature wave, chunk 9): VisionKit's document
/// camera hands us page images; they become ONE PDF saved through the existing
/// C3 file-capture path — so the scan is a normal capture memo (file card +
/// QuickLook + annotation), syncs like any shared file, and the Mac views it
/// like any other capture. Pages are OCR'd on-device into `sharedContent.text`
/// so the scan is findable from the memos search (chunk 6's matcher already
/// reads that field).
@MainActor
enum DocScanner {
    /// Render the scanned pages into a single PDF (each page at its image size).
    nonisolated static func renderPDF(pages: [UIImage]) -> Data? {
        guard !pages.isEmpty else { return nil }
        let bounds = CGRect(origin: .zero, size: pages[0].size)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        return renderer.pdfData { ctx in
            for page in pages {
                ctx.beginPage(withBounds: CGRect(origin: .zero, size: page.size), pageInfo: [:])
                page.draw(in: CGRect(origin: .zero, size: page.size))
            }
        }
    }

    /// OCR every page (same on-device Vision as the photo indexer), joined and
    /// capped — enough for search, not a full text archive.
    nonisolated static func recognizeText(pages: [UIImage]) async -> String {
        var texts: [String] = []
        for page in pages {
            guard let cg = page.cgImage else { continue }
            let text = await PhotoTextIndexer.recognize(cgImage: cg)
            if !text.isEmpty { texts.append(text) }
        }
        return String(texts.joined(separator: "\n\n").prefix(4000))
    }

    /// The scan's display name — "Scan 7 Jul 2026, 14.30.pdf".
    static func displayName(now: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy, HH.mm"
        return "Scan \(f.string(from: now)).pdf"
    }

    /// Persist a finished scan as a C3 file-capture memo (mirrors the share-
    /// extension drainer's construction byte-for-byte) and return its id so
    /// the caller can open it.
    static func save(pages: [UIImage], repository: NotesRepository) async -> UUID? {
        guard let pdf = renderPDF(pages: pages) else { return nil }
        let memoID = UUID()
        let destName = "file_\(memoID.uuidString).pdf"
        let destURL = AppPaths.recordingsDirectory.appendingPathComponent(destName)
        do {
            try pdf.write(to: destURL)
        } catch {
            DevLog.log("docScan: PDF write failed \(error)")
            return nil
        }

        let ocr = await recognizeText(pages: pages)
        let sharedContent = SharedContent(
            type: .file,
            text: ocr.isEmpty ? nil : ocr,      // searchable, never shown as prose
            filePath: destName,
            fileName: displayName(),
            mimeType: "application/pdf"
        )
        let memo = Memo.make(
            id: memoID,
            audioFilename: "",                  // no audio — the capture discriminator
            duration: 0,
            recordedAt: Date(),
            tags: [],
            syncStatus: .waiting,
            transcript: nil,
            transcriptStatus: .done,
            significance: 0,
            metadata: nil,
            sharedContent: sharedContent,
            annotationText: nil
        )
        repository.insert(memo)
        AssetMaterializer.capture(memoID: memoID, repository: repository)
        DevLog.log("docScan: saved \(pages.count) page(s) → \(destName) (ocr \(ocr.count) chars)")
        return memoID
    }
}
