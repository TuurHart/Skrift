import Foundation

/// Parses a shared Apple/Google Maps link into a place (D6): name + coordinates.
/// Pure string work — no MapKit, no network (E4: enrichment happens in the app;
/// short `maps.app.goo.gl` links are opaque without a fetch and stay plain link
/// cards). The drainer turns a hit into the memo's location metadata — the same
/// chip + place-search a recorded memo gets.
enum PlaceLink {
    struct Place: Equatable {
        var name: String?
        var latitude: Double
        var longitude: Double
    }

    static func parse(_ raw: String) -> Place? {
        guard let url = URL(string: raw), let host = url.host?.lowercased() else { return nil }
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        func q(_ name: String) -> String? {
            comps?.queryItems?.first { $0.name == name }?.value
        }

        // Apple Maps: ?ll=38.7,-9.1&q=Name  |  /place?coordinate=38.7,-9.1&name=Name
        if host == "maps.apple.com" || host.hasSuffix(".maps.apple.com") {
            guard let pair = (q("ll") ?? q("coordinate")).flatMap(parseLatLon) else { return nil }
            let name = firstNonGeneric(q("q"), q("name"), q("address"))
            return Place(name: name, latitude: pair.0, longitude: pair.1)
        }

        // Google Maps: /maps/place/<Name>/@38.7,-9.1,17z  |  maps.google.com/?q=38.7,-9.1
        let isGoogleMaps = host.hasPrefix("maps.google.") ||
            (host.contains("google.") && url.path.hasPrefix("/maps"))
        if isGoogleMaps {
            var name: String?
            if let r = url.path.range(of: "/place/") {
                let segment = url.path[r.upperBound...].split(separator: "/").first.map(String.init) ?? ""
                let decoded = segment.replacingOccurrences(of: "+", with: " ")
                name = firstNonGeneric(decoded.removingPercentEncoding ?? decoded)
            }
            // @lat,lng rides the PATH, not the query.
            if let at = raw.firstIndex(of: "@") {
                let nums = raw[raw.index(after: at)...].split(separator: ",").prefix(2).map(String.init)
                if nums.count == 2, let pair = parseLatLon("\(nums[0]),\(nums[1])") {
                    return Place(name: name, latitude: pair.0, longitude: pair.1)
                }
            }
            if let pair = q("q").flatMap(parseLatLon) {
                return Place(name: name, latitude: pair.0, longitude: pair.1)
            }
            return nil
        }
        return nil
    }

    /// "38.72,-9.13" → coordinates, range-checked. nil for anything non-numeric.
    private static func parseLatLon(_ s: String) -> (Double, Double)? {
        let parts = s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let la = Double(parts[0]), let lo = Double(parts[1]),
              abs(la) <= 90, abs(lo) <= 180 else { return nil }
        return (la, lo)
    }

    /// First candidate that reads as a NAME — a bare "38.72,-9.13" q param isn't one.
    private static func firstNonGeneric(_ candidates: String?...) -> String? {
        for c in candidates {
            guard let t = c?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { continue }
            if parseLatLon(t) == nil { return t }
        }
        return nil
    }
}
