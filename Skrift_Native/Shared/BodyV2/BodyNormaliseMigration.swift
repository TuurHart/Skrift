import Foundation

/// The one-time body normalisation (C10, D4, R25). A body stored before body v2 can hold a
/// picture marker inside a sentence (v1 wrote `sat\n\n[[img_001]]\n\n down.` at the photo's
/// moment; a v1 edit or copy-edit can leave one inline). At a note's first open on a device it
/// is rewritten ONCE so every picture is its own paragraph, and any stored name offsets are
/// re-derived over the new text.
///
/// Data safety:
/// - Only markers move. Machine text (unedited speech) also gets v2's C19 whitespace via
///   `BodyV2.committed`; a user-edited or typed body gets the marker move only.
/// - A rewrite is refused unless the words in == words out and the markers in == markers out.
/// - The pre-migration body is kept in a LOCAL ledger file per note (never synced), which is
///   also the once-flag. `undo` puts the original back if the body is still the migrated one.
/// - The C203 legacy shapes (old test image-captures, pre-build-76 PDF captures) are left
///   alone (D4).
enum BodyNormaliseMigration {

    // MARK: - detection

    /// True when some picture marker is not its own paragraph in v2's shape: at the top or
    /// after a blank line, markers `\n\n`-separated, then a blank line straight into the next
    /// paragraph (v1's wrap leaves a space there) or the end. `manifestCount` = how many
    /// markers resolve (a marker past it is the author's text, not a picture).
    static func needsNormalise(_ body: String, manifestCount: Int = .max) -> Bool {
        guard body.contains("[[img_") else { return false }
        let ns = body as NSString
        for run in BodyV2Marker.runs(in: body, manifestCount: manifestCount) {
            let r = ns.substring(with: run.range) as NSString
            let first = r.range(of: "[[").location
            let lastEnd = r.range(of: "]]", options: .backwards).location + 2
            let core = r.substring(with: NSRange(location: first, length: lastEnd - first))
            guard core == BodyV2Marker.block(run.numbers) else { return true }
            let end = run.range.location + run.range.length
            let atTop = ns.substring(to: run.range.location + first)
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            guard atTop || run.newlinesBefore >= 2 else { return true }
            if end == ns.length { continue }
            guard run.newlinesAfter >= 2, r.hasSuffix("\n") else { return true }
            if ",;:.!?)".contains(Character(UnicodeScalar(ns.character(at: end)) ?? " ")) { return true }
        }
        return false
    }

    // MARK: - C203: the shapes D4 leaves alone

    /// Pre-round-3 image captures (no migration by decree, 18da97ad, 2026-07-10 17:11 +0100).
    static let imageCaptureCutoff = Date(timeIntervalSince1970: 1_783_699_881)
    /// Build 76 (b41ec828, 2026-07-15 16:54 +0100): PDF captures before it stay text-only.
    static let pdfCaptureCutoff = Date(timeIntervalSince1970: 1_784_130_860)

    /// True for a C203 legacy capture: an image capture made before round 3, or a PDF capture
    /// made before build 76. `sharedContent` is the C3 capture object (`type`, `mimeType`,
    /// `fileName`); an unknown date counts as old.
    static func isC203Legacy(sharedContent: [String: Any]?, madeAt: Date?) -> Bool {
        guard let sc = sharedContent, let type = sc["type"] as? String else { return false }
        let at = madeAt ?? .distantPast
        if type == "image" { return at < imageCaptureCutoff }
        if type == "file" {
            let mime = (sc["mimeType"] as? String ?? "").lowercased()
            let name = (sc["fileName"] as? String ?? sc["filePath"] as? String ?? "").lowercased()
            return (mime.contains("pdf") || name.hasSuffix(".pdf")) && at < pdfCaptureCutoff
        }
        return false
    }

    static func isC203Legacy(sharedContentData: Data?, madeAt: Date?) -> Bool {
        let sc = sharedContentData.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        return isC203Legacy(sharedContent: sc, madeAt: madeAt)
    }

    // MARK: - the rewrite (pure)

