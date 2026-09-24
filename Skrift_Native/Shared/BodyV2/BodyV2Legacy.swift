import Foundation

/// Q13 READ-ONLY FALLBACK. Q14 KEPT it: `BodyNormaliseMigration` rewrites an old body at the
/// note's first open (onAppear, after the first render), but the vault exporter, the phone
/// publisher and the snapshot tool read bodies of notes never opened on this device, a v1 body
/// can arrive over CloudKit while its note is on screen, and a refused rewrite stays v1 — all
/// of those still need the snap. Every write site stores body v2 now, but a body stored
/// before the swap (v1 wrote `sat\n\n[[img_001]]\n\n down.` at the photo's moment; a v1 edit
/// or a copy-edit can leave a marker inline) would render with the photo mid-sentence
/// without the old snap. Such a body is still shown and exported through v1's snap, exactly
/// as before; a v2-shaped body passes through untouched, so its only offset remap is
/// marker → one glyph (C17). Nothing here writes.
enum BodyV2Legacy {

    /// True when some picture marker is not its own paragraph in v2's shape: at the top or
    /// after a blank line, markers `\n\n`-separated, then a blank line straight into the next
    /// paragraph (v1's wrap leaves a space there) or the end.
    static func isUnnormalised(_ body: String) -> Bool {
        BodyNormaliseMigration.needsNormalise(body)
    }

    /// The text to show / export for a stored body, and the map from a stored (raw) range
    /// to a range in that text. Identity for a v2-shaped body.
    static func shown(_ body: String) -> (text: String, map: (NSRange) -> NSRange) {
        guard isUnnormalised(body) else { return (body, { $0 }) }
        let snap = BodyTransform.snapImages(body)
        return (snap.text, { snap.snapped(rawRange: $0) })
    }
}
