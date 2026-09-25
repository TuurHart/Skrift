import Foundation

extension Sanitiser {
    // MARK: - Conversation-aware name-linking (speaker-attributed transcripts)

    /// Name-linking for a `**Name:**`-turn conversation — distinct from `process`
    /// (monologue) because turn HEADERS and INLINE speech want different treatment:
    ///
    /// - **Same-speaker merge** (#3): consecutive turns by the same resolved speaker are
    ///   merged into one, repairing diarization fragmentation.
    /// - **Headers** (#2): a speaker's FIRST turn header becomes a full `[[Canonical]]`
    ///   link; later headers become the plain short name (`**Tuur:**`). Unmatched
    ///   ("Speaker N") / unknown / ambiguous headers stay plain.
    /// - **Inline mentions** (#1): FIRST-ONLY per person ("one note, one link"). A person's
    ///   first not-yet-linked mention becomes the Obsidian alias-display `[[Canonical|short]]`
    ///   (or bare `[[Canonical]]` when the short equals the canonical); every later mention —
    ///   and every mention of a speaker already linked in their header — demotes to the plain
    ///   short name. Ambiguous aliases stay plain and are recorded for the resolver.
    ///
    /// OPT-OUT (decision 4): matched SPEAKERS auto-link in their header (a speaker is
    /// definitionally a subject) and every known person's first inline mention auto-links
    /// too — risk-tiered, so only a SAFE alias commits; FP-prone / ambiguous ones stay
    /// plain and are recorded as suggestions. Falls back to `process` (monologue) when the
    /// text isn't actually attributed.
    static func processConversation(text inputText: String, people: [Person],
                                    neverLink: Set<String> = [], namePicks: [String: String] = [:]) -> Result {
        guard let parsedWP = SpeakerTranscript.parseWithPreamble(inputText) else {
            return process(text: inputText, people: people, neverLink: neverLink, namePicks: namePicks)
        }
        let parsed = parsedWP.turns
        let preamble = parsedWP.preamble
        let ov = Overrides(people: people, neverLink: neverLink, namePicks: namePicks)
        let live = ov.live

        // Header resolution over ALL live people — a matched speaker is a subject, resolved
        // regardless of prune/silence (those overrides shape INLINE + suggestions). The rule
        // itself lives in `SpeakerTurnStyle.HeaderResolver`, SHARED with the two turn
        // renderers: who is speaking must be one answer, or the gutter colours a speaker the
        // linker split (or vice versa).
        let resolver = SpeakerTurnStyle.HeaderResolver(people: live)
        func resolveHeader(_ rawName: String) -> Person? { resolver.person(for: rawName) }
        func identity(person: Person?, rawName: String) -> String {
            person.map { NamesMerge.keyName($0.canonical).lowercased() } ?? "raw:" + rawName.lowercased()
        }

        // Merge consecutive turns by the same resolved speaker (#3).
        struct MTurn { let person: Person?; let rawName: String; var text: String }
        var merged: [MTurn] = []
        for turn in parsed {
            let person = resolveHeader(turn.name)
            let id = identity(person: person, rawName: turn.name)
            if let last = merged.last, identity(person: last.person, rawName: last.rawName) == id {
                let sep = (merged[merged.count - 1].text.isEmpty || turn.text.isEmpty) ? "" : " "
                merged[merged.count - 1].text += sep + turn.text
            } else {
                merged.append(MTurn(person: person, rawName: turn.name, text: turn.text))
            }
        }

        // PASS 1 — headers claim their speaker first: a speaker's FIRST turn header carries
        // the canonical `[[Name]]` link, later headers (and every inline mention) demote to
        // the short name. This makes the labelled attribution the one link per speaker, so
        // it can't be lost to an earlier inline name-drop ("one note, one link").
        var seen = Set<String>()
        var headers: [String] = []
        for m in merged {
            if let p = m.person {
                let canonKey = NamesMerge.keyName(p.canonical).trimmingCharacters(in: .whitespaces)
                if seen.insert(canonKey.lowercased()).inserted {
                    headers.append("[[\(canonKey)]]")               // first mention → full link
                } else {
                    let short = shortName(for: p)
                    headers.append(short.isEmpty ? canonKey : short) // later → plain short name
                }
            } else {
                headers.append(m.rawName)                            // Speaker N / unknown → plain
            }
        }

        // PASS 2 — bodies in document order (the leading preamble first, then each turn),
        // sharing `seen`: each person's FIRST not-yet-linked SAFE inline mention → the
        // alias-display link, the rest → the short name. The preamble (e.g. an early image
        // marker) is preserved as its own block, never dropped.
        var blocks: [String] = []
        if !preamble.isEmpty {
            blocks.append(linkInline(preamble, overrides: ov, seen: &seen))
        }
        for (i, m) in merged.enumerated() {
            let body = linkInline(m.text, overrides: ov, seen: &seen)
            blocks.append("**\(headers[i]):** \(body)")
        }
        let finalText = blocks.joined(separator: "\n\n")
        // Suggested occurrences over the FINAL body. `seen` = everyone linked (matched
        // speakers + first-mention inline links) so they're never re-suggested.
        let suggested = suggestedOccurrences(in: finalText, overrides: ov, linkedKeys: seen)
        return Result(sanitised: finalText, ambiguous: suggested)
    }

