import SwiftUI
import AppKit
import ImageIO

/// Editable note body with live `[[wiki link]]` accent styling + inline image
/// thumbnails for `[[img_NNN]]` markers — an NSTextView bridge (SwiftUI's TextEditor
/// can't do either). Self-sizing (no internal scroll; the surrounding SwiftUI
/// ScrollView scrolls). The MODEL string always keeps the literal `[[img_NNN]]`
/// markers + `[[brackets]]` (WYSIWYG to the exported markdown); the text view shows a
/// thumbnail in the marker's place via a custom attachment, and the marker is
/// reconstructed from that attachment whenever the user edits.
///
/// Unlink (mocks/name-unlink.html): when `onUnlink` is wired, an already-linked
/// `[[Name]]` whose core matches a live person is clickable — single-click opens a
/// popover offering "unlink this mention" (→ the plain alias as spoken), "unlink all
/// mentions in this note" (persisted so re-processing won't re-link), or "change to →
/// <person>". (The in-prose three-tier suggested rendering + which-person popover land
/// in chunk 4 — see NAMING_MODEL.md / mocks/naming-review.html.)
struct BodyTextView: NSViewRepresentable {
    @Binding var text: String
    /// Resolves an image marker number (`[[img_NNN]]`) to its file URL. Defaults to
    /// none (markers stay as styled text).
    var imageURL: (Int) -> URL? = { _ in nil }
    /// Right-click a text selection → "Add … as a new name".
    var onAddName: (String) -> Void = { _ in }
    /// Right-click a selection → "Add … as → alias of <existing person>" (word, canonical).
    var onAddAlias: (String, String) -> Void = { _, _ in }
    /// Click an already-linked `[[Name]]` → the unlink popover; the chosen scope is
    /// reported with the person's bare canonical + the plain alias to restore.
    /// nil = linked names aren't clickable (read-only hosts).
    var onUnlink: ((_ canonical: String, _ alias: String, _ scope: UnlinkScope) -> Void)? = nil
    /// Karaoke playback, or nil when not playing. Applied as an in-place recolor on
    /// THIS text view (no renderer swap → no reflow) + click-a-word-to-seek.
    var karaoke: KaraokePlayback? = nil
    /// Audiobook capture (C2 bookTitle present): the plain-text attribution caption
    /// ("— Author, Book · ch. N") DRAWN under the leading C1 quote block, which is
    /// styled italic + indented behind an accent bar (mocks/audiobook-capture.html
    /// `.quoteblock`). Presentation only — the caption is never inserted into the
    /// storage, the model keeps the raw "> " lines verbatim, and editing can't
    /// corrupt either. nil = not a book capture → no quote styling.
    var quoteAttribution: String? = nil

    /// How far through the body's words to brighten (0…1) + a click-a-word → seek
    /// callback (arg = the clicked word's INDEX, so the caller can seek to that word's
    /// REAL start time from the word-timings — an index-proportional seek lands on the
    /// wrong word when speech is uneven, e.g. a silent intro).
    struct KaraokePlayback {
        var fraction: Double
        var seekWord: (Int) -> Void
    }

    /// Unlink scope picked in the linked-mention popover: ONE mention (the i-th
    /// `[[link]]` of that person in reading order — order-based like the resolver,
    /// so storage-vs-model offset drift from image attachments can't misapply) or
    /// ALL of that person's links in this note.
    enum UnlinkScope: Equatable {
        /// "Change to → <person>": this mention re-links to someone else (the
        /// alias matched the wrong person). Order-based like `.mention`.
        case change(index: Int, to: String)
        case mention(index: Int)
        case all
    }