    /// The v2 body for a legacy one, or nil = leave it (already v2, or the rewrite would not
    /// preserve every word and marker). `machineText` = unedited speech: it gets v2's full
    /// commit; anything else gets only its markers moved to their sentence ends.
    static func rewrite(_ body: String, manifestCount: Int, machineText: Bool) -> String? {
        guard manifestCount > 0, needsNormalise(body, manifestCount: manifestCount) else { return nil }
        let out: String
        if machineText {
            let manifest = (0..<manifestCount).map { _ in ImageManifestEntry(filename: "", offsetSeconds: 0) }
            out = BodyV2.committed(.init(text: body, manifest: manifest, source: .typed))
        } else {
            out = markersMoved(body, manifestCount: manifestCount)
        }
        guard out != body, preserves(body, out),
              !needsNormalise(out, manifestCount: manifestCount) else { return nil }
        return out
    }

    /// Moves each resolving marker run to the end of its sentence / list item / quote block as
    /// its own paragraph; the prose is left as typed except the break the marker sat in.
    static func markersMoved(_ body: String, manifestCount: Int) -> String {
        let text = body.replacingOccurrences(of: "\r\n", with: "\n")
        let runs = BodyV2Marker.runs(in: text, manifestCount: manifestCount)
        let (bare, lifted) = BodyV2.lift(text, runs: runs)
        let ns = bare as NSString
        let spots: [(at: Int?, n: Int)] = lifted.map { item in
            (item.at.map { BodyV2.spot(after: max($0 - 1, 0), in: ns) }, item.n)
        }
        let built = BodyV2.build(ns, spots: spots, breaks: [])
        return built.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Words in == words out (markers read as a space) and markers in == markers out.
    static func preserves(_ old: String, _ new: String) -> Bool {
        words(old) == words(new)
            && BodyV2Marker.numbers(in: old).sorted() == BodyV2Marker.numbers(in: new).sorted()
    }

    static func words(_ s: String) -> [Substring] {
        let ns = s as NSString
        let spaced = BodyV2Marker.regex.stringByReplacingMatches(
            in: s, range: NSRange(location: 0, length: ns.length), withTemplate: " ")
        return spaced.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
    }

    // MARK: - name offsets (R25)

    /// UTF-16 location map old → new over the text both share: every unit that is neither
    /// whitespace nor inside a marker keeps its order (`preserves` guarantees the sequence is
    /// identical), so its new location is exact. nil for a unit that has no counterpart.
    static func offsetMap(from old: String, to new: String) -> [Int: Int] {
        let a = contentUnits(old), b = contentUnits(new)
        guard a.count == b.count else { return [:] }
        var map: [Int: Int] = [:]
        for (i, loc) in a.enumerated() where a[i].unit == b[i].unit { map[loc.loc] = b[i].loc }
        return map
    }

    private static func contentUnits(_ s: String) -> [(loc: Int, unit: unichar)] {
        let ns = s as NSString
        var inMarker = IndexSet()
        for m in BodyV2Marker.regex.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            inMarker.insert(integersIn: m.range.location..<(m.range.location + m.range.length))
        }
        var out: [(Int, unichar)] = []
        for i in 0..<ns.length where !inMarker.contains(i) {
            let c = ns.character(at: i)
            if c == 32 || c == 9 || c == 10 || c == 13 || c == 0xA0 { continue }
            out.append((i, c))
        }
        return out
    }

    /// A stored range (UTF-16) in `old`, re-derived in `new`; nil when it has no counterpart.
    static func remap(_ range: NSRange, from old: String, to new: String) -> NSRange? {
        remap(range, map: offsetMap(from: old, to: new))
    }

    static func remap(_ range: NSRange, map: [Int: Int]) -> NSRange? {
        guard range.length > 0, let s = map[range.location],
              let e = map[range.location + range.length - 1] else { return nil }
        return NSRange(location: s, length: e - s + 1)
    }

    /// Re-derives each stored name occurrence's offset over the rewritten body; an occurrence
    /// whose span no longer maps is dropped (the renderer drops stale ones the same way).
    static func remap(_ occurrences: [AmbiguousOccurrence], from old: String, to new: String) -> [AmbiguousOccurrence] {
        let map = offsetMap(from: old, to: new)
        return occurrences.compactMap { occ in
            guard let r = remap(NSRange(location: occ.offset, length: occ.length), map: map) else { return nil }
            var o = occ
            o.offset = r.location
            o.length = r.length
            return o
        }
    }

    // MARK: - the local once-flag + recoverable originals

