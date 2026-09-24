import Foundation

/// C170: which picture stands for a note in a list. Returns a 1-based manifest number.
enum BodyV2Thumbnail {
    /// - `resolves(n)`: manifest picture n has a file to show.
    /// - First marker in BODY order that resolves; markers present but none resolve, or a
    ///   typed body → none; a share capture with no marker at all → its first manifest photo.
    ///   A speech note whose markers were all deleted → none (the manifest keeps them, C14).
    static func pick(body: String, manifestCount: Int, source: BodyV2.Source,
                     resolves: (Int) -> Bool) -> Int? {
        guard source != .typed, manifestCount > 0 else { return nil }
        let markers = BodyV2Marker.numbers(in: body).filter { $0 >= 1 && $0 <= manifestCount }
        if markers.isEmpty { return source == .shareCapture ? 1 : nil }
        return markers.first(where: resolves)
    }
}