    /// Link inline alias mentions, FIRST-ONLY per person ("one note, one link"), OPT-OUT +
    /// risk-tiered. For each person not yet linked anywhere in the conversation (`seen`),
    /// their FIRST eligible SAFE mention (a distinctive, unambiguous alias) becomes the
    /// Obsidian alias-display link `[[Canonical|short]]` (or bare `[[Canonical]]` when the
    /// short equals the canonical); every LATER mention — plus every mention of an
    /// already-linked person (a matched speaker linked in their header, or a person linked
    /// in an earlier turn) — demotes to the plain short name. A person reachable here only
    /// via an FP-prone alias (common word / too short) or an ambiguous one is NOT linked and
    /// NOT demoted — left as spoken so the suggestion pass can offer them. The display is the
    /// short, NOT the transcribed surface, so a misheard name ("cherry"/"thierry" for "Tuur")
    /// normalises to the correct short. The whole match (alias + trailing possessive) is
    /// replaced and the possessive re-appended OUTSIDE the brackets.
    ///
    /// `seen` is shared across the whole document (headers + every body) and updated in
    /// place, so each person links exactly once. Ambiguous aliases, FP-prone first mentions,
    /// non-prose spans, and matches already inside a link are left untouched.
    static func linkInline(_ inputText: String, overrides ov: Overrides,
                                   seen: inout Set<String>) -> String {
        var text = inputText
        for p in ov.linkPeople {
            let canonKey = NamesMerge.keyName(p.canonical).trimmingCharacters(in: .whitespaces)
            let keyLower = canonKey.lowercased()
            let unambiguous = ov.ownedAliases(of: p).filter { !ov.ambiguousAliases.contains($0.lowercased()) }
            guard !unambiguous.isEmpty else { continue }
            // The display is the person's short name — fixed per person, independent of
            // what was transcribed — so every matched form normalises to it.
            let short = shortName(for: p)
            let display = (short.isEmpty || short.caseInsensitiveCompare(canonKey) == .orderedSame)
                ? "[[\(canonKey)]]"
                : "[[\(canonKey)|\(short)]]"

            if !seen.contains(keyLower) {
                // Not linked yet. Only a distinctive (non-FP-prone) alias — or a force-picked
                // one — may auto-commit a NEW inline link; a common-word/too-short-only,
                // unpicked person stays plain (suggested).
                let linkAliases = unambiguous.filter { !NameStoplist.isFpProne($0) || ov.forced[$0.lowercased()] != nil }
                guard !linkAliases.isEmpty else { continue }
                let prot = nonProseRanges(in: text)
                var earliest: (range: NSRange, poss: String)?
                for rx in linkAliases.compactMap({ wordRegex($0) }) {
                    // First ELIGIBLE match of this alias (skipping any inside a link / non-prose
                    // span — e.g. a leading audiobook quote), then take the earliest across aliases.
                    for m in rx.matches(in: text, range: fullRange(text)) where eligible(text, m.range.location, prot) {
                        if earliest == nil || m.range.location < earliest!.range.location {
                            earliest = (m.range, possText(m, in: text))
                        }
                        break
                    }
                }
                guard let first = earliest else { continue }    // no SAFE mention in this block
                text = nsReplace(text, first.range, with: display + first.poss)
                seen.insert(keyLower)
            }
            // Remaining mentions (and EVERY mention of an already-linked person) → the short
            // name, falling back to the canonical when no short is defined (so the contract
            // "every later mention demotes" holds even for a single-token name).
            let demotion = short.isEmpty ? canonKey : short
            guard !demotion.isEmpty else { continue }
            let prot = nonProseRanges(in: text)
            for rx in unambiguous.compactMap({ wordRegex($0) }) {
                for m in rx.matches(in: text, range: fullRange(text)).reversed() {
                    if !eligible(text, m.range.location, prot) { continue }
                    text = nsReplace(text, m.range, with: demotion + possText(m, in: text))
                }
            }
        }
        return text
    }