    fileprivate static let bodyFont = NSFont.systemFont(ofSize: 16)
    fileprivate static let markerRegex = try? NSRegularExpression(pattern: #"\[\[img_(\d+)\]\]"#)
    fileprivate static let linkRegex = try? NSRegularExpression(pattern: #"\[\[[^\]]+\]\]"#)
    // A speaker turn header at the START of a line: `**Name:**` → group 1 the leading
    // `**`, group 2 the bolded `Name:`, group 3 the trailing `**`. Lets the review body
    // render a conversation as bold speaker labels instead of raw markdown asterisks.
    fileprivate static let turnHeaderRegex = try? NSRegularExpression(
        pattern: #"(?m)^[ \t]*(\*\*)([^*\n]+?:)(\*\*)"#)
    // Quote presentation (the mock's `.quoteblock`): text indented clear of the bar,
    // caption a step smaller in the secondary color.
    fileprivate static let quoteIndent: CGFloat = 14
    fileprivate static let captionFont = NSFont.systemFont(ofSize: 12.5)
    fileprivate static let captionGap: CGFloat = 7   // last quote line ↘ caption top
    /// Vertical room reserved under the quote block for the drawn caption (gap +
    /// caption line height + breathing space before the ramble).
    fileprivate static var captionReserve: CGFloat {
        captionGap + ceil(captionFont.ascender - captionFont.descender) + 8
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> SelfSizingTextView {
        let tv = SelfSizingTextView()
        tv.delegate = context.coordinator
        tv.isRichText = false                 // we own the attributes
        tv.drawsBackground = false
        tv.font = Self.bodyFont
        tv.textContainerInset = .zero
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.textContainer?.widthTracksTextView = true
        tv.allowsUndo = true
        // Single-click on a linked `[[Name]]` → unlink popover (suppress cursor placement);
        // during karaoke a click seeks instead.
        tv.onSingleClickAt = { [weak coordinator = context.coordinator, weak tv] idx in
            guard let coordinator, let tv else { return false }
            return coordinator.handleClick(idx, tv)
        }
        tv.quoteAttribution = quoteAttribution
        context.coordinator.render(tv, model: text)
        return tv
    }

    func updateNSView(_ tv: SelfSizingTextView, context: Context) {
        // SwiftUI REUSES this NSView across note switches, so refresh the coordinator's
        // parent — otherwise its `text` binding write-back + `imageURL` resolver + `onUnlink`
        // callback stay bound to the first note shown.
        context.coordinator.parent = self
        if tv.quoteAttribution != quoteAttribution {
            tv.quoteAttribution = quoteAttribution   // note switch capture ↔ plain
            tv.invalidateIntrinsicContentSize()
        }
        // Re-render only on an EXTERNAL change (compare against the reconstructed
        // model so our own edits / thumbnail attachments don't trigger a clobber).
        let textChanged = context.coordinator.modelString(tv) != text
        if textChanged {
            context.coordinator.render(tv, model: text)
            tv.invalidateIntrinsicContentSize()
        }
        if let k = karaoke {
            // Playing: lock editing and recolor in place (bright up to the current
            // word, dim the rest). Same view → identical layout, no reflow.
            if tv.isEditable { tv.isEditable = false }
            context.coordinator.applyKaraoke(tv, fraction: k.fraction)
        } else {
            if !tv.isEditable { tv.isEditable = true }
            // render() already restyled; otherwise we're leaving karaoke — restyle in place.
            if !textChanged { context.coordinator.restyle(tv) }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: BodyTextView
        private var activePopover: NSPopover?
        /// Last applied karaoke boundary, so the ~20 Hz playback ticks skip a recolor
        /// unless the active-word count actually moved (cheap even on long notes).
        private var lastKaraoke: (active: Int, count: Int)?
        /// Live-people snapshot for the link tooltips applied on every restyle —
        /// refreshed per render (note switch / external change) and per unlink click,
        /// NOT per keystroke (`livePeople()` reads names.json from disk).
        private var peopleCache: [Person] = []
        init(_ parent: BodyTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? SelfSizingTextView else { return }
            parent.text = modelString(tv)   // attachments → [[img_NNN]] markers
            restyle(tv)                      // in-place recolor + ambiguous marks (keeps attachments + caret)
            tv.invalidateIntrinsicContentSize()
        }

        /// Right-click a short text selection → "Add '…' as ▸" with a submenu: a NEW
        /// name, or an ALIAS of any existing person. The reliable, user-driven way to
        /// grow the names graph (you pick the exact words; no flaky auto-detection).
        func textView(_ view: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
            let r = view.selectedRange()
            let ns = view.string as NSString
            guard r.length > 0, r.location + r.length <= ns.length else { return menu }
            let sel = ns.substring(with: r).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sel.isEmpty, sel.count <= 60 else { return menu }

            let parentItem = NSMenuItem(title: "Add “\(sel)” as…", action: nil, keyEquivalent: "")
            let sub = NSMenu()

            let newItem = NSMenuItem(title: "A new person…", action: #selector(addNewNameAction(_:)), keyEquivalent: "")
            newItem.target = self; newItem.representedObject = sel
            sub.addItem(newItem)

            let people = NamesStore.shared.livePeople().sorted {
                NamesMerge.keyName($0.canonical).localizedCaseInsensitiveCompare(NamesMerge.keyName($1.canonical)) == .orderedAscending
            }
            if !people.isEmpty {
                sub.addItem(.separator())
                let header = NSMenuItem(title: "An alias of…", action: nil, keyEquivalent: "")
                header.isEnabled = false
                sub.addItem(header)
                for p in people {
                    let pi = NSMenuItem(title: NamesMerge.keyName(p.canonical), action: #selector(addAliasAction(_:)), keyEquivalent: "")
                    pi.target = self
                    pi.representedObject = AliasTarget(word: sel, canonical: p.canonical)
                    sub.addItem(pi)
                }
            }
            parentItem.submenu = sub
            menu.insertItem(parentItem, at: 0)
            menu.insertItem(.separator(), at: 1)
            return menu
        }

        @objc private func addNewNameAction(_ sender: NSMenuItem) {
            if let sel = sender.representedObject as? String { parent.onAddName(sel) }
        }
        @objc private func addAliasAction(_ sender: NSMenuItem) {
            if let t = sender.representedObject as? AliasTarget { parent.onAddAlias(t.word, t.canonical) }
        }

        /// Build the text storage from the model: plain body + inline image thumbnails
        /// spliced where `[[img_NNN]]` markers resolve to a file, + accent `[[links]]`
        /// + ambiguous-name marks.
        func render(_ tv: SelfSizingTextView, model: String) {
            let primary = NSColor(Theme.textPrimary)
            // Synchronous: text + markers-as-text only — instant. Image disk-load +
            // thumbnailing (measured ~600ms EACH on the main thread, freezing the
            // note switch) is moved off-main below and spliced in when ready.
            let attributed = NSMutableAttributedString(
                string: model, attributes: [.font: BodyTextView.bodyFont, .foregroundColor: primary])
            tv.textStorage?.setAttributedString(attributed)
            lastKaraoke = nil   // new text → force the next karaoke recolor
            if parent.onUnlink != nil { peopleCache = NamesStore.shared.livePeople() }
            restyle(tv)
            tv.typingAttributes = [.font: BodyTextView.bodyFont, .foregroundColor: primary]
            loadThumbnails(into: tv, model: model)
        }

        /// In-place karaoke: brighten the first `fraction` of the body's words, dim the
        /// rest — on the SAME text view as the editor, so playing never reflows. Skips
        /// the work when the boundary hasn't moved (called ~20×/s while playing).
        func applyKaraoke(_ tv: SelfSizingTextView, fraction: Double) {
            guard let storage = tv.textStorage else { return }
            let words = Coordinator.wordRanges(storage.string)
            let active = max(0, min(words.count, Int((fraction * Double(words.count)).rounded())))
            if let last = lastKaraoke, last.active == active, last.count == words.count { return }
            lastKaraoke = (active, words.count)
            let bright = NSColor(Theme.textPrimary)
            let dim = NSColor(Theme.textPrimary).withAlphaComponent(0.4)
            let full = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.addAttribute(.foregroundColor, value: dim, range: full)
            storage.removeAttribute(.backgroundColor, range: full)
            storage.removeAttribute(.underlineStyle, range: full)
            storage.removeAttribute(.underlineColor, range: full)
            for (i, r) in words.enumerated() where i < active {
                storage.addAttribute(.foregroundColor, value: bright, range: r)
            }
            storage.endEditing()
        }

        /// Whitespace-delimited word ranges — the karaoke highlight unit + the
        /// click-to-seek hit map. Matches `BodyText.tokenize`'s word definition so the
        /// NSTextView highlight lines up with the read-path one.
        static func wordRanges(_ s: String) -> [NSRange] {
            let ns = s as NSString
            var ranges: [NSRange] = []
            var start = -1
            for i in 0..<ns.length {
                let c = ns.character(at: i)
                let isSpace = CharacterSet.whitespacesAndNewlines.contains(UnicodeScalar(c) ?? UnicodeScalar(32))
                if isSpace {
                    if start >= 0 { ranges.append(NSRange(location: start, length: i - start)); start = -1 }
                } else if start < 0 {
                    start = i
                }
            }
            if start >= 0 { ranges.append(NSRange(location: start, length: ns.length - start)) }
            return ranges
        }

        /// Resolve marker→URL on main (cheap), load + thumbnail OFF-main, then splice
        /// the thumbnails into the storage on main — only if the note hasn't changed.
        private func loadThumbnails(into tv: SelfSizingTextView, model: String) {
            guard let rx = BodyTextView.markerRegex else { return }
            let ns = model as NSString
            var jobs: [(num: Int, url: URL)] = []
            for m in rx.matches(in: model, range: NSRange(location: 0, length: ns.length)) {
                let num = Int(ns.substring(with: m.range(at: 1))) ?? 0
                if let url = parent.imageURL(num) { jobs.append((num, url)) }
            }
            guard !jobs.isEmpty else { return }
            Task.detached(priority: .userInitiated) {
                var thumbs: [Int: NSImage] = [:]
                for job in jobs where thumbs[job.num] == nil {
                    if let img = Coordinator.loadThumbnail(url: job.url) { thumbs[job.num] = img }
                }
                guard !thumbs.isEmpty else { return }
                await MainActor.run { [weak self, weak tv] in
                    guard let self, let tv, self.modelString(tv) == model else { return }   // same note, unedited
                    self.splice(thumbs, into: tv)
                }
            }
        }

        private func splice(_ thumbs: [Int: NSImage], into tv: SelfSizingTextView) {
            guard let storage = tv.textStorage, let rx = BodyTextView.markerRegex else { return }
            let full = storage.string as NSString
            let sel = tv.selectedRanges
            storage.beginEditing()
            for m in rx.matches(in: storage.string, range: NSRange(location: 0, length: full.length)).reversed() {
                let num = Int(full.substring(with: m.range(at: 1))) ?? 0
                guard let img = thumbs[num] else { continue }
                let att = ImageMarkerAttachment(imgNumber: num)
                att.image = img
                storage.replaceCharacters(in: m.range, with: NSAttributedString(attachment: att))
            }
            storage.endEditing()
            restyle(tv)
            tv.selectedRanges = sel
            tv.invalidateIntrinsicContentSize()
        }

        /// Reset to primary, accent the `[[links]]`, then mark ambiguous names — in
        /// place, so attachments and the caret/selection survive (no full storage
        /// rebuild per keystroke).
        func restyle(_ tv: SelfSizingTextView) {
            guard let storage = tv.textStorage else { return }
            lastKaraoke = nil   // normal styling applied → next karaoke entry must recolor
            let full = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.addAttribute(.foregroundColor, value: NSColor(Theme.textPrimary), range: full)
            storage.removeAttribute(.backgroundColor, range: full)
            storage.removeAttribute(.underlineStyle, range: full)
            storage.removeAttribute(.underlineColor, range: full)
            storage.removeAttribute(.toolTip, range: full)
            styleLeadingQuote(storage)
            if let rx = BodyTextView.linkRegex {
                for m in rx.matches(in: storage.string, range: full) {
                    storage.addAttribute(.foregroundColor, value: NSColor(Theme.accent), range: m.range)
                    // A linked person is clickable (unlink popover) — say so on hover.
                    if parent.onUnlink != nil, m.range.length > 4 {
                        let core = (storage.string as NSString)
                            .substring(with: NSRange(location: m.range.location + 2, length: m.range.length - 4))
                        if let p = person(matchingCore: core) {
                            storage.addAttribute(
                                .toolTip,
                                value: "Linked to \(NamesMerge.keyName(p.canonical)) — click to unlink",
                                range: m.range)
                        }
                    }
                }
            }
            // Bold the `**Name:**` turn headers so a conversation reads as speaker
            // labels, not raw markdown. The `**` delimiters STAY in the model (export
            // keeps the markdown + a hand edit round-trips) but are dimmed to recede;
            // the name — and any `[[link]]` accent already applied inside it — goes bold.
            if let hrx = BodyTextView.turnHeaderRegex {
                let boldName = NSFontManager.shared.convert(BodyTextView.bodyFont, toHaveTrait: .boldFontMask)
                let faint = NSColor(Theme.textPrimary).withAlphaComponent(0.22)
                for m in hrx.matches(in: storage.string, range: full) {
                    storage.addAttribute(.font, value: boldName, range: m.range(at: 2))
                    storage.addAttribute(.foregroundColor, value: faint, range: m.range(at: 1))
                    storage.addAttribute(.foregroundColor, value: faint, range: m.range(at: 3))
                }
            }
            storage.endEditing()
            // The bar + caption are drawn outside the glyph rects (in the reserved
            // paragraph spacing), which an in-place edit doesn't invalidate.
            if parent.quoteAttribution != nil { tv.needsDisplay = true }
        }

        /// Audiobook-capture presentation for the leading C1 quote block: italic,
        /// indented clear of the accent bar, with room reserved under the last quote
        /// line for the drawn attribution caption (`drawQuoteDecoration`). Attributes
        /// only, reapplied in place on every restyle — the model string keeps the raw
        /// "> " lines verbatim, and a hand edit (even deleting the ">" markers)
        /// simply restyles whatever block remains.
        private func styleLeadingQuote(_ storage: NSTextStorage) {
            guard parent.quoteAttribution != nil else { return }
            // Reset first — the block may have shrunk or vanished since the last pass.
            let full = NSRange(location: 0, length: storage.length)
            storage.addAttribute(.font, value: BodyTextView.bodyFont, range: full)
            storage.removeAttribute(.paragraphStyle, range: full)
            let ranges = BookCapture.quoteLineRanges(in: storage.string)
            guard let last = ranges.last, NSMaxRange(last) <= storage.length else { return }
            let italic = NSFontManager.shared.convert(BodyTextView.bodyFont, toHaveTrait: .italicFontMask)
            let quoteStyle = NSMutableParagraphStyle()
            quoteStyle.firstLineHeadIndent = BodyTextView.quoteIndent
            quoteStyle.headIndent = BodyTextView.quoteIndent
            let lastStyle = quoteStyle.mutableCopy() as! NSMutableParagraphStyle
            lastStyle.paragraphSpacing = BodyTextView.captionReserve
            for (i, r) in ranges.enumerated() {
                storage.addAttribute(.font, value: italic, range: r)
                storage.addAttribute(.paragraphStyle,
                                     value: i == ranges.count - 1 ? lastStyle : quoteStyle,
                                     range: r)
            }
        }

        /// The cached live person whose canonical key equals a link's core
        /// (case-insensitive), or nil for non-person links (places, etc.). Tolerates an
        /// Obsidian alias-display core (`Tiuri Hartog|Tuur`) by matching its target part,
        /// so a `[[Canonical|spoken]]` mention stays clickable for unlink/relink.
        private func person(matchingCore core: String) -> Person? {
            let key = Sanitiser.linkTarget(core)
            guard !key.isEmpty else { return nil }
            return peopleCache.first {
                NamesMerge.keyName($0.canonical).trimmingCharacters(in: .whitespaces)
                    .caseInsensitiveCompare(key) == .orderedSame
            }
        }

        // MARK: - Click interaction (karaoke seek + unlink popover)

        /// A single click at character `idx`. During karaoke it seeks the audio to the
        /// clicked word; otherwise an already-linked `[[Name]]` opens the unlink popover.
        /// Returns true when handled (suppresses cursor placement).
        func handleClick(_ idx: Int, _ tv: SelfSizingTextView) -> Bool {
            // Karaoke: click a word → seek there (the old behavior the user missed).
            if let k = parent.karaoke, let storage = tv.textStorage {
                let words = Coordinator.wordRanges(storage.string)
                if let wi = words.firstIndex(where: { NSLocationInRange(idx, $0) || idx == NSMaxRange($0) }) {
                    k.seekWord(wi)   // caller maps the index → that word's real start time
                    return true
                }
                return false
            }
            guard let storage = tv.textStorage else { return false }
            let text = storage.string
            // Already-linked [[Name]] → unlink popover (mocks/name-unlink.html). A
            // fresh names read per click — one-shot, and the render-time cache could
            // be stale after a right-click "Add as name".
            if parent.onUnlink != nil {
                for link in Sanitiser.linkOccurrences(in: text)
                where NSLocationInRange(idx, link.range) || idx == NSMaxRange(link.range) {
                    peopleCache = NamesStore.shared.livePeople()
                    guard let p = person(matchingCore: link.core) else { return false }   // place link etc. → caret as usual
                    showUnlinkPopover(link: link, person: p, tv: tv, text: text)
                    return true
                }
            }
            return false
        }

        /// The unlink popover at a clicked `[[Name]]`. The chosen scope is order-based
        /// (the i-th link of this person in reading order) so the apply against the MODEL
        /// text can't drift when image attachments shorten the storage string.
        private func showUnlinkPopover(link: Sanitiser.BodyLink, person p: Person,
                                       tv: SelfSizingTextView, text: String) {
            activePopover?.performClose(nil)
            let ns = text as NSString
            let beforeLen = min(38, link.range.location)
            let before = ns.substring(with: NSRange(location: link.range.location - beforeLen, length: beforeLen))
            let afterStart = NSMaxRange(link.range)
            let after = ns.substring(with: NSRange(location: afterStart, length: min(38, ns.length - afterStart)))

            let canonical = NamesMerge.keyName(p.canonical).trimmingCharacters(in: .whitespaces)
            let alias = Sanitiser.spokenAlias(for: p)
            let links = Sanitiser.linkOccurrences(of: canonical, in: text)
            let index = links.firstIndex { $0.range == link.range } ?? 0
            // "Mentions" the way the mock counts them: this person's [[links]] plus
            // the plain short-name mentions the Sanitiser already left/demoted.
            let mentionCount = links.count + Sanitiser.plainOccurrences(of: alias, in: text).count

            // "Change to →" candidates: every OTHER live person (the alias may
            // simply have matched the wrong one — the two-Jacks case).
            let others = peopleCache
                .map { NamesMerge.keyName($0.canonical) }
                .filter { $0.caseInsensitiveCompare(canonical) != .orderedSame }
                .sorted()

            let view = UnlinkPopover(
                person: canonical, alias: alias,
                contextBefore: before, contextAfter: after,
                mentionCount: mentionCount,
                others: others,
                onUnlinkMention: { [weak self] in
                    self?.closePopover()
                    self?.parent.onUnlink?(canonical, alias, .mention(index: index))
                },
                onUnlinkAll: { [weak self] in
                    self?.closePopover()
                    self?.parent.onUnlink?(canonical, alias, .all)
                },
                onChangeTo: { [weak self] newPerson in
                    self?.closePopover()
                    self?.parent.onUnlink?(canonical, alias, .change(index: index, to: newPerson))
                },
                onCancel: { [weak self] in self?.closePopover() })
            let host = NSHostingController(rootView: view)
            host.sizingOptions = [.preferredContentSize]
            let pop = NSPopover()
            pop.contentViewController = host
            pop.behavior = .transient
            activePopover = pop
            pop.show(relativeTo: boundingRect(link.range, in: tv), of: tv, preferredEdge: .maxY)
        }

        private func closePopover() { activePopover?.performClose(nil); activePopover = nil }

        private func boundingRect(_ range: NSRange, in tv: SelfSizingTextView) -> NSRect {
            guard let lm = tv.layoutManager, let tc = tv.textContainer else { return .zero }
            let g = lm.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var r = lm.boundingRect(forGlyphRange: g, in: tc)
            r.origin.x += tv.textContainerOrigin.x
            r.origin.y += tv.textContainerOrigin.y
            return r
        }

        /// Reconstruct the model string: image attachments → `[[img_NNN]]`, rest verbatim.
        func modelString(_ tv: SelfSizingTextView) -> String {
            guard let storage = tv.textStorage else { return tv.string }
            var out = ""
            storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
                if let att = value as? ImageMarkerAttachment {
                    out += String(format: "[[img_%03d]]", att.imgNumber)
                } else {
                    out += storage.attributedSubstring(from: range).string
                }
            }
            return out
        }

        /// Thread-safe downscaled thumbnail via ImageIO — decodes directly at thumbnail
        /// size, so it's cheap to run OFF the main thread (unlike NSImage
        /// lockFocus/draw, which forced a full decode on main → the ~600ms/image lag).
        static func loadThumbnail(url: URL, maxPixel: CGFloat = 720) -> NSImage? {
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                  ] as CFDictionary) else { return nil }
            // Display at half the pixel size → ~360pt wide, crisp on Retina.
            return NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width) / 2, height: CGFloat(cg.height) / 2))
        }
    }
}

/// Popover shown at a clicked, already-linked `[[Name]]`, per the signed-off mock
/// (mocks/name-unlink.html). Scopes + cancel: this mention → the plain alias as spoken;
/// all mentions in this note → also persisted so re-processing won't re-link; change to →
/// another person. (A "never link anywhere" scope was deliberately left out — that's a
/// Names-level rule.)
struct UnlinkPopover: View {
    let person: String          // bare canonical, e.g. "Nick Jansen"
    let alias: String           // plain replacement as spoken, e.g. "Nick"
    let contextBefore: String
    let contextAfter: String
    let mentionCount: Int       // this person's links + plain mentions in the note
    /// Other live people — "Change to →" candidates (wrong-person fix).
    var others: [String] = []
    var onUnlinkMention: () -> Void
    var onUnlinkAll: () -> Void
    var onChangeTo: (String) -> Void = { _ in }
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            (Text("Linked to ").foregroundStyle(Theme.textSecondary)
                + Text(person).foregroundStyle(Theme.textPrimary).bold())
                .font(.system(size: 12)).padding(.bottom, 3)

