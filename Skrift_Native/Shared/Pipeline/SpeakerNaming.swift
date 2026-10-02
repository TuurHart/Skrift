import Foundation

/// Naming a conversation's speakers — one rule for the phone's assign sheet and the Mac's
/// gutter popover (Q82 group 11). They used to differ where it mattered: the phone matched the
/// header TEXT (`**Tiuri:**`), so `**[[Tiuri Hartog]]:**` and `**Tiuri:**` were two speakers to
/// it and one to the Mac. Both now match by resolved identity (`SpeakerTurnStyle.HeaderResolver`),
/// the same identity the turn colours use.
enum SpeakerNaming {

    /// Rename EVERY turn of the speaker wearing `displayed` to `newName`, then fold adjacent
    /// same-speaker turns. When the phone's per-turn slot map still lines up with the turns, only
    /// that diarization SLOT is renamed (a same-named twin slot is left alone). nil when the
    /// text is not a conversation or `newName` is blank.
    static func rename(_ transcript: String?, displayed: String, to newName: String, people: [Person],
                       turnSlots: [Int] = [], slot: Int? = nil) -> String? {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        if let slot, let bySlot = SpeakerTranscript.relabelSlot(transcript, turnSlots: turnSlots, slot: slot, to: name) {
            return bySlot
        }
        let resolver = SpeakerTurnStyle.HeaderResolver(people: people)
        let target = resolver.identity(for: SpeakerTurnStyle.label(for: displayed))
        return SpeakerTranscript.relabel(transcript, where: { resolver.identity(for: SpeakerTurnStyle.label(for: $0)) == target },
                                         to: name)
    }

    /// How many turns belong to the speaker wearing `displayed` (their whole voice, short or
    /// full name alike): "A person names all 3 of Speaker 2's turns" (`SplitSpeakersCopy.namesAllTurns`).
    /// One count for the phone's assign sheet and the Mac's popover (Q183).
    static func turnCount(of displayed: String, in transcript: String?, people: [Person]) -> Int {
        let resolver = SpeakerTurnStyle.HeaderResolver(people: people)
        let target = resolver.identity(for: SpeakerTurnStyle.label(for: displayed))
        return (SpeakerTranscript.parse(transcript) ?? [])
            .filter { resolver.identity(for: SpeakerTurnStyle.label(for: $0.name)) == target }.count
    }

    /// The other speakers in the note, for "move this line to…": distinct identities in
    /// first-appearance order, excluding the one wearing `displayed`.
    static func otherSpeakers(than displayed: String, in transcript: String?, people: [Person]) -> [String] {
        let resolver = SpeakerTurnStyle.HeaderResolver(people: people)
        let me = resolver.identity(for: SpeakerTurnStyle.label(for: displayed))
        var seen = Set<String>(), out: [String] = []
        for turn in SpeakerTranscript.parse(transcript) ?? [] {
            let label = SpeakerTurnStyle.label(for: turn.name)
            let id = resolver.identity(for: label)
            if id != me, seen.insert(id).inserted { out.append(label) }
        }
        return out
    }
}
