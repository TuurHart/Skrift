import Foundation
import CoreLocation
import MapKit

/// Place clustering for the Journal map surfaces — SHARED: the phone's map screen
/// and the Mac's map mode group the same synced memos identically (name-grouped,
/// zoom-adaptive merging). Pure over [Memo]; MapKit types only for span math.
struct PlaceCluster: Identifiable {
    let id: String
    let name: String
    let coordinate: CLLocationCoordinate2D
    let memos: [Memo]
    /// The ids of every base cluster merged into this pin (just `[id]` for an unmerged one).
    /// Membership is asked of THIS, never recovered by splitting `id` on "+" (a place called
    /// "C+ Cafe" broke that).
    let memberIDs: [String]
    /// How many base clusters this pin holds (1 = not merged).
    let mergedCount: Int
    /// The name without the "+N" suffix.
    let baseName: String

    init(id: String, name: String, coordinate: CLLocationCoordinate2D, memos: [Memo],
         memberIDs: [String]? = nil, mergedCount: Int = 1, baseName: String? = nil) {
        self.id = id
        self.name = name
        self.coordinate = coordinate
        self.memos = memos
        self.memberIDs = memberIDs ?? [id]
        self.mergedCount = mergedCount
        self.baseName = baseName ?? name
    }

    /// Whether the base cluster `id` is this pin or one of the pins merged into it.
    func contains(memberID: String) -> Bool { memberIDs.contains(memberID) }

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

    /// The region that shows EVERY cluster: padded bounding box around the pins,
    /// with a minimum span so a single place doesn't render street-level. Nil when
    /// nothing is located. Drives the rail mini-map shot AND the full map's
    /// fit-all entry (mock review-minimap.html #m1). Pure; unit-tested.
    static func fitRegion(for clusters: [PlaceCluster],
                          minSpan: Double = 0.05, padding: Double = 1.35) -> MKCoordinateRegion? {
        let lats = clusters.map(\.coordinate.latitude)
        let lons = clusters.map(\.coordinate.longitude)
        guard let latMin = lats.min(), let latMax = lats.max(),
              let lonMin = lons.min(), let lonMax = lons.max() else { return nil }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (latMin + latMax) / 2,
                                           longitude: (lonMin + lonMax) / 2),
            span: MKCoordinateSpan(latitudeDelta: max((latMax - latMin) * padding, minSpan),
                                   longitudeDelta: max((lonMax - lonMin) * padding, minSpan)))
    }

    /// Photos-style zoom clustering: base (name-grouped) clusters closer than
    /// ~12% of the visible span COLLECT into one pin — biggest first, weighted
    /// centroid, "Name +N" title. Zooming in shrinks the span → they pull
    /// apart. Pure; unit-tested.
    static func merged(_ base: [PlaceCluster], span: MKCoordinateSpan) -> [PlaceCluster] {
        let latLimit = span.latitudeDelta * 0.12
        let lonLimit = span.longitudeDelta * 0.12
        var out: [PlaceCluster] = []
        for cluster in base.sorted(by: { $0.memos.count > $1.memos.count }) {
            if let i = out.firstIndex(where: {
                abs($0.coordinate.latitude - cluster.coordinate.latitude) < latLimit &&
                abs($0.coordinate.longitude - cluster.coordinate.longitude) < lonLimit
            }) {
                let host = out[i]
                let total = Double(host.memos.count + cluster.memos.count)
                let lat = (host.coordinate.latitude * Double(host.memos.count)
                    + cluster.coordinate.latitude * Double(cluster.memos.count)) / total
                let lon = (host.coordinate.longitude * Double(host.memos.count)
                    + cluster.coordinate.longitude * Double(cluster.memos.count)) / total
                let count = host.mergedCount + cluster.mergedCount
                out[i] = PlaceCluster(
                    id: host.id + "+" + cluster.id,
                    name: "\(host.baseName) +\(count - 1)",
                    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                    memos: (host.memos + cluster.memos)
                        .sorted { LookbackProvider.journalDate($0) > LookbackProvider.journalDate($1) },
                    memberIDs: host.memberIDs + cluster.memberIDs,
                    mergedCount: count,
                    baseName: host.baseName)
            } else {
                out.append(cluster)
            }
        }
        return out
    }
}

