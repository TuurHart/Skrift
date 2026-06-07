import SwiftUI

extension PipelineFile {
    /// Audio duration in seconds, from the phone metadata blob (0 if none).
    var durationSeconds: Double {
        guard let data = audioMetadataJSON,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let d = obj["duration"] as? String else { return 0 }
        return SkriftFormat.seconds(fromHMS: d)
    }

    /// Body text precedence — matches the web `getBestText`: the name-linked
    /// `sanitised` (what exports), then the copy-edit, then the raw transcript.
    var bestBodyText: String { sanitised ?? enhancedCopyedit ?? transcript ?? "" }
}

extension SkriftFormat {
    /// "HH:MM:SS" / "MM:SS" → seconds.
    static func seconds(fromHMS s: String) -> Double {
        let p = s.split(separator: ":").map { Double($0) ?? 0 }
        switch p.count {
        case 3: return p[0] * 3600 + p[1] * 60 + p[2]
        case 2: return p[0] * 60 + p[1]
        case 1: return p[0]
        default: return 0
        }
    }

    /// seconds → "m:ss" clock for the transport.
    static func clock(_ s: Double) -> String {
        let t = Int(max(0, s.isFinite ? s : 0))
        return String(format: "%d:%02d", t / 60, t % 60)
    }

    private static let breadcrumbDF: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, d MMM yyyy"
        f.locale = Locale(identifier: "en_GB")
        return f
    }()

    static func breadcrumbDate(_ d: Date) -> String { breadcrumbDF.string(from: d) }
}
