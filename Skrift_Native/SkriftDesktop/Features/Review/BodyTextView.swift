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
    /// The dotted *suggested* occurrences (`PipelineFile.ambiguousNames`) — recognised names
    /// the engine didn't auto-link (common-word / ambiguous / pruned). Rendered tan + dotted;
    /// clicking opens the which-person popover. Empty = nothing to suggest.
    var suggested: [AmbiguousOccurrence] = []
    /// Roster used to tell PERSON `[[links]]` (→ the #9d8ff7 linked tier) from other
    /// wiki-links (places). Empty = read the live names DB; injected for deterministic snapshots.
    var people: [Person] = []
    /// Naming-review callbacks (mocks/naming-review.html); nil on read-only hosts.
    /// Click a SUGGESTED name → pick a person (force-link) / leave as plain text / new person.
    var onSuggestionPick: ((_ alias: String, _ canonical: String) -> Void)? = nil
    var onSuggestionPlain: ((_ alias: String) -> Void)? = nil
    /// Click a LINKED name → unlink (prune → dotted suggestion) / change person / open note.
    var onLinkedUnlink: ((_ canonical: String) -> Void)? = nil
    var onLinkedChange: ((_ alias: String, _ newCanonical: String) -> Void)? = nil
    var onOpenNote: ((_ canonical: String) -> Void)? = nil
    /// Memo↔memo link chip clicked (phone chunk-5 parity) — open that memo in the
    /// detail pane. nil on read-only hosts → the chip still renders, just inert.
    var onOpenMemoLink: ((_ id: UUID) -> Void)? = nil
    /// The memos the `[[` picker can link to (phone parity). Evaluated LAZILY when the
    /// user types `[[`, so no per-render fetch; empty → the picker stays closed.
    var linkCandidates: () -> [MemoLinkCandidate] = { [] }
    /// The target memo's CURRENT title, so a chip shows the live title — not the snapshot
    /// frozen into `[[memo:UUID|Title]]` at creation (which goes stale when the target is
    /// renamed / enhanced). nil → the target can't be resolved, so keep the snapshot.
    var linkTitle: (UUID) -> String? = { _ in nil }
    /// Inline `#` completion source (the body's Obsidian-style tag popup). Evaluated
    /// lazily as a `#word` is typed; empty → no popup.
    var tagCandidates: () -> [String] = { [] }
    /// A tag completed from the inline `#` popup — the pick also FILES the tag
    /// (→ tags row → frontmatter), so inline tags reach the YAML on export.
    var onInlineTag: (String) -> Void = { _ in }
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

    fileprivate static let bodyFont = NSFont.systemFont(ofSize: 16)
    fileprivate static let markerRegex = try? NSRegularExpression(pattern: #"\[\[img_(\d+)\]\]"#)
    fileprivate static let linkRegex = try? NSRegularExpression(pattern: #"\[\[[^\]]+\]\]"#)
    // Heading tiers (H1/H2/H3+; deeper levels reuse the last). Body is 16pt.
    // The RULES (what is a heading / an inline #tag) live in the shared
    // `BodyMarkdown`; only the LOOK is platform-local.
    fileprivate static let headingFonts: [NSFont] = [
        .systemFont(ofSize: 23, weight: .bold),
        .systemFont(ofSize: 19.5, weight: .bold),
        .systemFont(ofSize: 17, weight: .semibold),
    ]
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
        // Re-render only on an EXTERNAL change. `modelString` must differ from BOTH:
        //  • the raw binding — our own edit already wrote `text = modelString`, so equal
        //    here means "this is our own keystroke", skip (this is the load-bearing guard
        //    while editing NEXT TO a snapped photo: mid-edit the reconstruct isn't
        //    snap-stable, so a snapped-only compare re-rendered on every keystroke — the
        //    photo flashed and typed text jumped before the image); AND
        //  • its snapped form — a pure display has `modelString == snapped(text)`, so a
        //    raw-only compare would loop forever (raw ≠ snapped when a photo is mid-sentence).
        // Differ from both ⇒ the text genuinely changed under us (a phone sync).
        let ms = context.coordinator.modelString(tv)
        let textChanged = ms != text && ms != BodyTransform.snappedImageBody(text)
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
            maybeShowLinkPicker(tv)          // just typed `[[` → open the memo-link picker
            updateTagSuggest(tv)             // typing a `#word` → the inline tag menu
        }

        // MARK: inline `#` tag suggestions (Obsidian idiom)

        /// The caret-anchored tag menu — a PASSIVE child panel (`TagSuggestPanel`): it
        /// never takes key and never touches the text path, so typing/backspace/clicks
        /// stay fully native; the only interception is ↑ ↓ Return Esc in `doCommandBy`
        /// while it's visible.
        private let tagSuggest = TagSuggestPanel()
        /// Candidates fetched ONCE per `#word` run (a full-library fetch per keystroke
        /// was the round-1 slowness), dropped when the menu hides.
        private var tagSessionCandidates: [String]?
        private var tagMatches: [String] = []
        private var tagSel = 0
        /// One-shot: accepting rewrites the run, which fires textDidChange with the
        /// caret still inside `#word` — without this the menu would instantly re-open
        /// over the accepted tag.
        private var suppressTagSuggestOnce = false

        /// Show/refresh/hide the menu for the caret's `#word` run. Called on every
        /// text change (may OPEN) and — only while visible — on selection change
        /// (follows the caret; hides when it leaves the run).
        func updateTagSuggest(_ tv: SelfSizingTextView) {
            if suppressTagSuggestOnce { suppressTagSuggestOnce = false; hideTagSuggest(); return }
            guard activePopover == nil,
                  tv.selectedRange().length == 0,
                  let pr = TagComplete.hashtagPartialRange(in: tv.string, caret: tv.selectedRange().location)
            else { hideTagSuggest(); return }
            let partial = (tv.string as NSString).substring(with: pr)
            let candidates = tagSessionCandidates ?? parent.tagCandidates()
            tagSessionCandidates = candidates
            let matches = TagComplete.completions(partial: partial, candidates: candidates)
            guard !matches.isEmpty else { hideTagSuggest(); return }
            if matches != tagMatches { tagSel = 0 }
            tagMatches = matches
            presentTagSuggest(tv, at: pr)
        }

        private func presentTagSuggest(_ tv: SelfSizingTextView, at range: NSRange) {
            tagSuggest.onPick = { [weak self, weak tv] tag in
                guard let self, let tv else { return }
                self.acceptTag(tag, in: tv)
            }
            tagSuggest.show(matches: tagMatches, selected: tagSel,
                            anchoredTo: boundingRect(range, in: tv), of: tv)
        }

        /// Accept: replace the partial with the tag (plain, undoable text edit) and
        /// FILE it — inline tags reach the frontmatter through the tags row.
        private func acceptTag(_ tag: String, in tv: SelfSizingTextView) {
            defer { hideTagSuggest() }
            guard let pr = TagComplete.hashtagPartialRange(in: tv.string, caret: tv.selectedRange().location)
            else { return }
            suppressTagSuggestOnce = true
            tv.insertText(tag, replacementRange: pr)
            parent.onInlineTag(tag)
        }

        private func hideTagSuggest() {
            tagSuggest.hide()
            tagMatches = []
            tagSel = 0
            tagSessionCandidates = nil
        }

        /// ↑ ↓ Return Esc drive the tag menu while it's up; everything else —
        /// including Backspace — stays native. (Esc arrives as `complete:`, the
        /// NSTextView default binding; intercepting it also keeps the system
        /// completion list from opening over ours.)
        func textView(_ view: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard tagSuggest.isVisible, let tv = view as? SelfSizingTextView else { return false }
            switch commandSelector {
            case #selector(NSResponder.moveDown(_:)), #selector(NSResponder.moveUp(_:)):
                let delta = commandSelector == #selector(NSResponder.moveDown(_:)) ? 1 : -1
                tagSel = max(0, min(tagSel + delta, tagMatches.count - 1))
                if let pr = TagComplete.hashtagPartialRange(in: tv.string, caret: tv.selectedRange().location) {
                    presentTagSuggest(tv, at: pr)
                }
                return true
            case #selector(NSResponder.insertNewline(_:)):
                if tagSel < tagMatches.count { acceptTag(tagMatches[tagSel], in: tv) }
                return true
            case #selector(NSResponder.cancelOperation(_:)), #selector(NSTextView.complete(_:)):
                hideTagSuggest()
                return true
            default:
                return false
            }
        }

        /// While the menu is up, a caret move re-validates it (hides when the caret
        /// leaves the `#word` run — a click elsewhere, arrowing out). Never OPENS it:
        /// opening happens only from typing.
        func textViewDidChangeSelection(_ notification: Notification) {
            guard tagSuggest.isVisible,
                  let tv = notification.object as? SelfSizingTextView else { return }
            updateTagSuggest(tv)
        }

        func textDidEndEditing(_ notification: Notification) {
            hideTagSuggest()
        }

        /// The `[[` trigger (phone chunk-5 parity): when the two chars just before the caret are
        /// `[[` (a fresh literal — rendered links are chip attachments, never literal `[[`), open a
        /// searchable memo picker anchored there. Picking replaces the `[[` with a link chip.
        private func maybeShowLinkPicker(_ tv: SelfSizingTextView) {
            guard activePopover == nil else { return }
            let caret = tv.selectedRange()
            guard caret.length == 0, caret.location >= 2 else { return }
            let ns = tv.string as NSString
            guard ns.substring(with: NSRange(location: caret.location - 2, length: 2)) == "[[" else { return }
            let candidates = parent.linkCandidates()
            guard !candidates.isEmpty else { return }
            let trigger = NSRange(location: caret.location - 2, length: 2)
            presentPopover(MemoLinkPopover(
                candidates: candidates,
                onPick: { [weak self, weak tv] id, title in
                    guard let self, let tv else { return }
                    self.closePopover()
                    self.insertMemoLink(id: id, title: title, replacing: trigger, in: tv)
                },
                onCancel: { [weak self] in self?.closePopover() }),
                at: trigger, in: tv)
        }

        /// Replace the `[[` trigger with the full `[[memo:UUID|Title]]` literal, render it as a chip,
        /// and drop the caret after it. Writing `parent.text` rides the Part-B edit sync to the phone.
        private func insertMemoLink(id: UUID, title: String, replacing trigger: NSRange, in tv: SelfSizingTextView) {
            guard let storage = tv.textStorage, NSMaxRange(trigger) <= storage.length else { return }
            let literal = MemoLinkSyntax.link(id: id, title: title)
            storage.replaceCharacters(in: trigger, with: NSAttributedString(
                string: literal, attributes: [.font: BodyTextView.bodyFont,
                                              .foregroundColor: NSColor(Theme.textPrimary)]))
            spliceMemoLinkChips(tv)          // literal → atomic chip
            restyle(tv)
            parent.text = modelString(tv)    // persist + push (bodyBinding setter)
            // The chip is one character where the `[[` began; put the caret just after it.
            let after = min(trigger.location + 1, (tv.string as NSString).length)
            tv.setSelectedRange(NSRange(location: after, length: 0))
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
        func render(_ tv: SelfSizingTextView, model rawModel: String) {
            let primary = NSColor(Theme.textPrimary)
            // Photos snap to their sentence end for DISPLAY (shared with the phone +
            // the Obsidian export): a mid-sentence marker lands on its own `\n\n` block
            // beneath the whole sentence, so the sentence reads intact and the photo no
            // longer shares a line with prose (killing the image-height caret). The
            // stored `sanitised` keeps the marker at its moment until an edit; the
            // transform is idempotent, so the no-op check in `updateNSView` holds.
            let model = BodyTransform.snappedImageBody(rawModel)
            hideTagSuggest()   // note switch / external change → the caret's run is gone
            // Synchronous: text + markers-as-text only — instant. Image disk-load +
            // thumbnailing (measured ~600ms EACH on the main thread, freezing the
            // note switch) is moved off-main below and spliced in when ready.
            let attributed = NSMutableAttributedString(
                string: model, attributes: [.font: BodyTextView.bodyFont, .foregroundColor: primary])
            tv.textStorage?.setAttributedString(attributed)
            spliceMemoLinkChips(tv)   // [[memo:UUID|Title]] → titled chip (model keeps the literal)
            spliceTaskBoxes(tv)       // "- [ ]"/"- [x]" → toggleable checkbox (Obsidian task syntax)
            lastKaraoke = nil   // new text → force the next karaoke recolor
            // Refresh the roster used to color person links / resolve unlink (injected people
            // for snapshots, else the live names DB). Per-render, not per-keystroke.
            peopleCache = parent.people.isEmpty ? NamesStore.shared.livePeople() : parent.people
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

        /// Replace every `[[memo:UUID|Title]]` with an atomic chip attachment showing
        /// the TITLE (the raw syntax/UUID never renders — the phone's chip idiom).
        /// Synchronous (pure drawing, no IO); `modelString` reconstructs the literal,
        /// so the model/export keep the exact syntax and deleting a chip deletes the
        /// whole link atomically.
        private func spliceMemoLinkChips(_ tv: SelfSizingTextView) {
            guard let storage = tv.textStorage else { return }
            let occs = MemoLinkSyntax.occurrences(in: storage.string)
            guard !occs.isEmpty else { return }
            let ns = storage.string as NSString
            storage.beginEditing()
            for occ in occs.reversed() {
                // Show the target's LIVE title (falls back to the frozen snapshot when the
                // target can't be resolved — deleted / other library), so a renamed note's
                // chips stay current instead of showing whatever title they were made with.
                let live = parent.linkTitle(occ.id)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let shown = (live?.isEmpty == false) ? live! : occ.title
                let att = MemoLinkChipAttachment(literal: ns.substring(with: occ.range),
                                                 linkID: occ.id, title: shown)
                storage.replaceCharacters(in: occ.range, with: NSAttributedString(attachment: att))
            }
            storage.endEditing()
        }

        /// Replace every line-start `- [ ]` / `- [x]` with a toggleable checkbox
        /// attachment (the phone's checklist idiom, shared `BodyTransform` syntax).
        /// A click flips the box and writes the flipped syntax back through the
        /// model — which persists AND rides the Part-B edit sync to the phone.
        private func spliceTaskBoxes(_ tv: SelfSizingTextView) {
            guard let storage = tv.textStorage else { return }
            let tasks = BodyTransform.pieces(of: storage.string).filter {
                if case .task = $0.segment { return true }; return false
            }
            guard !tasks.isEmpty else { return }
            storage.beginEditing()
            for piece in tasks.reversed() {
                guard case .task(let checked) = piece.segment else { continue }
                storage.replaceCharacters(in: piece.rawRange,
                                          with: NSAttributedString(attachment: TaskBoxAttachment(checked: checked)))
            }
            storage.endEditing()
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
            // Fonts reset every pass (headings/turn-headers/quote re-apply below) —
            // editing a heading line back to prose must drop its big font.
            storage.addAttribute(.font, value: BodyTextView.bodyFont, range: full)
            storage.removeAttribute(.backgroundColor, range: full)
            storage.removeAttribute(.underlineStyle, range: full)
            storage.removeAttribute(.underlineColor, range: full)
            storage.removeAttribute(.toolTip, range: full)
            styleLeadingQuote(storage)
            // Memo-link chips: hover names the target (the chip shows the title only).
            // Checked task lines: strike + mute the text after the box (Notes idiom).
            storage.removeAttribute(.strikethroughStyle, range: full)
            storage.enumerateAttribute(.attachment, in: full) { value, range, _ in
                if let chip = value as? MemoLinkChipAttachment {
                    storage.addAttribute(.toolTip, value: "Opens “\(chip.title)”", range: range)
                } else if let box = value as? TaskBoxAttachment {
                    storage.addAttribute(.toolTip,
                        value: box.checked ? "Done — click to reopen" : "Click to check off",
                        range: range)
                    guard box.checked else { return }
                    let ns = storage.string as NSString
                    let line = ns.lineRange(for: NSRange(location: range.location, length: 0))
                    let after = NSRange(location: NSMaxRange(range),
                                        length: max(0, NSMaxRange(line) - NSMaxRange(range)))
                    guard after.length > 0 else { return }
                    storage.addAttribute(.strikethroughStyle,
                                         value: NSUnderlineStyle.single.rawValue, range: after)
                    storage.addAttribute(.foregroundColor, value: NSColor(Theme.textMuted), range: after)
                }
            }
            // LINKED tier: a person `[[link]]` gets the accent-link color (#9d8ff7) + a
            // click-to-unlink hover tooltip; other wiki-links (places, etc.) keep the plain accent.
            if let rx = BodyTextView.linkRegex {
                let clickable = parent.onLinkedUnlink != nil
                for m in rx.matches(in: storage.string, range: full) {
                    var isPerson = false
                    if m.range.length > 4 {
                        let core = (storage.string as NSString)
                            .substring(with: NSRange(location: m.range.location + 2, length: m.range.length - 4))
                        if let p = person(matchingCore: core) {
                            isPerson = true
                            if clickable {
                                storage.addAttribute(.toolTip,
                                    value: "Linked to \(NamesMerge.keyName(p.canonical)) — click to unlink",
                                    range: m.range)
                            }
                        }
                    }
                    storage.addAttribute(.foregroundColor,
                        value: NSColor(isPerson ? Theme.nameLink : Theme.accent), range: m.range)
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
            // Markdown headings render as real TITLES (`# ` big, `## ` smaller) and
            // inline #tags accent — the WHAT comes from the shared `BodyMarkdown`
            // (one rule set with the phone), the LOOK is local. Characters stay
            // verbatim — the export is already markdown.
            let headingFaint = NSColor(Theme.textPrimary).withAlphaComponent(0.25)
            for h in BodyMarkdown.headings(in: storage.string) {
                let tier = min(h.level, BodyTextView.headingFonts.count) - 1
                storage.addAttribute(.font, value: BodyTextView.headingFonts[tier], range: h.text)
                storage.addAttribute(.foregroundColor, value: headingFaint, range: h.marks)
            }
            for r in BodyMarkdown.inlineTags(in: storage.string) {
                storage.addAttribute(.foregroundColor, value: NSColor(Theme.accent), range: r)
            }
            // SUGGESTED tier: tan text + a dotted underline (mocks/naming-review.html).
            let tan = NSColor(Theme.nameSuggest), line = NSColor(Theme.nameSuggestLine)
            for (_, r) in suggestedRanges(in: storage) {
                storage.addAttribute(.foregroundColor, value: tan, range: r)
                storage.addAttribute(.underlineStyle,
                    value: NSUnderlineStyle.single.rawValue | NSUnderlineStyle.patternDot.rawValue, range: r)
                storage.addAttribute(.underlineColor, value: line, range: r)
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

        /// Each `parent.suggested` occurrence (offset/length into the RAW
        /// `PipelineFile.sanitised`) mapped to its STORAGE range. The display SNAPS
        /// photos to their sentence end, so the raw offset is first mapped through the
        /// snap (`rawSnap`), then the attachment collapse (an 11-char `[[img_NNN]]`
        /// marker → 1 char). A stale offset (the body was hand-edited after sanitise,
        /// so `ambiguousNames` no longer lines up) is dropped — the storage text there
        /// must still read as the alias.
        func suggestedRanges(in storage: NSTextStorage) -> [(occ: AmbiguousOccurrence, range: NSRange)] {
            guard !parent.suggested.isEmpty else { return [] }
            let locs = attachmentModelLocs(storage)
            let rawSnap = BodyTransform.snapImages(parent.text)
            let ns = storage.string as NSString
            var out: [(AmbiguousOccurrence, NSRange)] = []
            for occ in parent.suggested {
                let snapOffset = rawSnap.snapped(rawLocation: occ.offset)
                let shift = locs.reduce(0) { $0 + ($1.loc < snapOffset ? $1.shift : 0) }
                let loc = snapOffset - shift
                guard loc >= 0, loc + occ.length <= ns.length else { continue }
                let r = NSRange(location: loc, length: occ.length)
                // Guard stale offsets: the span must still start with the alias.
                let sub = ns.substring(with: r)
                guard sub.range(of: occ.alias, options: [.caseInsensitive, .anchored]) != nil else { continue }
                out.append((occ, r))
            }
            return out
        }

        /// Model-string start location + storage-shift of each attachment, ascending.
        /// An image attachment stands for the 11-char `[[img_NNN]]` marker (shift 10);
        /// a memo-link chip stands for its variable-length literal (shift len-1).
        private func attachmentModelLocs(_ storage: NSTextStorage) -> [(loc: Int, shift: Int)] {
            var locs: [(Int, Int)] = []
            var modelLoc = 0
            storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
                if value is ImageMarkerAttachment {
                    locs.append((modelLoc, 10)); modelLoc += 11
                } else if let chip = value as? MemoLinkChipAttachment {
                    let len = (chip.literal as NSString).length
                    locs.append((modelLoc, len - 1)); modelLoc += len
                } else if value is TaskBoxAttachment {
                    locs.append((modelLoc, 4)); modelLoc += 5   // "- [ ]" → one glyph
                } else {
                    modelLoc += range.length
                }
            }
            return locs
        }

        // MARK: - Click interaction (karaoke seek · suggested / linked name popovers)

        /// A single click at character `idx`. During karaoke it seeks the audio to the
        /// clicked word; otherwise a dotted SUGGESTED name opens the which-person popover and
        /// a LINKED `[[Name]]` opens the prune/fix popover. Returns true when handled.
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
            // Memo-link chip → open that memo in the detail pane (read-only v1).
            if let open = parent.onOpenMemoLink, idx < storage.length,
               let chip = storage.attribute(.attachment, at: idx, effectiveRange: nil) as? MemoLinkChipAttachment {
                open(chip.linkID)
                return true
            }
            // Checklist box → toggle: flip the attachment, write the flipped syntax
            // back through the model (persists + Part-B edit sync), restyle the line.
            if idx < storage.length,
               let box = storage.attribute(.attachment, at: idx, effectiveRange: nil) as? TaskBoxAttachment {
                storage.replaceCharacters(in: NSRange(location: idx, length: 1),
                                          with: NSAttributedString(attachment: TaskBoxAttachment(checked: !box.checked)))
                parent.text = modelString(tv)
                restyle(tv)
                tv.invalidateIntrinsicContentSize()
                return true
            }
            // SUGGESTED (dotted) name → the which-person popover (state 2). Checked first so a
            // suggestion inside a link-free span wins; a fresh names read keeps candidates current.
            if parent.onSuggestionPick != nil {
                for (occ, r) in suggestedRanges(in: storage)
                where NSLocationInRange(idx, r) || idx == NSMaxRange(r) {
                    peopleCache = NamesStore.shared.livePeople()
                    showSuggestionPopover(occ: occ, range: r, tv: tv)
                    return true
                }
            }
            // LINKED person `[[Name]]` → the prune/fix popover (state 3).
            if parent.onLinkedUnlink != nil {
                let text = storage.string
                for link in Sanitiser.linkOccurrences(in: text)
                where NSLocationInRange(idx, link.range) || idx == NSMaxRange(link.range) {
                    peopleCache = NamesStore.shared.livePeople()
                    guard let p = person(matchingCore: link.core) else { return false }   // place link etc. → caret
                    showLinkedPopover(link: link, person: p, tv: tv)
                    return true
                }
            }
            return false
        }

        /// State 2 — the which-person popover at a clicked dotted suggestion: pick a candidate
        /// (force-link), New person…, or Leave as plain text. Keyed on the suggestion's alias.
        private func showSuggestionPopover(occ: AmbiguousOccurrence, range: NSRange, tv: SelfSizingTextView) {
            let word = (tv.string as NSString).substring(with: range)
            presentPopover(SuggestionPopover(
                spoken: word,
                candidates: occ.candidates,
                onPick: { [weak self] c in self?.closePopover(); self?.parent.onSuggestionPick?(occ.alias, c.canonical) },
                onNew: { [weak self] in self?.closePopover(); self?.parent.onAddName(word) },
                onPlain: { [weak self] in self?.closePopover(); self?.parent.onSuggestionPlain?(occ.alias) }),
                at: range, in: tv)
        }

        /// State 3 — the prune/fix popover at a clicked linked `[[Name]]`: unlink (→ a dotted,
        /// re-promotable suggestion), change person…, open their note.
        private func showLinkedPopover(link: Sanitiser.BodyLink, person p: Person, tv: SelfSizingTextView) {
            let canonical = NamesMerge.keyName(p.canonical).trimmingCharacters(in: .whitespaces)
            // The alias a "change person" override keys on — the spoken word of a
            // `[[Canonical|spoken]]` link, else the person's spoken short.
            let parts = link.core.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            let alias = parts.count == 2 ? parts[1].trimmingCharacters(in: .whitespaces) : Sanitiser.spokenAlias(for: p)
            // "Change person" only makes sense among people who SHARE this name (the twins) —
            // the wrong-Jack → right-Jack fix. A distinctive name has no twin, so the list is
            // empty and the LinkedNamePopover hides the row entirely. Switching to an unrelated
            // person was nonsensical (and confusing), so it's gone.
            let myAliases = Set(p.aliases.map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
            let others = peopleCache
                .filter { other in
                    NamesMerge.keyName(other.canonical).caseInsensitiveCompare(canonical) != .orderedSame
                        && other.aliases.contains { myAliases.contains($0.trimmingCharacters(in: .whitespaces).lowercased()) }
                }
                .map { NamesMerge.keyName($0.canonical) }
                .sorted()
            presentPopover(LinkedNamePopover(
                person: canonical,
                others: others,
                canOpen: parent.onOpenNote != nil,
                onUnlink: { [weak self] in self?.closePopover(); self?.parent.onLinkedUnlink?(canonical) },
                onChange: { [weak self] newP in self?.closePopover(); self?.parent.onLinkedChange?(alias, "[[\(newP)]]") },
                onOpen: { [weak self] in self?.closePopover(); self?.parent.onOpenNote?(canonical) }),
                at: link.range, in: tv)
        }

        private func presentPopover(_ view: some View, at range: NSRange, in tv: SelfSizingTextView) {
            activePopover?.performClose(nil)
            let host = NSHostingController(rootView: view)
            host.sizingOptions = [.preferredContentSize]
            let pop = NSPopover()
            pop.contentViewController = host
            pop.behavior = .transient
            activePopover = pop
            pop.show(relativeTo: boundingRect(range, in: tv), of: tv, preferredEdge: .maxY)
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

        /// Reconstruct the model string: image attachments → `[[img_NNN]]`, memo-link
        /// chips → their literal `[[memo:UUID|Title]]`, rest verbatim.
        func modelString(_ tv: SelfSizingTextView) -> String {
            guard let storage = tv.textStorage else { return tv.string }
            var out = ""
            storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
                if let att = value as? ImageMarkerAttachment {
                    out += String(format: "[[img_%03d]]", att.imgNumber)
                } else if let chip = value as? MemoLinkChipAttachment {
                    out += chip.literal
                } else if let box = value as? TaskBoxAttachment {
                    out += BodyTransform.rawTask(checked: box.checked)
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
            let img = NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width) / 2, height: CGFloat(cg.height) / 2))
            return roundedCorners(img)
        }

        /// Clip an inline photo to soft rounded corners — reads better in the note body.
        private static func roundedCorners(_ image: NSImage) -> NSImage {
            let size = image.size
            guard size.width > 0, size.height > 0 else { return image }
            let radius = min(size.width, size.height) * 0.04
            let out = NSImage(size: size)
            out.lockFocus()
            let rect = NSRect(origin: .zero, size: size)
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
            image.draw(in: rect)
            out.unlockFocus()
            return out
        }
    }
}

/// State 2 (mocks/naming-review.html): click a dotted SUGGESTED name → which person? One
/// candidate (a recognised common-word name) reads "Link "Rose"?"; 2+ (the ambiguous twins)
/// read "Which "Jack"? · N people share this name". Plus New person… and Leave as plain text.
/// A memo the `[[` picker can link to (phone parity: id + title + a date subtitle).
struct MemoLinkCandidate: Identifiable, Equatable {
    let id: UUID
    let title: String
    let subtitle: String
}

/// The `[[` memo-link picker popover (phone `MemoLinkPickerSheet` parity, the Obsidian idiom):
/// a search field over titles + subtitles, most-recent first, picking inserts a chip. The search
/// field auto-focuses so you keep typing straight after `[[`.
struct MemoLinkPopover: View {
    let candidates: [MemoLinkCandidate]
    var onPick: (UUID, String) -> Void
    var onCancel: () -> Void
    @State private var query = ""
    @FocusState private var focused: Bool

    private var filtered: [MemoLinkCandidate] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return Array(candidates.prefix(50)) }
        return candidates.filter {
            $0.title.lowercased().contains(q) || $0.subtitle.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "link").font(.system(size: 11)).foregroundStyle(Theme.textMuted)
                TextField("Link a note…", text: $query)
                    .textFieldStyle(.plain).font(.system(size: 13)).focused($focused)
                    .onSubmit { if let first = filtered.first { onPick(first.id, first.title) } else { onCancel() } }
            }
            .padding(.horizontal, 4).padding(.bottom, 8)

            if filtered.isEmpty {
                Text("No notes match").font(.system(size: 11)).foregroundStyle(Theme.textMuted)
                    .padding(.leading, 2).padding(.vertical, 4)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(filtered) { c in
                            Button { onPick(c.id, c.title) } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(c.title.isEmpty ? "Untitled" : c.title)
                                        .font(.system(size: 12.5)).foregroundStyle(Theme.textPrimary)
                                        .lineLimit(1)
                                    if !c.subtitle.isEmpty {
                                        Text(c.subtitle).font(.system(size: 10.5)).foregroundStyle(Theme.textMuted)
                                            .lineLimit(1)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .padding(.horizontal, 6).padding(.vertical, 5)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
        .padding(11).frame(width: 300).background(Theme.surfaceHover)
        .onAppear { focused = true }
    }
}

struct SuggestionPopover: View {
    let spoken: String
    let candidates: [NameCandidate]
    var onPick: (NameCandidate) -> Void
    var onNew: () -> Void
    var onPlain: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(candidates.count > 1
                 ? "Which “\(spoken)”? · \(candidates.count) people share this name"
                 : "Link “\(spoken)”?")
                .font(.system(size: 11)).foregroundStyle(Theme.textMuted)
                .padding(.leading, 2).padding(.bottom, 8)
            ForEach(candidates, id: \.canonical) { c in
                NameRow(avatar: NameRow.initials(c.canonical), title: NameRow.clean(c.canonical),
                        tint: .accent) { onPick(c) }
            }
            Divider().overlay(Theme.hairline.opacity(0.08)).padding(.vertical, 6)
            NameRow(symbol: "plus", title: "New person…", tint: .muted, action: onNew)
            NameRow(symbol: "minus", title: "Leave as plain text", tint: .muted, action: onPlain)
        }
        .padding(11).frame(width: 270).background(Theme.surfaceHover)
    }
}

/// State 3 (mocks/naming-review.html): click a LINKED name → prune (unlink — it stays a
/// dotted, re-promotable suggestion), change person… (reveals the other people), or open
/// their note.
struct LinkedNamePopover: View {
    let person: String          // bare canonical, e.g. "Hendri van Niekerk"
    var others: [String] = []
    var canOpen: Bool = false
    var onUnlink: () -> Void
    var onChange: (String) -> Void
    var onOpen: () -> Void
    @State private var changing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(NameRow.initials(person)).font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.nameLink).frame(width: 22, height: 22)
                    .background(Theme.accent.opacity(0.2), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text("✓ this note is about").font(.system(size: 10.5, weight: .bold)).foregroundStyle(Theme.green)
                    Text(person).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.nameLink)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 2).padding(.bottom, 9)

            NameRow(symbol: "link.badge.minus", title: "Unlink — just a side-mention", tint: .primary, action: onUnlink)
            if !others.isEmpty {
                NameRow(symbol: "arrow.left.arrow.right", title: "Change person…", tint: .primary,
                        chevron: changing ? "chevron.down" : "chevron.right") { changing.toggle() }
                if changing {
                    ForEach(others.prefix(8), id: \.self) { o in
                        NameRow(avatar: NameRow.initials(o), title: o, tint: .accent, indented: true) { onChange(o) }
                    }
                }
            }
            if canOpen {
                let first = person.split(separator: " ").first.map(String.init) ?? person
                NameRow(symbol: "arrow.up.forward", title: "Open \(first)’s note", tint: .primary, action: onOpen)
            }
        }
        .padding(11).frame(width: 266).background(Theme.surfaceHover)
    }
}

