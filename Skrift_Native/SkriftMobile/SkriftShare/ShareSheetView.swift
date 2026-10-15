import SwiftUI
import UIKit

/// What the share sheet knows about who sent the share (C123, D37): whether to offer the From
/// row (a share from a chat), the name remembered for that chat, and the roster names that
/// autocomplete it.
struct ShareSenderContext {
    var offered = false
    var initialName: String? = nil
    var roster: [ShareRosterName] = []
    /// Chat hint key → remembered name (labels the suggestions, "WhatsApp: Marta").
    var remembered: [String: String] = [:]

    static let none = ShareSenderContext()
}

/// The share sheet (Q464, signed mock `mocks/Q455-share-sheet.html`, option A).
///
/// The calm sheet fills the system sheet in the app's own look and follows light/dark:
///   - nav bar: ✕ top left, "Skrift", Save top right (turns green "Saved" on save);
///   - the item card (what is coming in, then the typed thought where one is offered);
///   - a Settings-style card BELOW it: "Rating" with the pill on the right, and "From" (who
///     sent it, roster autocomplete) on a share from a chat;
///   - a grey footer saying what happens; after Save it becomes the green receipt, the cards
///     dim, and the host closes the sheet after 0.9 s.
///
/// Save builds the `CaptureInboxEntry`s and hands them to `onSave`, which writes them and
/// answers whether that worked (a failure is the host's error screen).
struct ShareSheetView: View {
    let payload: SharePayload
    var sender: ShareSenderContext = .none
    /// Entries to write (1 for everything except audio-split, where each clip becomes its own
    /// entry) + the image datas aligned to `imageFileNames`. Returns true when written.
    let onSave: (_ entries: [CaptureInboxEntry], _ imageDatas: [Data]) -> Bool
    let onCancel: () -> Void

    @State private var annotation: String = ""
    @State private var significance: Double = 0
    @State private var senderName: String = ""
    @State private var saved = false
    @State private var toast: RatingToast?
    @State private var menuHeight: CGFloat = 0
    @FocusState private var focus: Field?
    private enum Field { case thought, sender }
    /// B1 chooser: N shared voice notes → one note (default, clips merged in order) or N notes.
    @State private var combineIntoOne = true
    /// E2 audio-length routing: a clip ≥ 1 hour defaults to the Books tab (read-along).
    @State private var sendToBooks = false
    /// Q355 (D195): a web link guessed as an article asks "Article or Note", Article pre-picked.
    /// Article hides the thought and the rating (a source has neither).
    @State private var pickedArticle = true

    private var linkGuess: ArticleLinkGuess {
        payload.type == .url && !payload.isAudio && !payload.isVideo ? ArticleLinkGuess.guess(payload.url) : .unchanged
    }
    private var toLibrary: Bool { linkGuess == .article && pickedArticle }
    private var hasLongClip: Bool { LongAudioRoute.needsOffer(durations: payload.audioItems.map(\.duration)) }
    private var toBooks: Bool { hasLongClip && sendToBooks }
    /// B3: photos and/or chat text arrived WITH the voice notes — one note takes everything.
    private var isMixedBundle: Bool {
        payload.isAudio && (!payload.imageItems.isEmpty || payload.text?.isEmpty == false)
    }
    /// Audio shares carry no thought (C66): the voice note IS the content.
    private var offersThought: Bool { !payload.isAudio && !toLibrary }
    private var offersRating: Bool { !toLibrary }
    private var offersSender: Bool { sender.offered && offersRating && !toBooks }

