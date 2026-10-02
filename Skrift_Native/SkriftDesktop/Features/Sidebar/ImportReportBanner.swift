import SwiftUI

/// The list banner for what an import skipped or failed (Q137 / C199 / C202): the headline,
/// one line per file with its reason, a dismiss button. The phone draws the same copy
/// (`ImportReport.headline` / `bannerLines`) in its own `ImportReportBanner`.
struct ImportReportBanner: View {
    let report: ImportReport
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.amber)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(report.headline)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                ForEach(Array(report.bannerLines().enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.textMuted)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
            .accessibilityLabel("Dismiss import report")
        }
        .padding(10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline.opacity(0.12), lineWidth: 1))
        .accessibilityIdentifier("import-report-banner")
    }
}