/// One popover row: an avatar (initials) OR an SF Symbol, a title, an optional chevron.
private struct NameRow: View {
    enum Tint { case accent, primary, muted }
    var avatar: String? = nil
    var symbol: String? = nil
    let title: String
    var tint: Tint = .primary
    var chevron: String? = nil
    var indented = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Group {
                    if let avatar {
                        Text(avatar).font(.system(size: 9.5, weight: .bold)).foregroundStyle(Theme.nameLink)
                            .frame(width: 20, height: 20).background(Theme.accent.opacity(0.22), in: Circle())
                    } else if let symbol {
                        Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(color).frame(width: 20, height: 20)
                            .background(Theme.hairline.opacity(0.06), in: Circle())
                    }
                }
                Text(title).font(.system(size: 12.5)).foregroundStyle(color)
                Spacer(minLength: 4)
                if let chevron { Image(systemName: chevron).font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.textMuted) }
            }
            .padding(.leading, indented ? 18 : 8).padding(.trailing, 8).padding(.vertical, 5.5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var color: Color {
        switch tint { case .accent: return Theme.nameLink; case .primary: return Theme.textPrimary; case .muted: return Theme.textMuted }
    }

    static func clean(_ canonical: String) -> String {
        canonical.replacingOccurrences(of: "[[", with: "").replacingOccurrences(of: "]]", with: "")
    }
    static func initials(_ canonical: String) -> String {
        let chars = clean(canonical).split(separator: " ").prefix(2).compactMap(\.first)
        return chars.isEmpty ? "?" : String(chars).uppercased()
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

/// A checklist checkbox standing in for a line-start `- [ ]` / `- [x]` (the shared
/// `BodyTransform` task syntax). One storage char; `modelString` reconstructs the
/// raw prefix, so a toggle is a real text edit that exports + syncs.
final class TaskBoxAttachment: NSTextAttachment {
    let checked: Bool

    init(checked: Bool) {
        self.checked = checked
        super.init(data: nil, ofType: nil)
        let img = Self.boxImage(checked: checked)
        image = img
        bounds = CGRect(x: 0, y: -3.5, width: img.size.width, height: img.size.height)
    }

    required init?(coder: NSCoder) { self.checked = false; super.init(coder: coder) }

    private static func boxImage(checked: Bool) -> NSImage {
        let size = NSSize(width: 17, height: 17)
        return NSImage(size: size, flipped: false) { rect in
            let box = NSBezierPath(roundedRect: rect.insetBy(dx: 1.5, dy: 1.5), xRadius: 4.5, yRadius: 4.5)
            if checked {
                NSColor(Theme.accent).setFill(); box.fill()
                let check = NSBezierPath()
                check.move(to: NSPoint(x: 5, y: 8.6))
                check.line(to: NSPoint(x: 7.4, y: 6.2))
                check.line(to: NSPoint(x: 12.2, y: 11.2))
                NSColor.white.setStroke()
                check.lineWidth = 1.8; check.lineCapStyle = .round; check.lineJoinStyle = .round
                check.stroke()
            } else {
                NSColor(Theme.textMuted).withAlphaComponent(0.55).setStroke()
                box.lineWidth = 1.4; box.stroke()
            }
            return true
        }
    }
}

/// A memo↔memo link rendered as an atomic titled chip (the phone's idiom — the raw
/// `[[memo:UUID|Title]]` never shows). Remembers its LITERAL so `modelString`
/// reconstructs the exact syntax; one storage char, so deleting it removes the whole
/// link and the caret can't land inside the UUID.
final class MemoLinkChipAttachment: NSTextAttachment {
    let literal: String
    let linkID: UUID
    let title: String

    init(literal: String, linkID: UUID, title: String) {
        self.literal = literal
        self.linkID = linkID
        self.title = title
        super.init(data: nil, ofType: nil)
        let img = Self.chipImage(title: title.isEmpty ? "Untitled" : title)
        image = img
        // Sit the chip on the text baseline (slight descend so it optically centers
        // in a 16pt body line).
        bounds = CGRect(x: 0, y: -5, width: img.size.width, height: img.size.height)
    }

    required init?(coder: NSCoder) {
        self.literal = ""; self.linkID = UUID(); self.title = ""
        super.init(coder: coder)
    }

    /// The chip: rounded accent-tinted capsule, 🗒 + title (mock panel 3's idiom).
    private static func chipImage(title: String) -> NSImage {
        let font = NSFont.systemFont(ofSize: 12.5, weight: .medium)
        let label = "🗒 \(title)" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: NSColor(Theme.nameLink),
        ]
        let tsize = label.size(withAttributes: attrs)
        let padH: CGFloat = 8
        let size = NSSize(width: ceil(tsize.width) + padH * 2, height: 21)
        return NSImage(size: size, flipped: false) { rect in
            let accent = NSColor(Theme.nameLink)
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
            accent.withAlphaComponent(0.13).setFill(); path.fill()
            accent.withAlphaComponent(0.35).setStroke(); path.lineWidth = 1; path.stroke()
            label.draw(at: NSPoint(x: padH, y: (rect.height - tsize.height) / 2), withAttributes: attrs)
            return true
        }
    }
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
