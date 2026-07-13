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
                let mergedCount = host.id.split(separator: "+").count
                out[i] = PlaceCluster(
                    id: host.id + "+" + cluster.id,
                    name: "\(host.name.split(separator: " +").first.map(String.init) ?? host.name) +\(mergedCount)",
                    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                    memos: (host.memos + cluster.memos)
                        .sorted { LookbackProvider.journalDate($0) > LookbackProvider.journalDate($1) })
            } else {
                out.append(cluster)
            }
        }
        return out
    }
}

