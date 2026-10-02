import SwiftUI

/// The list banner for what an import skipped or failed (Q137 / C199 / C202): the headline,
/// one line per file with its reason, a dismiss button. Same copy as the Mac's banner
/// (`ImportReport.headline` / `bannerLines`).
struct ImportReportBanner: View {
    let report: ImportReport
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.skAmber)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(report.headline)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.skText)
                ForEach(Array(report.bannerLines().enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.skTextDim)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.skTextFaint)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss import report")
        }
        .padding(.leading, 12).padding(.vertical, 8).padding(.trailing, 4)
        .background(Color.skElev, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.skBorder, lineWidth: 1))
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("import-report-banner")
    }
}
