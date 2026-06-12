import SwiftUI

/// Settings → Models: the on-device ML models — downloaded state + size on
/// disk (read-only v1; delete/re-download = later if ever needed). The data
/// comes from `ModelInventory` (FluidAudio cache directories).
struct ModelsView: View {
    @State private var entries: [ModelInventory.Entry] = []

    private var totalLine: String {
        let total = entries.compactMap(\.sizeBytes).reduce(0, +)
        return total > 0 ? "Total: \(ModelInventory.format(bytes: total))" : "No models downloaded yet."
    }

    var body: some View {
        Form {
            Section {
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(entry.name)
                                .font(.system(size: 15, weight: .medium))
                            Spacer()
                            if let size = entry.sizeBytes {
                                Text(ModelInventory.format(bytes: size))
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.skTextDim)
                            } else {
                                Text("Not downloaded")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.skTextFaint)
                            }
                        }
                        Text(entry.detail)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.skTextDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 2)
                    .accessibilityIdentifier("model-row-\(entry.id)")
                }
            } footer: {
                Text("\(totalLine) Models download automatically when first needed and run fully on-device — nothing leaves your phone.")
            }
        }
        .navigationTitle("Models")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { entries = ModelInventory.entries() }
        .refreshable { entries = ModelInventory.entries() }
    }
}