    /// The *suggested* tier (NAMING_MODEL.md): recognised-but-not-auto-linked occurrences the
    /// review surface renders dotted (commit on click), recorded over the FINAL text so
    /// offsets/contexts match what renders. Two kinds, both skipping existing links +
    /// non-prose spans:
    ///   (a) AMBIGUOUS aliases (shared by 2+ roster people) — every plain occurrence, any case;
    ///   (b) FP-PRONE single-candidate aliases (common word / too short — `NameStoplist`) whose
    ///       person did NOT auto-link — only CAPITALIZED occurrences (the capitalization
    ///       FP-guard keeps "I will call" plain while surfacing "Will came over").
    static func suggestedOccurrences(in text: String, overrides ov: Overrides,
                                             linkedKeys: Set<String>) -> [AmbiguousOccurrence] {
        let prot = nonProseRanges(in: text)
        var out: [AmbiguousOccurrence] = []
        func record(alias: String, candidates: [Person], capitalizedOnly: Bool) {
            guard let rx = wordRegex(alias) else { return }
            for m in rx.matches(in: text, range: fullRange(text)) {
                let loc = m.range.location
                if !eligible(text, loc, prot) { continue }
                if capitalizedOnly, !startsUppercase(text, at: loc) { continue }
                out.append(AmbiguousOccurrence(
                    alias: alias,
                    offset: loc,
                    length: m.range.length,
                    contextBefore: nsSub(text, max(0, loc - 40), loc),
                    contextAfter: nsSub(text, loc + m.range.length, min(nsLen(text), loc + m.range.length + 40)),
                    candidates: candidates.map {
                        NameCandidate(id: $0.canonical, canonical: $0.canonical, short: shortName(for: $0))
                    }
                ))
            }
        }
        // (a) ambiguous linkable aliases — every occurrence, any case.
        for alias in ov.ambiguousAliases.sorted() {
            record(alias: alias, candidates: ov.aliasMap[alias] ?? [], capitalizedOnly: false)
        }
        // (b) common-word / too-short single linkable names whose person didn't auto-link.
        for alias in ov.aliasMap.keys.sorted() where !ov.ambiguousAliases.contains(alias) {
            guard NameStoplist.isFpProne(alias), let people = ov.aliasMap[alias], people.count == 1,
                  !linkedKeys.contains(Overrides.key(people[0])) else { continue }
            record(alias: alias, candidates: people, capitalizedOnly: true)
        }
        // (c) PRUNED people whose alias no linkable person owns → dotted (re-promotable) suggestion.
        for alias in ov.prunedAliasMap.keys.sorted() {
            record(alias: alias, candidates: ov.prunedAliasMap[alias] ?? [],
                   capitalizedOnly: NameStoplist.isFpProne(alias))
        }
        return out
    }

    /// Plain (not-inside-`[[ ]]`) whole-word occurrences of `alias` in `text`, in
    /// reading order. Used by the unlink popover to count a person's plain mentions
    /// (the short-name forms the Sanitiser already left/demoted). Each range covers
    /// the alias (+ any trailing `'s`); skips matches inside an existing link.
    static func plainOccurrences(of alias: String, in text: String) -> [NSRange] {
        let a = alias.trimmingCharacters(in: .whitespaces)
        guard !a.isEmpty, let rx = wordRegex(a) else { return [] }
        return rx.matches(in: text, range: fullRange(text))
            .map { $0.range }
            .filter { !avoidInside || notInsideLink(text, $0.location) }
    }

}
