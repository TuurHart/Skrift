import SwiftUI
import AppKit
import ImageIO

/// Editable note body with live `[[wiki link]]` accent styling, inline image
/// thumbnails for `[[img_NNN]]` markers, AND R3 inline name disambiguation — an
/// NSTextView bridge (SwiftUI's TextEditor can't do any of these). Self-sizing (no
/// internal scroll; the surrounding SwiftUI ScrollView scrolls). The MODEL string
/// always keeps the literal `[[img_NNN]]` markers + `[[brackets]]` (WYSIWYG to the
/// exported markdown); the text view shows a thumbnail in the marker's place via a
/// custom attachment, and the marker is reconstructed from that attachment whenever
/// the user edits.
///
/// R3: when a `resolver` is attached (the note has ambiguous names), each plain
/// mention of an ambiguous alias is marked (dotted accent underline + tint) and
/// single-clicking it opens a candidate popover anchored at the word. Resolution is
/// per-occurrence by nature — two friends named "Jack" are set independently.
struct BodyTextView: NSViewRepresentable {
    @Binding var text: String
    /// Resolves an image marker number (`[[img_NNN]]`) to its file URL. Defaults to
    /// none (markers stay as styled text).
    var imageURL: (Int) -> URL? = { _ in nil }
    /// Called when the user right-clicks a text selection → "Add … as a name".
    var onAddName: (String) -> Void = { _ in }
    /// Inline name-disambiguation state, or nil when the note has no ambiguous names.
    var resolver: InlineResolverModel? = nil
    /// Karaoke playback, or nil when not playing. Applied as an in-place recolor on
    /// THIS text view (no renderer swap → no reflow) + click-a-word-to-seek.
    var karaoke: KaraokePlayback? = nil

    /// How far through the body's words to brighten (0…1) + a click-a-word → seek
    /// callback (arg = the clicked word's 0…1 position).
    struct KaraokePlayback {
        var fraction: Double
        var seek: (Double) -> Void
    }