            (Text("…\(contextBefore)").foregroundStyle(Theme.textMuted)
                + Text("[[\(person)]]").foregroundStyle(Theme.accent).bold()
                + Text("\(contextAfter)…").foregroundStyle(Theme.textMuted))
                .font(.system(size: 10.5)).italic().lineLimit(2).padding(.bottom, 9)

            optionRow("Unlink this mention", "→ plain “\(alias)”, as spoken", action: onUnlinkMention)
            optionRow("Unlink all mentions in this note",
                      mentionCount > 1
                        ? "all \(mentionCount) “\(alias)” mentions stay plain — won’t re-link on reprocess"
                        : "“\(alias)” appears once — won’t re-link on reprocess",
                      action: onUnlinkAll)

            // Wrong-person fix: re-link THIS mention to someone else (per-mention,
            // like "Unlink this mention" — a body edit, not a Names rule).
            if !others.isEmpty {
                Rectangle().fill(Theme.hairline.opacity(0.08)).frame(height: 0.5).padding(.vertical, 6)
                Text("CHANGE THIS MENTION TO")
                    .font(.system(size: 8.5, weight: .semibold)).kerning(0.5)
                    .foregroundStyle(Theme.textMuted)
                    .padding(.horizontal, 4).padding(.bottom, 2)
                ForEach(others.prefix(5), id: \.self) { other in
                    optionRow("[[\(other)]]", nil, action: { onChangeTo(other) })
                }
            }

