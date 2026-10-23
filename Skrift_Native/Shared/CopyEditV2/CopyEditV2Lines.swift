import Foundation

extension CopyEditV2 {
    /// D215: lines the model never sees, held aside like pictures and put back in place.
    /// Checkbox lines (`- [ ]` / `- [x]`) always, so a task keeps its box and its state; every
    /// list line (`- `, `* `, `1. `) of a TYPED note, so a typed list stays a list. A run of
    /// held lines is one block: a block that was a paragraph of its own returns as one after the
    /// same number of edited paragraphs; a block inside a paragraph returns inside the same-index
    /// edited paragraph, at its line when the paragraph kept its line count, else at its edge.
    struct HeldLines {
        struct Block: Equatable {
            let lines: [String]
            /// Own paragraph: the number of model paragraphs before it. Inside one: that paragraph's index.
            let para: Int
            /// Inside a paragraph: the number of that paragraph's model lines before it.
            let line: Int
            let own: Bool
        }

        /// What the model reads: the text with every held line out. Byte-identical to the input
        /// when nothing is held.
        let prose: String
        let blocks: [Block]
        /// Lines per model paragraph, as the model was given them.
        let lineCounts: [Int]

        static let checkboxRegex = try! NSRegularExpression(pattern: #"^[ \t]*(?:[-*+]|\d+[.)])[ \t]+\[[ xX]\]"#)
        static let listRegex = try! NSRegularExpression(pattern: #"^[ \t]*(?:[-*+]|\d+[.)])[ \t]+\S"#)

        static func isHeld(_ line: String, typed: Bool) -> Bool {
            let r = NSRange(location: 0, length: (line as NSString).length)
            return (typed ? listRegex : checkboxRegex).firstMatch(in: line, range: r) != nil
        }

        init(_ text: String, typed: Bool) {
            guard text.components(separatedBy: "\n").contains(where: { Self.isHeld($0, typed: typed) }) else {
                prose = text; blocks = []; lineCounts = []
                return
            }
            var model: [String] = [], counts: [Int] = [], blocks: [Block] = []
            for para in CopyEditV2.paragraphs(text) {
                var textLines: [String] = [], run: [String] = []
                var inner: [(lines: [String], line: Int)] = []
                for line in para.components(separatedBy: "\n") {
                    if Self.isHeld(line, typed: typed) { run.append(line); continue }
                    if !run.isEmpty { inner.append((run, textLines.count)); run = [] }
                    textLines.append(line)
                }
                if !run.isEmpty { inner.append((run, textLines.count)) }
                if textLines.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                    blocks.append(Block(lines: inner.flatMap(\.lines), para: model.count, line: 0, own: true))
                } else {
                    blocks += inner.map { Block(lines: $0.lines, para: model.count, line: $0.line, own: false) }
                    model.append(textLines.joined(separator: "\n"))
                    counts.append(textLines.count)
                }
            }
            prose = model.joined(separator: "\n\n")
            self.blocks = blocks
            lineCounts = counts
        }

        /// Every held block back into `edited`, in its original order.
        func putBack(_ edited: String) -> String {
            guard !blocks.isEmpty else { return edited }
            let paras = CopyEditV2.paragraphs(edited)
            var out: [String] = []
            for k in 0...paras.count {
                // Own blocks before paragraph k; a block inside a paragraph the edit no longer has, at the end.
                out += blocks.filter { $0.own ? Swift.min($0.para, paras.count) == k : ($0.para >= paras.count && k == paras.count) }
                    .map { $0.lines.joined(separator: "\n") }
                guard k < paras.count else { break }
                let inside = blocks.filter { !$0.own && $0.para == k }
                out.append(inside.isEmpty ? paras[k] : Self.merge(paras[k], inside,
                                                                  inputLines: k < lineCounts.count ? lineCounts[k] : -1))
            }
            return out.joined(separator: "\n\n")
        }

        private static func merge(_ para: String, _ inside: [Block], inputLines: Int) -> String {
            var lines = para.components(separatedBy: "\n")
            if lines.count == inputLines {
                for b in inside.reversed() { lines.insert(contentsOf: b.lines, at: Swift.min(b.line, lines.count)) }
                return lines.joined(separator: "\n")
            }
            let head = inside.filter { $0.line == 0 }.flatMap(\.lines)
            let tail = inside.filter { $0.line != 0 }.flatMap(\.lines)
            return (head + lines + tail).joined(separator: "\n")
        }
    }
}