    enum Outcome: String, Codable {
        /// At least one body was rewritten; originals kept in the record.
        case rewritten
        /// Nothing to do (already v2, or no pictures).
        case clean
        /// A C203 legacy shape, left alone by decree.
        case legacyShape
        /// A rewrite was computed but would have changed words or markers, so it was not written.
        case refused
        /// `undo` restored the originals; the note is not migrated again.
        case undone
    }

    struct Record: Codable, Equatable {
        struct Field: Codable, Equatable {
            var original: String
            var migrated: String
        }
        var version: Int = BodyNormaliseMigration.version
        var outcome: Outcome
        var at: Date
        /// Body field name → its original and migrated text. Only rewritten fields appear.
        var fields: [String: Field] = [:]
        /// Field names whose rewrite was refused by the preservation check.
        var refused: [String] = []
    }

    static let version = 1

    /// One JSON file per note in a LOCAL directory (never in the synced store). The file's
    /// existence is the once-flag; its `fields` hold the pre-migration bodies for `undo`.
    struct Ledger {
        let directory: URL

        static var standard: Ledger {
            #if os(macOS)
            Ledger(directory: AppPaths.appSupportDirectory.appendingPathComponent("BodyNormalise", isDirectory: true))
            #else
            Ledger(directory: URL.applicationSupportDirectory.appendingPathComponent("BodyNormalise", isDirectory: true))
            #endif
        }

        func url(_ id: String) -> URL { directory.appendingPathComponent("\(id).json") }

        func record(for id: String) -> Record? {
            guard let data = try? Data(contentsOf: url(id)) else { return nil }
            let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
            return try? d.decode(Record.self, from: data)
        }

        /// A record exists whenever the file does, even an unreadable one: a damaged ledger
        /// must never make a note migrate twice.
        func hasRun(_ id: String) -> Bool { FileManager.default.fileExists(atPath: url(id).path) }

        func save(_ record: Record, for id: String) throws {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted, .sortedKeys]
            try e.encode(record).write(to: url(id), options: .atomic)
        }
    }

    /// One stored body of a note, read and written through closures so both apps' models fit.
    struct Body {
        let name: String
        let get: () -> String?
        let set: (String) -> Void
    }

    /// Runs the migration once for note `id`. A second call is a no-op (returns nil). The
    /// ledger is written BEFORE any body changes, so a crash mid-run keeps the originals.
    /// `didRewrite(name, old, new)` runs after each body is set (for offset re-derivation).
    @discardableResult
    static func run(id: String, bodies: [Body], manifestCount: Int, machineText: Bool,
                    legacyShape: Bool, ledger: Ledger = .standard, now: Date = Date(),
                    didRewrite: (String, String, String) -> Void = { _, _, _ in }) -> Outcome? {
        guard !ledger.hasRun(id) else { return nil }
        if legacyShape {
            try? ledger.save(Record(outcome: .legacyShape, at: now), for: id)
            return .legacyShape
        }
        var record = Record(outcome: .clean, at: now)
        var plan: [(Body, String, String)] = []
        for body in bodies {
            guard let old = body.get(), needsNormalise(old, manifestCount: manifestCount) else { continue }
            if let new = rewrite(old, manifestCount: manifestCount, machineText: machineText) {
                record.fields[body.name] = .init(original: old, migrated: new)
                plan.append((body, old, new))
            } else {
                record.refused.append(body.name)
            }
        }
        record.outcome = !plan.isEmpty ? .rewritten : record.refused.isEmpty ? .clean : .refused
        do { try ledger.save(record, for: id) } catch { return nil }   // no flag → no write
        for (body, old, new) in plan {
            body.set(new)
            didRewrite(body.name, old, new)
        }
        return record.outcome
    }

    /// Puts back every original whose body is still exactly the migrated text (a later edit
    /// wins and is left alone) and marks the note `undone`, so it is never migrated again.
    /// Returns the names of the bodies restored.
    @discardableResult
    static func undo(id: String, bodies: [Body], ledger: Ledger = .standard, now: Date = Date(),
                     didRestore: (String, String, String) -> Void = { _, _, _ in }) -> [String] {
        guard var record = ledger.record(for: id), record.outcome == .rewritten else { return [] }
        var restored: [String] = []
        for body in bodies {
            guard let f = record.fields[body.name], body.get() == f.migrated else { continue }
            body.set(f.original)
            didRestore(body.name, f.migrated, f.original)
            restored.append(body.name)
        }
        record.outcome = .undone
        record.at = now
        try? ledger.save(record, for: id)
        return restored
    }
}