    fileprivate static let bodyFont = NSFont.systemFont(ofSize: 16)
    fileprivate static let markerRegex = try? NSRegularExpression(pattern: #"\[\[img_(\d+)\]\]"#)
    fileprivate static let linkRegex = try? NSRegularExpression(pattern: #"\[\[[^\]]+\]\]"#)

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
        // Single-click on an ambiguous mention → resolve it (suppress cursor placement).
        tv.onSingleClickAt = { [weak coordinator = context.coordinator, weak tv] idx in
            guard let coordinator, let tv else { return false }
            return coordinator.handleClick(idx, tv)
        }
        context.coordinator.render(tv, model: text)
        context.coordinator.registerJump(tv)
        return tv
    }

    func updateNSView(_ tv: SelfSizingTextView, context: Context) {
        // SwiftUI REUSES this NSView across note switches, so refresh the
        // coordinator's parent — otherwise its `text` binding write-back, `imageURL`
        // resolver, and `resolver` model stay bound to the first note shown.
        context.coordinator.parent = self
        context.coordinator.registerJump(tv)
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
            // render() already restyled; otherwise the resolver/decisions or text may
            // have changed (or we're leaving karaoke) — restyle in place.
            if !textChanged { context.coordinator.restyle(tv) }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: BodyTextView
        private var activePopover: NSPopover?
        /// Last applied karaoke boundary, so the ~20 Hz playback ticks skip a recolor
        /// unless the active-word count actually moved (cheap even on long notes).
        private var lastKaraoke: (active: Int, count: Int)?
        init(_ parent: BodyTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? SelfSizingTextView else { return }
            parent.text = modelString(tv)   // attachments → [[img_NNN]] markers
            restyle(tv)                      // in-place recolor + ambiguous marks (keeps attachments + caret)
            tv.invalidateIntrinsicContentSize()
        }

        /// Inject "Add … as a name" into the right-click menu when there's a short
        /// text selection — the reliable, user-driven way to grow the names graph
        /// (no flaky auto-detection; you pick the exact words).
        func textView(_ view: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
            let r = view.selectedRange()
            let ns = view.string as NSString
            if r.length > 0, r.location + r.length <= ns.length {
                let sel = ns.substring(with: r).trimmingCharacters(in: .whitespacesAndNewlines)
                if !sel.isEmpty, sel.count <= 60 {
                    let item = NSMenuItem(title: "Add “\(sel)” as a name", action: #selector(addNameAction(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = sel
                    menu.insertItem(item, at: 0)
                    menu.insertItem(.separator(), at: 1)
                }
            }
            return menu
        }

        @objc private func addNameAction(_ sender: NSMenuItem) {
            if let sel = sender.representedObject as? String { parent.onAddName(sel) }
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
            if let rx = BodyTextView.linkRegex {
                for m in rx.matches(in: storage.string, range: full) {
                    storage.addAttribute(.foregroundColor, value: NSColor(Theme.accent), range: m.range)
                }
            }
            markAmbiguous(storage)
            storage.endEditing()
        }

        /// Mark each plain ambiguous mention: undecided → dotted accent underline +
        /// tint; resolved-to-person → accent + faint tint + a tooltip of who; resolved
        /// to plain → no mark (it's just a word now).
        private func markAmbiguous(_ storage: NSTextStorage) {
            guard let resolver = parent.resolver else { return }
            let text = storage.string
            let accent = NSColor(Theme.accent)
            let undecidedBG = accent.withAlphaComponent(0.14)
            let decidedBG = accent.withAlphaComponent(0.10)
            let underline = accent.withAlphaComponent(0.65)
            let dotted = NSUnderlineStyle([.single, .patternDot]).rawValue
            var observed = 0
            for alias in resolver.candidatesByAlias.keys {
                for range in Sanitiser.plainOccurrences(of: alias, in: text) where NSMaxRange(range) <= storage.length {
                    observed += 1
                    switch resolver.decisions[range.location] {
                    case .none:
                        storage.addAttribute(.backgroundColor, value: undecidedBG, range: range)
                        storage.addAttribute(.underlineStyle, value: dotted, range: range)
                        storage.addAttribute(.underlineColor, value: underline, range: range)
                    case .some(.person(let c)):
                        storage.addAttribute(.foregroundColor, value: accent, range: range)
                        storage.addAttribute(.backgroundColor, value: decidedBG, range: range)
                        storage.addAttribute(.toolTip, value: clean(c.canonical), range: range)
                    case .some(.plain):
                        break   // resolved → render as normal text
                    }
                }
            }
            // Report the true occurrence count so the banner total is exact. Defer the
            // write so we don't mutate the @Observable during a SwiftUI view update.
            if resolver.observedTotal != observed {
                DispatchQueue.main.async { resolver.observedTotal = observed }
            }
        }

        // MARK: - Inline resolver interaction

        /// A single click at character `idx`. During karaoke it seeks the audio to the
        /// clicked word; otherwise, if it's on an ambiguous mention, it opens the
        /// candidate popover. Returns true when handled (suppresses cursor placement).
        func handleClick(_ idx: Int, _ tv: SelfSizingTextView) -> Bool {
            // Karaoke: click a word → seek there (the old behavior the user missed).
            if let k = parent.karaoke, let storage = tv.textStorage {
                let words = Coordinator.wordRanges(storage.string)
                if let wi = words.firstIndex(where: { NSLocationInRange(idx, $0) || idx == NSMaxRange($0) }) {
                    k.seek(words.count > 1 ? Double(wi) / Double(words.count - 1) : 0)
                    return true
                }
                return false
            }
            guard let resolver = parent.resolver, let storage = tv.textStorage else { return false }
            let text = storage.string
            for alias in resolver.candidatesByAlias.keys {
                for range in Sanitiser.plainOccurrences(of: alias, in: text)
                where NSLocationInRange(idx, range) || idx == NSMaxRange(range) {
                    showPopover(aliasLower: alias, range: range, tv: tv, resolver: resolver, text: text)
                    return true
                }
            }
            return false
        }

        private func showPopover(aliasLower: String, range: NSRange, tv: SelfSizingTextView,
                                 resolver: InlineResolverModel, text: String) {
            activePopover?.performClose(nil)
            let ns = text as NSString
            let beforeLen = min(38, range.location)
            let before = ns.substring(with: NSRange(location: range.location - beforeLen, length: beforeLen))
            let afterStart = NSMaxRange(range)
            let after = ns.substring(with: NSRange(location: afterStart, length: min(38, ns.length - afterStart)))
            let display = resolver.displayAlias[aliasLower] ?? aliasLower
            let cands = resolver.candidatesByAlias[aliasLower] ?? []
            let current = resolver.decisions[range.location]
            let loc = range.location

            let view = ResolverPopover(alias: display, contextBefore: before, contextAfter: after,
                                       candidates: cands, current: current) { [weak self, weak tv] choice in
                resolver.decisions[loc] = choice
                self?.activePopover?.performClose(nil)
                self?.activePopover = nil
                if let tv { self?.restyle(tv) }
            }
            let host = NSHostingController(rootView: view)
            host.sizingOptions = [.preferredContentSize]
            let pop = NSPopover()
            pop.contentViewController = host
            pop.behavior = .transient
            activePopover = pop
            pop.show(relativeTo: boundingRect(range, in: tv), of: tv, preferredEdge: .maxY)
        }

        /// Hook the banner's "jump to next" up to this text view: scroll the first
        /// undecided mention (reading order, across aliases) into view + open it.
        /// Deferred so we never mutate the @Observable model mid SwiftUI update.
        func registerJump(_ tv: SelfSizingTextView) {
            guard let resolver = parent.resolver, resolver.jumpHandler == nil else { return }
            DispatchQueue.main.async { [weak self, weak tv] in
                guard let self, let tv, let resolver = self.parent.resolver, resolver.jumpHandler == nil else { return }
                resolver.jumpHandler = self.makeJump(tv)
            }
        }

        private func makeJump(_ tv: SelfSizingTextView) -> () -> Void {
            { [weak self, weak tv] in
                guard let self, let tv, let resolver = self.parent.resolver, let storage = tv.textStorage else { return }
                let text = storage.string
                var first: (alias: String, range: NSRange)?
                for alias in resolver.candidatesByAlias.keys {
                    for range in Sanitiser.plainOccurrences(of: alias, in: text)
                    where resolver.decisions[range.location] == nil {
                        if first == nil || range.location < first!.range.location { first = (alias, range) }
                    }
                }
                guard let next = first else { return }
                tv.scrollRangeToVisible(next.range)
                self.showPopover(aliasLower: next.alias, range: next.range, tv: tv, resolver: resolver, text: text)
            }
        }

        private func boundingRect(_ range: NSRange, in tv: SelfSizingTextView) -> NSRect {
            guard let lm = tv.layoutManager, let tc = tv.textContainer else { return .zero }
            let g = lm.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var r = lm.boundingRect(forGlyphRange: g, in: tc)
            r.origin.x += tv.textContainerOrigin.x
            r.origin.y += tv.textContainerOrigin.y
            return r
        }

        private func clean(_ canonical: String) -> String {
            canonical.replacingOccurrences(of: "[[", with: "").replacingOccurrences(of: "]]", with: "")
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

    override var intrinsicContentSize: NSSize {
        guard let layoutManager, let textContainer else { return super.intrinsicContentSize }
        layoutManager.ensureLayout(for: textContainer)
        let height = layoutManager.usedRect(for: textContainer).height + textContainerInset.height * 2
        return NSSize(width: NSView.noIntrinsicMetric, height: max(height, 60))
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
