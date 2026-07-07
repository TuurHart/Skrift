import SwiftUI
import MapKit

/// Places map (mock screen 3): pins clustered by place name; tap a cluster →
/// that place's notes in a bottom card. Only memos with location metadata.
struct JournalMapView: View {
    private let repository = NotesRepository.shared
    @State private var clusters: [PlaceCluster] = []
    @State private var selected: PlaceCluster?

    var body: some View {
        ZStack(alignment: .bottom) {
            Map {
                ForEach(clusters) { cluster in
                    Annotation(cluster.name, coordinate: cluster.coordinate) {
                        pin(cluster)
                    }
                }
            }
            .mapStyle(.standard)
            if let selected { placeSheet(selected) }
        }
        .navigationTitle("Places")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            clusters = PlaceCluster.build(from: repository.allMemos())
            if selected == nil { selected = clusters.max { $0.memos.count < $1.memos.count } }
        }
    }

    private func pin(_ cluster: PlaceCluster) -> some View {
        Text("\(cluster.memos.count)")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .frame(minWidth: 22, minHeight: 22)
            .background(Circle().fill(selected?.id == cluster.id ? Color.skAccent : Color.skAccent.opacity(0.7)))
            .shadow(color: Color.skAccent.opacity(0.5), radius: 5, y: 2)
            .onTapGesture { selected = cluster }
    }

    private func placeSheet(_ cluster: PlaceCluster) -> some View {
        JournalCard {
            VStack(alignment: .leading, spacing: 8) {
                JournalCardHeader(title: "\(cluster.name) · \(cluster.memos.count) note\(cluster.memos.count == 1 ? "" : "s")")
                ForEach(cluster.memos.prefix(3), id: \.id) { JournalMemoRow(memo: $0) }
            }
        }
        .padding(12)
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
    }
}

struct PlaceCluster: Identifiable {
    let id: String
    let name: String
    let coordinate: CLLocationCoordinate2D
    let memos: [Memo]

    /// Group by place name (fallback: coordinates rounded to ~1 km) and average
    /// each group's coordinates for the pin.
    static func build(from memos: [Memo]) -> [PlaceCluster] {
        let located = memos.compactMap { memo -> (Memo, LocationInfo)? in
            guard let loc = memo.metadata?.location else { return nil }
            return (memo, loc)
        }
        let groups = Dictionary(grouping: located) { pair in
            pair.1.placeName
                ?? String(format: "%.2f,%.2f", pair.1.latitude, pair.1.longitude)
        }
        return groups.map { key, pairs in
            let lat = pairs.map { $0.1.latitude }.reduce(0, +) / Double(pairs.count)
            let lon = pairs.map { $0.1.longitude }.reduce(0, +) / Double(pairs.count)
            let sorted = pairs.map { $0.0 }
                .sorted { LookbackProvider.journalDate($0) > LookbackProvider.journalDate($1) }
            return PlaceCluster(id: key, name: key,
                                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                                memos: sorted)
        }
        .sorted { $0.memos.count > $1.memos.count }
    }
}

/// Non-interactive mini map for the Journal home's Places card.
struct JournalMapPreview: View {
    let memos: [Memo]
    var body: some View {
        let clusters = PlaceCluster.build(from: memos)
        Map(interactionModes: []) {
            ForEach(clusters) { cluster in
                Annotation(cluster.name, coordinate: cluster.coordinate) {
                    Text("\(cluster.memos.count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Circle().fill(Color.skAccent))
                }
            }
        }
        .mapStyle(.standard)
    }
}
