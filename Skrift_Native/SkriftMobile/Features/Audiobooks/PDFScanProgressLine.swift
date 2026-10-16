import SwiftUI

/// Q461 (D213): what the PDF reader shows while on-device text recognition reads a scanned PDF
/// (`LibraryPDF.needsRecognition`), before the reading view opens. One quiet line, centred.
struct PDFScanProgressLine: View {
    static let label = "Reading the scan…"

    var body: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(Self.label)
                .font(.system(size: 14))
                .foregroundStyle(Color.skTextDim)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("library-pdf-reading-scan")
    }
}
