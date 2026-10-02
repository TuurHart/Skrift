import Foundation

/// EN + NL number-word values, shared by `AlignmentCore` (aligner match keys) and
/// `ChapterDetector` (chapter headings). Callers lowercase, fold diaereses and
/// split on hyphens / whitespace themselves, then hand over the parts.
enum NumberWords {
    private static let units: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
        "eight": 8, "nine": 9,
        "first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5, "sixth": 6,
        "seventh": 7, "eighth": 8, "ninth": 9,
        "een": 1, "twee": 2, "drie": 3, "vier": 4, "vijf": 5, "zes": 6, "zeven": 7,
        "acht": 8, "negen": 9,
        "eerste": 1, "tweede": 2, "derde": 3, "vierde": 4, "vijfde": 5, "zesde": 6,
        "zevende": 7, "achtste": 8, "negende": 9,
    ]
    private static let teens: [String: Int] = [
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15,
        "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19,
        "tenth": 10, "eleventh": 11, "twelfth": 12, "thirteenth": 13, "fourteenth": 14,
        "fifteenth": 15, "sixteenth": 16, "seventeenth": 17, "eighteenth": 18, "nineteenth": 19,
        "tien": 10, "elf": 11, "twaalf": 12, "dertien": 13, "veertien": 14, "vijftien": 15,
        "zestien": 16, "zeventien": 17, "achttien": 18, "negentien": 19,
        "tiende": 10, "elfde": 11, "twaalfde": 12,
    ]
    private static let tens: [String: Int] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60,
        "seventy": 70, "eighty": 80, "ninety": 90,
        "twintig": 20, "dertig": 30, "veertig": 40, "vijftig": 50, "zestig": 60,
        "zeventig": 70, "tachtig": 80, "negentig": 90,
    ]
    private static let linkingWords: Set<String> = ["and", "en", "the", "de", "het"]

    /// Dutch glued compound: "<unit>en<tens>" ("drieentwintig" → 23).
    static func dutchGlued(_ token: String) -> Int? {
        for (tensWord, tensValue) in tens where token.hasSuffix("en" + tensWord) {
            let unitPart = String(token.dropLast(tensWord.count + 2))
            if let u = units[unitPart] { return u + tensValue }
        }
        return nil
    }

    /// Value of already lowercased, hyphen-split parts ("twenty", "three" → 23;
    /// "one", "hundred", "and", "four" → 104; "drieentwintig" → 23), or nil when
    /// any part isn't a number word or the total is 0.
    static func value(of parts: [String]) -> Int? {
        let parts = parts.filter { !linkingWords.contains($0) }
        guard !parts.isEmpty else { return nil }
        var total = 0
        for p in parts {
            if let u = units[p] { total += u }
            else if let t = teens[p] { total += t }
            else if let t = tens[p] { total += t }
            else if p == "hundred" || p == "honderd" { total = max(total, 1) * 100 }
            else if let g = dutchGlued(p) { total += g }
            else { return nil }
        }
        return total > 0 ? total : nil
    }
}
