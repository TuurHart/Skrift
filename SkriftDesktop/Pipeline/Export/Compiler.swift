import Foundation

/// Phone-sent metadata, decoded from `PipelineFile.audioMetadataJSON` (the phone's
/// MemoMetadata shape) for the export frontmatter. All optional / lenient.
struct PhoneMetadata: Codable, Sendable {
    struct Location: Codable, Sendable { var placeName: String? }
    struct Weather: Codable, Sendable { var conditions: String?; var temperature: Double?; var temperatureUnit: String? }
    struct Pressure: Codable, Sendable { var hPa: Double?; var trend: String? }
    struct Daylight: Codable, Sendable { var sunrise: String?; var sunset: String?; var hoursOfLight: Double? }
    var location: Location?
    var weather: Weather?
    var pressure: Pressure?
    var dayPeriod: String?
    var daylight: Daylight?
    var steps: Int?
    var recordedAt: String?
}

/// Assembles Obsidian-ready markdown (YAML frontmatter + body) from a PipelineFile.
/// Pure (no IO) → host-testable. Ported from `enhancement.py:compile_file`. Body
/// precedence: sanitised → enhanced copy-edit → transcript (the name-linked text
/// wins, since it's what exports). The vault write/copy is the Export step (Phase 8).
enum Compiler {
    static func compile(file pf: PipelineFile, author: String, date overrideDate: String? = nil) -> String {
        let meta = pf.audioMetadataJSON.flatMap { try? JSONDecoder().decode(PhoneMetadata.self, from: $0) }
        let body = firstNonEmpty(pf.sanitised, pf.enhancedCopyedit, pf.transcript) ?? ""
        let summary = (pf.enhancedSummary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let rawStem = (pf.filename as NSString).deletingPathExtension
        let title = firstNonEmpty(pf.enhancedTitle, rawStem) ?? rawStem
        let date = overrideDate ?? meta?.recordedAt.map { String($0.prefix(10)) } ?? ""

        let source: String
        switch pf.sourceType {
        case .note: source = "Apple-Note"
        case .capture: source = "Capture"
        case .audio: source = "Voice-memo"
        }

        var y: [String] = [
            "---",
            "title: \(title)",
            "date: \(date)",
            "lastTouched:",
            "author: \(author)",
            "source: \(source)",
        ]
        if let place = meta?.location?.placeName, !place.isEmpty {
            y.append("location: \"\(place)\"")
        } else {
            y.append("location:")
        }
        if let w = meta?.weather, let c = w.conditions, let t = w.temperature {
            y.append("weather: \"\(c), \(fmtNum(t))\(w.temperatureUnit ?? "°C")\"")
        }
        if let hPa = meta?.pressure?.hPa { y.append("pressure: \(fmtNum(hPa))") }
        if let trend = meta?.pressure?.trend, !trend.isEmpty { y.append("pressureTrend: \(trend)") }
        if let dp = meta?.dayPeriod, !dp.isEmpty { y.append("dayPeriod: \(dp)") }
        if let d = meta?.daylight, let sr = d.sunrise, let ss = d.sunset {
            y.append("daylight:")
            y.append("  sunrise: \"\(sr)\"")
            y.append("  sunset: \"\(ss)\"")
            if let h = d.hoursOfLight { y.append("  hoursOfLight: \(fmtNum(h))") }
        }
        if let steps = meta?.steps { y.append("steps: \(steps)") }

        y.append("tags:")
        for t in pf.tags { y.append("  - \(t)") }
        y.append(pf.significance != nil ? "significance: \(String(format: "%.1f", pf.significance!))" : "significance:")
        y.append(summary.isEmpty ? "summary:" : "summary: \(summary)")
        y.append("---")
        y.append("")

        return y.joined(separator: "\n") + "\n" + body
    }

    private static func firstNonEmpty(_ vals: String?...) -> String? {
        for v in vals {
            if let v, !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return v }
        }
        return nil
    }

    /// Whole numbers print without a trailing `.0` (e.g. 21, 1013), fractions keep it.
    private static func fmtNum(_ d: Double) -> String {
        d == d.rounded() ? String(Int(d)) : String(d)
    }
}