            Rectangle().fill(Theme.hairline.opacity(0.08)).frame(height: 0.5).padding(.vertical, 6)

            optionRow("Cancel", nil, plain: true, action: onCancel)

            HStack(alignment: .top, spacing: 5) {
                Image(systemName: "info.circle")
                    .font(.system(size: 9)).foregroundStyle(Theme.textMuted.opacity(0.7))
                Text("Only the first mention carries the [[link]] — later “\(alias)”s are already plain. \(person) stays in your Names.")
                    .font(.system(size: 10)).foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 5).padding(.horizontal, 4)
        }
        .padding(12)
        .frame(width: 264)
        .background(Theme.surfaceHover)
    }

    @ViewBuilder
    private func optionRow(_ title: String, _ subtitle: String?, plain: Bool = false,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 9) {
                Group {
                    if plain {
                        Text("×").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.textMuted)
                    } else {
                        Image(systemName: "link").font(.system(size: 8.5, weight: .bold)).foregroundStyle(Theme.accent)
                    }
                }
                .frame(width: 18, height: 18)
                .background(plain ? Theme.hairline.opacity(0.06) : Theme.accent.opacity(0.2), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 12.5))
                        .foregroundStyle(plain ? Theme.textMuted : Theme.textPrimary)
                    if let subtitle {
                        Text(subtitle).font(.system(size: 10.5)).foregroundStyle(Theme.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Carries (selected word, target person canonical) on an "add as alias" menu item.
private final class AliasTarget {
    let word: String
    let canonical: String
    init(word: String, canonical: String) { self.word = word; self.canonical = canonical }
}

/// An `NSTextAttachment` that remembers which `[[img_NNN]]` marker it stands in for,
/// so the editor can reconstruct the literal marker for the model/export.
final class ImageMarkerAttachment: NSTextAttachment {
    let imgNumber: Int
    init(imgNumber: Int) { self.imgNumber = imgNumber; super.init(data: nil, ofType: nil) }
    required init?(coder: NSCoder) { self.imgNumber = 0; super.init(coder: coder) }
}

/// NSTextView that reports its laid-out height as `intrinsicContentSize` (so SwiftUI
/// sizes it to its content; width comes from the parent column) and routes single
/// clicks for inline name resolution.
final class SelfSizingTextView: NSTextView {
    /// Returns true if the click at the given character index was handled (a resolver
    /// popover opened) → the default cursor placement is suppressed.
    var onSingleClickAt: ((Int) -> Bool)?
    /// Audiobook capture: the attribution caption drawn under the leading C1 quote
    /// block (plus the accent bar beside it). nil = no quote decoration.
    var quoteAttribution: String? {
        didSet { if oldValue != quoteAttribution { needsDisplay = true } }
    }

    override var intrinsicContentSize: NSSize {
        guard let layoutManager, let textContainer else { return super.intrinsicContentSize }
        layoutManager.ensureLayout(for: textContainer)
        var height = layoutManager.usedRect(for: textContainer).height + textContainerInset.height * 2
        // A quote-only capture (no ramble yet) ends inside the quote block, and
        // TextKit drops the trailing paragraph spacing the caption draws into —
        // make sure the caption still fits.
        if quoteAttribution != nil, let block = quoteBlockRect(),
           block.maxY + BodyTextView.captionReserve > height {
            height = block.maxY + BodyTextView.captionReserve
        }
        return NSSize(width: NSView.noIntrinsicMetric, height: max(height, 60))
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawQuoteDecoration()
    }

    /// The laid-out bounds of the leading C1 quote block, in view coordinates.
    private func quoteBlockRect() -> NSRect? {
        guard let lm = layoutManager, let tc = textContainer,
              let last = BookCapture.quoteLineRanges(in: string).last else { return nil }
        let chars = NSRange(location: 0, length: NSMaxRange(last))
        let glyphs = lm.glyphRange(forCharacterRange: chars, actualCharacterRange: nil)
        var rect = lm.boundingRect(forGlyphRange: glyphs, in: tc)
        rect.origin.x += textContainerOrigin.x
        rect.origin.y += textContainerOrigin.y
        return rect
    }

    /// Draws the quote presentation the attributes can't: the accent left bar
    /// spanning quote + caption (the mock's `border-left`), and the plain-text
    /// attribution caption in the space `styleLeadingQuote` reserved under the
    /// block. Pure drawing — nothing enters the text storage or the model.
    private func drawQuoteDecoration() {
        guard let caption = quoteAttribution, !caption.isEmpty,
              let tc = textContainer, let block = quoteBlockRect() else { return }
        let textLeft = textContainerOrigin.x + tc.lineFragmentPadding + BodyTextView.quoteIndent
        let attrs: [NSAttributedString.Key: Any] = [
            .font: BodyTextView.captionFont,
            .foregroundColor: NSColor(Theme.textSecondary),
        ]
        let capSize = (caption as NSString).size(withAttributes: attrs)
        let capOrigin = NSPoint(x: textLeft, y: block.maxY + BodyTextView.captionGap)
        (caption as NSString).draw(at: capOrigin, withAttributes: attrs)

        let bar = NSRect(x: textContainerOrigin.x + tc.lineFragmentPadding + 2,
                         y: block.minY, width: 2.5,
                         height: (capOrigin.y + capSize.height) - block.minY)
        NSColor(Theme.accent).withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: bar, xRadius: 1.25, yRadius: 1.25).fill()
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 1, let handler = onSingleClickAt,
           let idx = charIndex(at: convert(event.locationInWindow, from: nil)), handler(idx) {
            return   // resolver handled it; don't move the caret
        }
        super.mouseDown(with: event)
    }

    /// Character index under a point, or nil if the point isn't actually on a glyph
    /// (glyphIndex(for:) returns the NEAREST glyph, so we confirm containment to avoid
    /// false hits past line ends).
    private func charIndex(at point: CGPoint) -> Int? {
        guard let lm = layoutManager, let tc = textContainer else { return nil }
        let p = CGPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyph = lm.glyphIndex(for: p, in: tc)
        var rect = lm.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: tc)
        rect = rect.insetBy(dx: -1, dy: 0)
        guard rect.contains(p) else { return nil }
        return lm.characterIndexForGlyph(at: glyph)
    }
}