    var body: some View {
        VStack(spacing: 0) {
            ShareNavBar {
                Button { onCancel() } label: {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .semibold))
                }
                .buttonStyle(ShareNavButtonStyle(kind: .glass, iconOnly: true))
                .accessibilityLabel("Close")
                .accessibilityIdentifier("share-sheet-dismiss")
                .disabled(saved)
            } trailing: {
                saveButton
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    itemCard.dimmed(saved)
                    if offersRating { rowsCard.dimmed(saved).zIndex(1) }
                    if saved {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark").font(.system(size: 14, weight: .bold))
                            Text("Saved. Skrift opens on it next time.")
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.skGreen)
                        .padding(.horizontal, 16).padding(.top, 4)
                        .accessibilityIdentifier("share-saved-receipt")
                    } else {
                        ShareFooter(text: footerText)
                            .accessibilityIdentifier("share-sheet-footer")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Color.skBg.ignoresSafeArea())
        .onAppear {
            if hasLongClip { sendToBooks = true }
            if let name = sender.initialName { senderName = name }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focus = nil }.font(.system(size: 14, weight: .semibold))
            }
        }
    }

    // MARK: - Nav bar

    private var saveLabel: String {
        if toLibrary || toBooks { return "Add" }
        return "Save"
    }

    @ViewBuilder private var saveButton: some View {
        if saved {
            Button {} label: {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark").font(.system(size: 14, weight: .bold))
                    Text("Saved")
                }
            }
            .buttonStyle(ShareNavButtonStyle(kind: .done))
            .accessibilityIdentifier("capture-saved-button")
        } else {
            Button { saveTapped() } label: { Text(saveLabel) }
                .buttonStyle(ShareNavButtonStyle(kind: .primary))
                .accessibilityIdentifier("capture-save-button")
        }
    }

    // MARK: - Item card

    private var itemCard: some View {
        ShareCard {
            preview
            if offersThought {
                ShareRowSeparator()
                thoughtField
            }
        }
    }

    @ViewBuilder private var preview: some View {
        if payload.isAudio {
            if payload.audioItems.count > 1 { clipRows } else { audioRow }
            if !payload.imageItems.isEmpty {
                ShareRowSeparator()
                pictures.padding(12)
            }
            if let text = payload.text, !text.isEmpty {
                ShareRowSeparator()
                quote(text)
            }
            if hasLongClip {
                ShareRowSeparator()
                segmented(LongAudioRoute.audiobook.title, LongAudioRoute.voiceNote.title,
                          first: $sendToBooks, ids: ("capture-choice-books", "capture-choice-memo"))
            }
            if AudioImportChoice.needsChoice(clipCount: payload.audioItems.count), !toBooks, !isMixedBundle {
                ShareRowSeparator()
                segmented(AudioImportChoice.oneNote.title(clipCount: payload.audioItems.count),
                          AudioImportChoice.separateNotes.title(clipCount: payload.audioItems.count),
                          first: $combineIntoOne, ids: ("capture-choice-combine", "capture-choice-split"))
            }
        } else if payload.isVideo {
            videoPoster
        } else {
            switch payload.type {
            case .url:
                linkRow
                if linkGuess == .article {
                    ShareRowSeparator()
                    segmented("Article", "Note", first: $pickedArticle,
                              ids: ("capture-choice-article", "capture-choice-note"))
                }
            case .text:
                if let subject = payload.urlTitle, !subject.isEmpty {
                    itemRow(glyph: "envelope", tint: .skAccent, title: subject, subtitle: "Email")
                    ShareRowSeparator()
                }
                quote(payload.text ?? "")
            case .image:
                pictures
            case .file:
                itemRow(glyph: "doc.fill", tint: .skAccent, title: payload.fileName ?? "Document",
                        subtitle: docSubtitle)
                    .accessibilityIdentifier("capture-doc-card")
            }
        }
    }

    /// One item row: 44 pt glyph tile, 17 pt semibold title, 15 pt grey second line.
    private func itemRow(glyph: String, tint: Color, title: String, subtitle: String?,
                         titleLines: Int = 1) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.skElev)
                .frame(width: 44, height: 44)
                .overlay(Image(systemName: glyph).font(.system(size: 19, weight: .medium)).foregroundStyle(tint))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.skText)
                    .lineLimit(titleLines)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.skTextDim)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private var audioRow: some View {
        let item = payload.audioItems.first
        var parts: [String] = []
        if let d = item?.duration, d >= 1 { parts.append(fmtDuration(d)) }
        parts.append("shared \(Date().formatted(date: .omitted, time: .shortened))")
        return itemRow(glyph: "waveform", tint: .skAccent, title: "Voice note", subtitle: parts.joined(separator: " · "))
            .accessibilityIdentifier("capture-audio-card")
    }

    /// Multi-audio: every incoming clip, oldest → newest, scrollable past five rows.
    private var clipRows: some View {
        let items = payload.audioItems
        let known = items.compactMap(\.duration)
        let total = known.isEmpty ? nil : fmtDuration(known.reduce(0, +))
        return VStack(alignment: .leading, spacing: 0) {
            itemRow(glyph: "waveform", tint: .skAccent, title: "\(items.count) voice notes",
                    subtitle: [total, "oldest → newest"].compactMap { $0 }.joined(separator: " · "))
            ShareRowSeparator()
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                        HStack(spacing: 10) {
                            Text("\(i + 1)")
                                .font(.system(size: 13, weight: .medium).monospacedDigit())
                                .foregroundStyle(Color.skTextFaint)
                                .frame(width: 18, alignment: .trailing)
                            Text("Voice note").font(.system(size: 15)).foregroundStyle(Color.skText)
                            Spacer(minLength: 6)
                            Text(clipLabel(item))
                                .font(.system(size: 15).monospacedDigit())
                                .foregroundStyle(Color.skTextDim)
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 40)
                        if i < items.count - 1 { ShareRowSeparator() }
                    }
                }
            }
            .frame(maxHeight: 200)
        }
        .accessibilityIdentifier("capture-clip-stack")
    }

    private func clipLabel(_ item: SharedAudioItem) -> String {
        var parts: [String] = []
        if let at = item.recordedAt { parts.append(at.formatted(date: .omitted, time: .shortened)) }
        if let d = item.duration, d >= 1 { parts.append(fmtDuration(d)) }
        return parts.joined(separator: " · ")
    }

    private var videoPoster: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                Rectangle().fill(Color.skElev).frame(height: 214)
                    .overlay(
                        Circle().fill(.white.opacity(0.85)).frame(width: 52, height: 52)
                            .overlay(Image(systemName: "play.fill").font(.system(size: 20)).foregroundStyle(.black))
                    )
                if let d = payload.videoDuration {
                    Text(fmtDuration(d))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(.black.opacity(0.55), in: .rect(cornerRadius: 6))
                        .padding(10)
                }
            }
            Text(payload.videoFilmedAt.map { "Filmed \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "Video")
                .font(.system(size: 15))
                .foregroundStyle(Color.skTextDim)
                .padding(.horizontal, 16).padding(.vertical, 10)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("capture-video-card")
    }

    private var linkRow: some View {
        itemRow(glyph: "globe", tint: Color(red: 0.231, green: 0.510, blue: 0.965),
                title: payload.urlTitle ?? urlDomain ?? "Link", subtitle: urlDomain, titleLines: 2)
            .accessibilityIdentifier("capture-link-card")
    }

    /// A shared text: the accent bar + italic idiom (shared input never gets bubble chrome).
    private func quote(_ text: String) -> some View {
        HStack(spacing: 10) {
            Rectangle().fill(Color.skAccent.opacity(0.5)).frame(width: 2)
            Text(text)
                .font(.system(size: 15).italic())
                .foregroundStyle(Color.skTextDim)
                .lineLimit(6)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityIdentifier("capture-text-preview")
    }

    @ViewBuilder private var pictures: some View {
        let items = payload.imageItems
        if items.count > 1 {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)], spacing: 4) {
                ForEach(Array(items.prefix(4).enumerated()), id: \.offset) { i, item in
                    ZStack(alignment: .bottomTrailing) {
                        photo(item.data).frame(height: 112).clipped()
                        if i == 3, items.count > 4 {
                            Text("+\(items.count - 4)")
                                .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(.black.opacity(0.5), in: .capsule).padding(6)
                        }
                    }
                }
            }
            .accessibilityIdentifier("capture-photo-grid")
            .accessibilityLabel("\(items.count) photos, combined into one note")
        } else {
            photo(items.first?.data).frame(height: 230).clipped()
                .accessibilityIdentifier("capture-image-preview")
        }
    }

    @ViewBuilder private func photo(_ data: Data?) -> some View {
        if let data, let img = UIImage(data: data) {
            Color.clear.overlay(Image(uiImage: img).resizable().scaledToFill())
        } else {
            Rectangle().fill(Color.skElev)
                .overlay(Image(systemName: "photo").font(.system(size: 24)).foregroundStyle(Color.skTextFaint))
        }
    }

    private var thoughtField: some View {
        ZStack(alignment: .topLeading) {
            if annotation.isEmpty {
                Text("Add a thought")
                    .font(.system(size: 17))
                    .foregroundStyle(Color.skTextFaint)
                    .padding(.top, 12).padding(.leading, 16)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            TextEditor(text: $annotation)
                .font(.system(size: 17))
                .foregroundStyle(Color.skText)
                .tint(Color.skAccent)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 84, maxHeight: 160)
                .padding(.horizontal, 11)
                .padding(.vertical, 4)
                .focused($focus, equals: .thought)
                .accessibilityIdentifier("capture-annotation-field")
        }
    }

    /// A segmented control inside the card (Article / Note, One note / N notes, Audiobook / Voice note).
    private func segmented(_ a: String, _ b: String, first: Binding<Bool>, ids: (String, String)) -> some View {
        HStack(spacing: 2) {
            segment(a, on: first.wrappedValue, id: ids.0) { first.wrappedValue = true }
            segment(b, on: !first.wrappedValue, id: ids.1) { first.wrappedValue = false }
        }
        .padding(2)
        .background(Color.skElev, in: .rect(cornerRadius: 9, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func segment(_ title: String, on: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.skText)
                .frame(maxWidth: .infinity, minHeight: 32)
                .background(on ? Color.skSurface : .clear, in: .rect(cornerRadius: 7, style: .continuous))
                .shadow(color: on ? .black.opacity(0.12) : .clear, radius: 1.5, y: 1)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: - Rating + From (option A)

    private var rowsCard: some View {
        ShareCard {
            HStack(spacing: 12) {
                Text("Rating").font(.system(size: 17)).foregroundStyle(Color.skText)
                Spacer(minLength: 8)
                NoteRatingPill(value: Binding(get: { significance == 0 ? nil : significance },
                                              set: { significance = $0 ?? 0 }),
                               style: .phone,
                               onTap: { Haptics.tap(.light) },
                               onToast: { toast = $0 })
                    .overlay(alignment: .top) {
                        if let toast {
                            RatingToastView(toast: toast)
                                .fixedSize()
                                .offset(y: -38)
                                .allowsHitTesting(false)
                                .transition(.opacity)
                                .task(id: toast.id) {
                                    try? await Task.sleep(for: .seconds(1.6))
                                    if self.toast?.id == toast.id { withAnimation(SkMotion.snappy) { self.toast = nil } }
                                }
                        }
                    }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
            if offersSender {
                ShareRowSeparator()
                HStack(spacing: 12) {
                    Text("From").font(.system(size: 17)).foregroundStyle(Color.skText)
                    TextField("Who sent it?", text: $senderName)
                        .font(.system(size: 17))
                        .foregroundStyle(Color.skText)
                        .tint(Color.skAccent)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($focus, equals: .sender)
                        .accessibilityIdentifier("share-sender-field")
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 48)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if focus == .sender, !suggestions.isEmpty {
                // Hangs BELOW the From row (mock: top at the card's bottom − 4 pt). An offset
                // by the menu's own height; an alignment guide here was ignored on iOS 26.
                suggestionMenu
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { menuHeight = $0 }
                    .offset(y: menuHeight - 4)
                    .padding(.trailing, 16)
            }
        }
    }

    private var suggestions: [ShareSender.Suggestion] {
        ShareSender.suggestions(for: senderName, roster: sender.roster, remembered: sender.remembered)
    }

    private var suggestionMenu: some View {
        VStack(spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.offset) { i, s in
                if i > 0 { Rectangle().fill(ShareTheme.separator).frame(height: 0.5) }
                Button {
                    senderName = s.name
                    focus = nil
                } label: {
                    HStack(spacing: 12) {
                        Text(s.name).font(.system(size: 16)).foregroundStyle(Color.skText)
                        Spacer(minLength: 8)
                        Text(s.detail).font(.system(size: 12)).foregroundStyle(Color.skTextDim)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("share-sender-suggestion")
            }
        }
        .frame(minWidth: 190)
        .fixedSize()
        .background(Color.skSurface, in: .rect(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.skBorder, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 8)
    }

    // MARK: - Footer

    private var footerText: String {
        if payload.isAudio {
            if toBooks { return "Goes to Books for read-along. Skrift opens on it next time." }
            return "Transcribes on your iPhone. Skrift opens on it next time."
        }
        if payload.isVideo {
            if let bytes = payload.videoBytes, !VideoKeep.fits(byteCount: bytes) {
                return VideoKeep.shareCardLine(byteCount: bytes)
            }
            return "The audio becomes the note; the video stays in it and syncs through iCloud."
        }
        switch payload.type {
        case .url:
            switch linkGuess {
            case .article:
                return pickedArticle
                    ? "Goes to Library. Skrift saves the article text for offline reading; a page with no article text becomes a note instead."
                    : "Saves the link as a note."
            case .note(let kind):
                return "\(kind) → a note. Videos, posts and product pages save as notes, never to Library."
            case .unchanged:
                return "Saves the link as a note."
            }
        case .file:
            if CaptureInboxEntry.routesPDFToLibrary(displayName: payload.fileName, thought: thoughtOrSender,
                                                    significance: significance) {
                return "Goes to your Library. Type a thought or rate it to make it a note instead."
            }
            return payload.filePageCount != nil
                ? "Its text becomes searchable in Skrift. Skrift opens on it next time."
                : "Skrift opens on it next time."
        case .text, .image:
            return "Skrift opens on it next time."
        }
    }

    private var docSubtitle: String {
        var parts: [String] = []
        if let p = payload.filePageCount { parts.append(p == 1 ? "1 page" : "\(p) pages") }
        if let s = payload.fileSizeBytes { parts.append(ByteCountFormatter.string(fromByteCount: s, countStyle: .file)) }
        return parts.joined(separator: " · ")
    }

    private func fmtDuration(_ t: TimeInterval) -> String {
        let s = Int(t.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private var urlDomain: String? {
        guard let urlStr = payload.url, let url = URL(string: urlStr) else { return nil }
        return url.host?.replacingOccurrences(of: "www.", with: "")
    }

    // MARK: - Entries

    /// The typed thought, trimmed; nil when empty.
    private var trimmedThought: String? {
        let t = annotation.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// C123: the From row's name, roster-spelt; nil when empty or not offered.
    private var senderValue: String? {
        guard offersSender, let name = ShareSender.clean(senderName) else { return nil }
        return ShareSender.resolved(name, roster: sender.roster)
    }

    /// A sender says "this is a note" as much as a thought does (the PDF Library rule).
    private var thoughtOrSender: String? { trimmedThought ?? senderValue }

    /// "" = unknown date (the index-aligned arrays can't hold nil).
    private static func iso(_ date: Date?) -> String {
        date.map { ISO8601.string(from: $0) } ?? ""
    }

    /// The four index-aligned image arrays an entry carries. All nil when there are no images.
    private struct ImageColumns {
        let fileNames: [String]?
        let recordedAts: [String]?
        let originalNames: [String]?
        let selectionPositions: [Int]?

        init(_ items: [SharedImageItem]) {
            guard !items.isEmpty else {
                fileNames = nil; recordedAts = nil; originalNames = nil; selectionPositions = nil
                return
            }
            fileNames = items.map(\.fileName)
            recordedAts = items.map { ShareSheetView.iso($0.recordedAt) }
            originalNames = items.map { $0.originalName ?? "" }
            selectionPositions = items.enumerated().map { $0.element.selectionIndex ?? $0.offset }
        }
    }

    private func saveTapped() {
        focus = nil
        let ok: Bool
        if payload.isAudio {
            let (entries, imageDatas) = audioEntries()
            ok = onSave(entries, imageDatas)
        } else if let entry = videoEntry() {
            ok = onSave([entry], [])
        } else if let entry = fileEntry() {
            ok = onSave([entry], [])
        } else {
            ok = onSave([mediaEntry()], payload.imageItems.map(\.data))
        }
        if ok { withAnimation(.easeOut(duration: 0.2)) { saved = true } }
    }

    /// Combine (default) = ONE entry carrying every clip name in play order → one merged memo;
    /// split = one entry per clip → N memos.
    private func audioEntries() -> (entries: [CaptureInboxEntry], imageDatas: [Data]) {
        let items = payload.audioItems
        let imageItems = payload.imageItems
        let images = ImageColumns(imageItems)
        let sharedAt = ISO8601.string(from: Date())
        let from = toBooks ? nil : senderValue
        let rating = significance
        func entry(id: UUID, names: [String], clips: [SharedAudioItem]) -> CaptureInboxEntry {
            var e = CaptureInboxEntry(
                id: id, type: "audio", url: nil, urlTitle: nil,
                // B3: the bundle's chat text rides the entry → the memo's annotation.
                text: payload.text,
                imageFileName: nil, mimeType: nil, annotationText: nil,
                significance: rating, sharedAt: sharedAt,
                audioFileNames: names, audioRecordedAts: clips.map { Self.iso($0.recordedAt) },
                routeToBooks: toBooks ? true : nil,
                imageFileNames: images.fileNames,
                imageRecordedAts: images.recordedAts,
                audioOriginalNames: clips.map { $0.originalName ?? "" },
                audioSelectionPositions: clips.enumerated().map { $0.element.selectionIndex ?? $0.offset },
                imageOriginalNames: images.originalNames,
                imageSelectionPositions: images.selectionPositions
            )
            e.senderName = from
            return e
        }
        func ext(_ item: SharedAudioItem) -> String {
            item.url.pathExtension.isEmpty ? "m4a" : item.url.pathExtension
        }
        // A Books-routed share is always ONE entry (the parts of one book); a mixed bundle (B3)
        // is likewise always one note.
        if combineIntoOne || items.count == 1 || toBooks || isMixedBundle {
            let id = UUID()
            let names = items.enumerated().map { "audio_\(id.uuidString)_\($0.offset).\(ext($0.element))" }
            return ([entry(id: id, names: names, clips: items)], imageItems.map(\.data))
        }
        let entries = items.map { item -> CaptureInboxEntry in
            let id = UUID()
            return entry(id: id, names: ["audio_\(id.uuidString)_0.\(ext(item))"], clips: [item])
        }
        return (entries, [])
    }

    /// E1: video rides its own entry type — the typed thought + rating + sender travel with it.
    private func videoEntry() -> CaptureInboxEntry? {
        guard payload.isVideo, let videoURL = payload.videoURL else { return nil }
        let id = UUID()
        let ext = videoURL.pathExtension.isEmpty ? "mov" : videoURL.pathExtension
        var e = CaptureInboxEntry(
            id: id, type: "video", url: nil, urlTitle: nil, text: nil,
            imageFileName: nil, mimeType: nil,
            annotationText: trimmedThought,
            significance: significance, sharedAt: ISO8601.string(from: Date()),
            videoFileName: "video_\(id.uuidString).\(ext)"
        )
        e.senderName = senderValue
        return e
    }

    /// E1: documents likewise — the thought becomes the capture's body.
    private func fileEntry() -> CaptureInboxEntry? {
        guard payload.type == .file, let fileURL = payload.fileURL else { return nil }
        let id = UUID()
        let ext = fileURL.pathExtension.isEmpty ? "pdf" : fileURL.pathExtension
        var e = CaptureInboxEntry(
            id: id, type: "file", url: nil, urlTitle: nil, text: nil,
            imageFileName: nil, mimeType: payload.mimeType,
            annotationText: trimmedThought,
            significance: significance, sharedAt: ISO8601.string(from: Date()),
            fileName: "file_\(id.uuidString).\(ext)",
            fileDisplayName: payload.fileName,
            // Q354 / D126: a bare PDF goes to the Library tab, not into a new note.
            routeToLibrary: CaptureInboxEntry.routesPDFToLibrary(
                displayName: payload.fileName, thought: thoughtOrSender, significance: significance) ? true : nil
        )
        e.senderName = senderValue
        return e
    }

    /// URL / text / image(s): the generic capture entry.
    private func mediaEntry() -> CaptureInboxEntry {
        let imageItems = payload.imageItems
        let images = ImageColumns(imageItems)
        var e = CaptureInboxEntry(
            id: UUID(),
            type: payload.type.rawValue,
            url: payload.url,
            urlTitle: payload.urlTitle,
            text: payload.text,
            imageFileName: imageItems.first?.fileName,
            mimeType: payload.mimeType,
            // Q355: an article share carries no thought and no rating (the sheet hid both).
            annotationText: toLibrary ? nil : trimmedThought,
            significance: toLibrary ? 0 : significance,
            // C142: a shared email dates the note by its Date header.
            sharedAt: ISO8601.string(from: payload.sharedAt ?? Date()),
            imageFileNames: images.fileNames,
            imageRecordedAts: images.recordedAts,
            imageOriginalNames: images.originalNames,
            imageSelectionPositions: images.selectionPositions,
            routeToLibrary: toLibrary ? true : nil,
            emailAttachmentFileNames: payload.emailAttachments.isEmpty ? nil
                : payload.emailAttachments.indices.map { "emailatt_\($0)" },
            emailAttachmentNames: payload.emailAttachments.isEmpty ? nil : payload.emailAttachments.map(\.name)
        )
        e.senderName = toLibrary ? nil : senderValue
        return e
    }
}

private extension View {
    /// The receipt state: the fields dim and stop taking taps.
    func dimmed(_ on: Bool) -> some View {
        self.opacity(on ? 0.45 : 1).allowsHitTesting(!on)
    }
}
