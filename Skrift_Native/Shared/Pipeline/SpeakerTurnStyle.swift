import Foundation

/// How a `**Name:**` conversation is DRAWN — one rule, both apps.
///
/// The two renderers are deliberately different shapes: the Mac seats each speaker in a
/// right-aligned gutter beside their words (signed mock `mocks/conversation-turns-D-hifi.html`,
/// variant E1), the phone keeps its turn cards on a much narrower measure. What they must
/// never disagree on is WHICH SPEAKER GETS WHICH COLOUR — so the slot rule lives here and
/// both renderers ask for it (the phone's old copy was a private 4-colour table keyed on the
/// header text, i.e. a twin that had already drifted).
///
/// SLOT = first-appearance order of a speaker's resolved IDENTITY, not of their header text.
/// Two headers are the same speaker when they resolve to the same roster person, so the
/// conversation naming rule — first mention `**[[Tiuri Hartog]]:**`, every later one the short
/// `**Tiuri:**` — does not split one voice across two colours (which is exactly what a
/// name-keyed map does). Renaming "Speaker 2" → "Bulldops" keeps that speaker's position too,
/// so no colour reshuffles: the invariant `Palette.speakerHues` is written against.
enum SpeakerTurnStyle {

    /// Resolves a turn header's label to a live person. THE rule — `Sanitiser`'s conversation
    /// pass resolves through this same type, so a renderer can never disagree with the linker
    /// about who is speaking. Precomputes the alias map; build one per pass, not per turn.
    struct HeaderResolver {
        private let live: [Person]
        private let aliases: [String: [Person]]
        private let ambiguous: Set<String>

        init(people: [Person]) {
            live = people
            var map: [String: [Person]] = [:]
            for p in people {
                for a in p.aliases {
                    let al = a.trimmingCharacters(in: .whitespaces).lowercased()
                    if !al.isEmpty { map[al, default: []].append(p) }
                }
            }
            aliases = map
            ambiguous = Set(map.filter { $0.value.count >= 2 }.keys)
        }

        /// The unique live person a header label names — by canonical key (the phone sends a
        /// matched speaker's full canonical, e.g. "Tiuri Hartog") or by an unambiguous alias.
        /// nil = "Speaker N" / unknown / ambiguous → the header stays plain.
        /// `name` is a PARSED label (`SpeakerTranscript.parse` form: `[[ ]]` already stripped).
        func person(for name: String) -> Person? {
            let key = name.trimmingCharacters(in: .whitespaces).lowercased()
            guard !key.isEmpty else { return nil }
            if let p = live.first(where: {
                NamesMerge.keyName($0.canonical).trimmingCharacters(in: .whitespaces).lowercased() == key
            }) { return p }
            if !ambiguous.contains(key), let cands = aliases[key], cands.count == 1 { return cands[0] }
            return nil
        }

        /// The key two headers share iff they are the same speaker — a resolved person's
        /// canonical, else the raw label. Unknown speakers stay distinct from each other.
        func identity(for name: String) -> String {
            person(for: name).map { NamesMerge.keyName($0.canonical).lowercased() }
                ?? "raw:" + name.lowercased()
        }
    }

    /// A styled turn: where its header sits, what the gutter shows, whose colour it wears.
    struct Turn: Equatable {
        /// The whole `**Name:**` literal INCLUDING its trailing spaces — what a renderer
        /// stands the gutter in for. The model keeps the markdown verbatim either way.
        let headerRange: NSRange
        /// The turn's words: header end → the next header (or the end of the text).
        let bodyRange: NSRange
        /// The label to SHOW — brackets dropped, an Obsidian `Canonical|spoken` header
        /// showing its spoken part, no trailing colon.
        let display: String
        /// The header was a `[[link]]` — this speaker's first turn (drawn a touch heavier).
        let isLinked: Bool
        /// Index for `Palette.speakerHue(slot:)`.
        let slot: Int
    }

    /// The styled turns of a conversation body, or `[]` when the text isn't one.
    ///
    /// "Is a conversation" is the pipeline's own definition (`SpeakerTranscript.isAttributed`):
    /// ≥2 line-anchored `**Name:**` headers AND ≥2 distinct speakers. Deliberately the same
    /// test the Sanitiser routes on — a body the linker already treated as a conversation is
    /// the body that should render as one, and a single bold lead-in never sprouts a gutter.
    /// Fixed pattern — hoisted so `turns(in:)` (called on EVERY keystroke via
    /// `BodyTextView.restyle`, R90) doesn't recompile it each time (sweep E finding #5).
    private static let headerRegex = try! NSRegularExpression(pattern: SpeakerTranscript.headerPattern)

    static func turns(in text: String, people: [Person]) -> [Turn] {
        let re = headerRegex
        let ns = text as NSString
        let matches = re.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard matches.count >= 2 else { return [] }
        let resolver = HeaderResolver(people: people)
        var slots: [String: Int] = [:]
        var out: [Turn] = []
        for (i, m) in matches.enumerated() {
            let raw = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
            let parsed = raw.replacingOccurrences(of: "[[", with: "").replacingOccurrences(of: "]]", with: "")
            let id = resolver.identity(for: parsed)
            let slot: Int
            if let known = slots[id] { slot = known } else { slot = slots.count; slots[id] = slot }
            let start = NSMaxRange(m.range)
            let end = (i + 1 < matches.count) ? matches[i + 1].range.location : ns.length
            out.append(Turn(headerRange: m.range,
                            bodyRange: NSRange(location: start, length: max(0, end - start)),
                            display: label(for: parsed),
                            isLinked: raw.contains("[["),
                            slot: slot))
        }
        return slots.count >= 2 ? out : []
    }

    /// Hue slots for already-parsed turn names (`SpeakerTranscript.parse` order) — the phone's
    /// entry point, where the turns are model objects rather than ranges in a string. Same rule
    /// as `turns(in:people:)`, so both apps colour a given speaker identically.
    static func slots(forParsedNames names: [String], people: [Person]) -> [Int] {
        let resolver = HeaderResolver(people: people)
        var slots: [String: Int] = [:]
        return names.map { name in
            let id = resolver.identity(for: name)
            if let known = slots[id] { return known }
            let n = slots.count
            slots[id] = n
            return n
        }
    }

    /// The gutter label for a parsed header name: an Obsidian alias-display header
    /// (`Canonical|spoken`) shows the SPOKEN part, everything else shows itself.
    static func label(for parsedName: String) -> String {
        let n = parsedName.trimmingCharacters(in: .whitespaces)
        guard let bar = n.lastIndex(of: "|") else { return n }
        let spoken = n[n.index(after: bar)...].trimmingCharacters(in: .whitespaces)
        return spoken.isEmpty ? String(n[..<bar]).trimmingCharacters(in: .whitespaces) : spoken
    }
}
