import Foundation

/// C123 (Q464, D37): who sent a share. The share sheet's "From" row types an optional name, with
/// autocomplete from the roster; the name rides the capture inbox entry (`senderName`) and the
/// drain writes it into the note as an ordinary person mention ("From Marta Silva"). The same
/// shared `Sanitiser` that links every other mention links it when the name is on the roster and
/// leaves it plain otherwise, so `people:` carries it exactly when it is linked.
///
/// The extension cannot read the app's `names.json` (it lives in the app's own Documents), so the
/// app mirrors the roster's NAMES (canonical + aliases, nothing else) into the App Group on every
/// drain (`ShareRosterSnapshot`). A share that carries a chat hint (an `INSendMessageIntent`
/// conversation) remembers the name for that chat (`ShareSenderMemory`). Pure Foundation:
/// compiled into the app, the share extension and the tests.
enum ShareSender {

    /// The typed name, trimmed and single-spaced; nil when empty. Brackets are stripped so a
    /// typed "[[Marta]]" cannot nest a link inside the mention.
    static func clean(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let stripped = raw.replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")
        let words = stripped.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        let out = words.joined(separator: " ")
        return out.isEmpty ? nil : String(out.prefix(80))
    }

    /// The mention line the note carries.
    static func mentionLine(_ name: String) -> String { "From \(name)" }

    /// `body` with the sender's mention line appended as its own paragraph (the note's own text
    /// stays first, so the title ladder never reads "From …" ahead of his words).
    static func appending(_ sender: String?, to body: String?) -> String? {
        guard let name = clean(sender) else { return body }
        let line = mentionLine(name)
        guard let body, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return line }
        return body + "\n\n" + line
    }

    /// The roster's spelling of a typed name: an exact canonical or alias match (case and
    /// diacritic insensitive) becomes the canonical, anything else stays as typed.
    static func resolved(_ typed: String, roster: [ShareRosterName]) -> String {
        let key = fold(typed)
        for p in roster where fold(p.name) == key || p.aliases.contains(where: { fold($0) == key }) {
            return p.name
        }
        return typed
    }

    struct Suggestion: Equatable, Sendable {
        let name: String
        /// The grey line beside it: the chat it was remembered for, else "on your roster".
        let detail: String
    }

    /// Roster names whose canonical or any alias starts with `query` (word starts count, so
    /// "Sil" finds "Marta Silva"), at most `limit`. Empty query → none.
    static func suggestions(for query: String, roster: [ShareRosterName],
                            remembered: [String: String] = [:], limit: Int = 4) -> [Suggestion] {
        let q = fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !q.isEmpty else { return [] }
        func hit(_ s: String) -> Bool {
            let f = fold(s)
            return f.hasPrefix(q) || f.split(separator: " ").contains { $0.hasPrefix(q) }
        }
        var out: [Suggestion] = []
        var seen = Set<String>()
        for p in roster where hit(p.name) || p.aliases.contains(where: hit) {
            guard seen.insert(fold(p.name)).inserted else { continue }
            if fold(p.name) == q { continue }   // already typed in full
            let chat = remembered.first { fold($0.value) == fold(p.name) }?.key
            out.append(Suggestion(name: p.name, detail: chat.map { ShareChatHint.label($0) } ?? "on your roster"))
            if out.count == limit { break }
        }
        return out
    }

    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// A chat hint key: "<app>|<conversation>" so the label can name the chat ("WhatsApp: Marta").
enum ShareChatHint {
    static func key(app: String?, conversation: String) -> String { "\(app ?? "")|\(conversation)" }

    static func label(_ key: String) -> String {
        let parts = key.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2 else { return key }
        return parts[0].isEmpty ? parts[1] : "\(parts[0]): \(parts[1])"
    }
}

/// One roster person as the share extension sees it: the bare canonical + aliases.
struct ShareRosterName: Codable, Equatable, Sendable {
    let name: String
    let aliases: [String]
}

/// The roster's names mirrored into the App Group (`ShareRoster.json`) for the extension.
enum ShareRosterSnapshot {
    static let fileName = "ShareRoster.json"

    static func url(in container: URL?) -> URL? { container?.appendingPathComponent(fileName) }

    /// Written by the app; skipped when the content is unchanged.
    @discardableResult
    static func write(_ names: [ShareRosterName], container: URL?) -> Bool {
        guard let url = url(in: container),
              let data = try? JSONEncoder().encode(names) else { return false }
        if (try? Data(contentsOf: url)) == data { return true }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    static func read(container: URL?) -> [ShareRosterName] {
        guard let url = url(in: container), let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([ShareRosterName].self, from: data)) ?? []
    }
}

/// C123 "remembered per chat": chat hint key → the name he typed for it (`ShareSenders.json`).
struct ShareSenderMemory {
    static let fileName = "ShareSenders.json"
    let url: URL

    static func inContainer(_ container: URL?) -> ShareSenderMemory? {
        container.map { ShareSenderMemory(url: $0.appendingPathComponent(fileName)) }
    }

    func all() -> [String: String] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    func name(for hint: String?) -> String? {
        guard let hint else { return nil }
        return all()[hint]
    }

    /// Remember (or, with an empty name, forget) the sender for a chat.
    func remember(_ name: String?, for hint: String?) {
        guard let hint else { return }
        var map = all()
        map[hint] = ShareSender.clean(name)
        if let data = try? JSONEncoder().encode(map) { try? data.write(to: url, options: .atomic) }
    }
}
