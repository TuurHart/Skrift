import SwiftUI

/// Track B (mock share-ingest-wave2 m3): the A6-extracted PDF text, IN the note —
/// a quiet collapsed row under the inline PDF block; expanded it flows the first
/// stretch in the note's own type (dimmed, subordinate to the user's words) with
/// a fade + "Show all N pages" into the full reader. The note stays the user's:
/// their ramble first, the document second, its guts third.
struct PDFTextDisclosure: View {
    let text: String
    let pageCount: Int
    /// Present the full reader (the host owns the sheet).
    var onShowAll: () -> Void

    @State private var expanded = false

    private var preview: String {
        String(text.prefix(1200))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(Theme.Motion.snappy) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.skAccentSoft)
                        .frame(width: 22, height: 22)
                        .overlay(
                            Image(systemName: "text.justify.left")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.skAccent)
                        )
                    Text("Text from the PDF")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.skText)
                    Spacer(minLength: 4)
                    Text(pageCount == 1 ? "1 page" : "\(pageCount) pages")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.skTextFaint)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.skTextFaint)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("pdf-text-disclosure")

            if expanded {
                VStack(alignment: .leading, spacing: 0) {
                    Text(preview)
                        .font(.system(size: 13.5))
                        .foregroundStyle(Color.skTextDim)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .mask(
                            // The mock's fade: the preview trails off, never a hard cut.
                            LinearGradient(stops: [.init(color: .black, location: 0),
                                                   .init(color: .black, location: 0.78),
                                                   .init(color: .clear, location: 1)],
                                           startPoint: .top, endPoint: .bottom)
                        )
                        .frame(maxHeight: 170, alignment: .top)
                        .clipped()
                        .padding(.horizontal, 14)
                    Button(action: onShowAll) {
                        Text(pageCount == 1 ? "Show the whole page" : "Show all \(pageCount) pages")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.skAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("pdf-text-show-all")
                }
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.skBorder).frame(height: 0.5).padding(.horizontal, 12)
                }
            }
        }
        .background(Color.skSurface.opacity(0.55), in: .rect(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Color.skBorder, lineWidth: 0.5)
        )
    }
}

/// The pushed reader: the whole extracted text, selectable, in reading type.
struct PDFTextReaderView: View {
    let title: String
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text)
                    .font(.system(size: 15))
                    .lineSpacing(5)
                    .foregroundStyle(Color.skText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.Space.margin)
                    .padding(.vertical, 14)
            }
            .background(Color.skBg)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
