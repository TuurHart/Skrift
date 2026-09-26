import SwiftUI

extension MemosListView {
    // MARK: - Toolbar

    /// ONE header line: "Notes" 30pt + Select · scan · filter inline right
    /// (mock notes-compact-header.html — the stock toolbar row above the large
    /// title was pure cost). The iOS-26 "second trailing toolbar item gets
    /// eaten" gotcha (build-35 probe) doesn't apply to a hand-rolled HStack,
    /// so doc-scan rejoins the actions cluster.
    /// iPad-regular header — the MAC's construction (signed mock A, section 0;
    /// Tuur: the Mac "just looks way better"): a compact identity line instead of
    /// the 30pt wordmark that sat too low, then the Mac sidebar's verb rows
    /// verbatim — Import · Record · ✎ across, Process N full-width below (the
    /// pile's size ON the button) — then search, the filter chips and the
    /// count/sort line. Compact width keeps the phone's own header below,
    /// untouched.
    /// D136 second pass: the iPad-regular identity row is now JUST the title +
    /// Select — the verb row, Process and the chips all moved out into
    /// `notesRoot` so the phone can share them at compact width too.
    var macStyleHeader: some View {
        HStack(spacing: 8) {
            // 22pt, hugging the top — "the notes title can be bigger, move
            // the whole notes bit up" (Tuur, live round b130).
            Text(SharedCopy.notesTitle)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color.skText)
            Spacer(minLength: 0)
            Button(editMode.isEditing ? "Done" : "Select") {
                withAnimation(Theme.Motion.snappy) {
                    if editMode.isEditing { editMode = .inactive; selected.removeAll() }
                    else { editMode = .active }
                }
            }
            .font(.system(size: 13))
            .tint(.skAccent)
            .accessibilityIdentifier("select-button")
        }
        // Clear the screen-pinned ◧ (14 + 30) and sit on the same 48pt line
        // as the note's chrome bar, so the button reads as belonging to this
        // header while the list is open (signed mock ipad-note-chrome-belongs).
        .padding(.leading, 34)
        .frame(height: 48)
        .padding(.horizontal, 14)
    }

    /// The Mac sidebar's verb row, ported whole and now shared by the PHONE too
    /// (D135/D136, Tuur: "just get the same ones… also unify that" — the phone
    /// gains this row and loses its corner FAB): Import (the picker chooser),
    /// Record, and the typed-note ✎ — the two verbs that BRING MATERIAL IN pair
    /// up with typing, the signed mocks mac-record-button.html option B +
    /// mac-new-note.html m2.
    var verbRow: some View {
        HStack(spacing: 7) {
            // Import IS the picker chooser now (Tuur: "when you click import
            // you should see if you want files or video from photos").
            Menu {
                Button { showMediaFileImporter = true } label: {
                    Label("Audio or video from Files", systemImage: "folder")
                }
                Button { showVideoImporter = true } label: {
                    Label("Video from Photos", systemImage: "photo.on.rectangle")
                }
                if DocScanView.isSupported {
                    Button { showDocScanner = true } label: {
                        Label("Scan a document", systemImage: "doc.viewfinder")
                    }
                }
            } label: {
                Label(SharedCopy.importVerb, systemImage: "plus")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color.skText)
                    // Q48/D145: "a bit small" (Tuur, b172) — was `.padding(.vertical, 7)`
                    // over ~16pt of content, ≈30pt tall. `minHeight: 44` is Apple's HIG
                    // tap-target floor, which this row was under; that floor (not the
                    // brief's ~20% guideline) is the binding number here.
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color.skElev, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .accessibilityIdentifier("ipad-import-button")

            // Start a take — the Mac's Record, same shape as Import (they are
            // the same verb family). D136: this replaces the phone's corner FAB
            // too now ("reaching up to record is not that bad").
            Button {
                intentBridge.clearPendingStart()
                LiveRecordingService.prestart()
                showRecord = true
            } label: {
                HStack(spacing: 6) {
                    Circle().fill(Color.skRed).frame(width: 9, height: 9)
                    Text("Record")
                }
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Color.skRed)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Color.skElev, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("ipad-record-button")
            .accessibilityLabel("Record a voice memo")

            // A typed note (the Mac's ✎/⌘N, mocks/mac-new-note.html m2):
            // Import and Record name their sources, typing is the third verb —
            // a quiet fixed-width chip, ⌘N on a hardware keyboard.
            Button { newTypedNote() } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.skText)
                    // Widened alongside the height (34 → 44) so the square stays a
                    // square, not a tall sliver next to the two wide buttons.
                    .frame(width: 44, height: 44)
                    .background(Color.skElev, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("n", modifiers: .command)
            .accessibilityIdentifier("ipad-new-note-button")
            .accessibilityLabel("New note")
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 2)
    }

    /// "Process N" — the Mac's button, ported whole: N is the pile a polisher
    /// would pick up (ProcessPile.waiting), and pressing it RUNS that pile here
    /// — full-width, like the Mac's. Regular width only (D136's mock: the phone
    /// has no Process row in the unified list).
    var processRow: some View {
        SwiftUI.Group {
            if PolishCenter.shared.isAvailable {
                if let run = PolishCenter.shared.pileRun {
                    Button { PolishCenter.shared.cancelPile() } label: {
                        HStack(spacing: 6) {
                            ProgressView(value: run.fraction)
                                .progressViewStyle(.linear)
                                .frame(width: 54)
                                .tint(.white)
                            Text(run.line)
                                .font(.system(size: 11.5, weight: .semibold))
                                .lineLimit(1)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(Color.skAccent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("ipad-process-pile-running")
                    .accessibilityLabel("\(run.line). Tap to stop.")
                } else {
                    Button { PolishCenter.shared.processPile(processPile) } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "play.fill").font(.system(size: 10, weight: .bold))
                            Text(SharedCopy.processVerb).font(.system(size: 12.5, weight: .semibold))
                            if !processPile.isEmpty {
                                Text("\(processPile.count)")
                                    .font(.system(size: 12, weight: .bold).monospacedDigit())
                                    .opacity(0.8)
                            }
                        }
                        .lineLimit(1)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(Color.skAccent.opacity(processPile.isEmpty ? 0.4 : 1),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(processPile.isEmpty)
                    .accessibilityIdentifier("ipad-process-pile-button")
                }
            }
        }
        .padding(.horizontal, 14)
    }

    /// Q66/D148 (option A, `mocks/Q49-one-filter.html`): the chip row carries
    /// EVERYTHING now. All / Needs Work / Done / Unrated (verbatim, one shared
    /// `QueueFilter`) come first, then Date and Unsynced past them, then a
    /// sort word ending the row (`MemoSort.short`/`.next`). The Filter icon,
    /// the Sort & Filter sheet's Sort/Unsynced sections and the sheet's
    /// separate "Not rated" toggle are gone — the toggle was the SAME set as
    /// the Unrated chip (BUGS §2: the phone filtered Unrated twice, together
    /// they emptied the list). The whole row scrolls sideways when it doesn't
    /// fit (a 390pt phone with a live date range, per the mock's own admission).
    var filterChips: some View {
        // Computed ONCE for the whole row, not per chip — `chipCounts` used to
        // be read as a property inside the ForEach, so its 3 corpus filters +
        // `enhancedMemoIDs` rebuild reran on each of the 4 chip iterations.
        let counts = chipCounts
        let chipStyle = ChipRowStyle(accent: .skAccent, dim: .skTextDim)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(QueueFilter.allCases, id: \.self) { chip in
                    let on = listChip == chip
                    HStack(spacing: 3) {
                        Text(chip.rawValue)
                        if let n = counts[chip] {
                            Text("\(n)").fontWeight(.semibold)
                        }
                    }
                    .font(.system(size: 11))
                    .lineLimit(1).fixedSize()
                    .foregroundStyle(on ? Color.skAccent : Color.skTextDim)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(on ? Color.skAccent.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .stroke(on ? Color.skAccent.opacity(0.22) : .clear, lineWidth: 1))
                    .contentShape(Rectangle())
                    // Q48/D145 (BUGS §3): this used to wrap the `listChip` write in
                    // `withAnimation`, which put the List's own ForEach/Section diff
                    // inside that animation transaction — SwiftUI then auto-animates
                    // each section's insert/remove individually (Needs Work flying up
                    // from the bottom, Done's headers arriving last), a different
                    // motion per chip. A plain (unanimated) write swaps the list
                    // instantly and identically every time — list identity stays the
                    // memo id via `Identifiable`, nothing here re-keys it. The pill
                    // highlight below still animates on its own, short and the same
                    // for every chip (`.animation(value: listChip)` on the row).
                    .onTapGesture { listChip = chip }
                    .accessibilityIdentifier("ipad-chip-\(chip.rawValue)")
                }
                ExtraFilterChip(label: filter.dateActive ? "Date · \(dateChipLabel)" : "Date",
                                active: filter.dateActive, style: chipStyle)
                    .onTapGesture { showDateFilter = true }
                    .accessibilityIdentifier("chip-date")
                ExtraFilterChip(label: "Unsynced", active: filter.unsyncedOnly, style: chipStyle)
                    .onTapGesture { filter.unsyncedOnly.toggle() }
                    .accessibilityIdentifier("chip-unsynced")
                SortCycleWord(word: sort.short, style: chipStyle) { sort = sort.next }
                    .accessibilityIdentifier("sort-cycle-word")
            }
            .padding(.horizontal, 16)
            .padding(.top, 2)
            .padding(.bottom, 4)
            // Scoped to this row ONLY — the highlight pill still gets one quick,
            // consistent motion on every chip switch. It does not reach the List
            // below (a sibling, not a descendant), so the row content swaps
            // instantly with no section-by-section animation.
            .animation(Theme.Motion.snappy, value: listChip)
        }
        .accessibilityIdentifier("filter-chip-scroll")
    }

    /// "22–25 Sep" / "from 22 Sep" / "to 25 Sep" — the Date chip's own label
    /// once a range is live (mock's `dateLabel`).
    var dateChipLabel: String {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        switch (filter.from, filter.to) {
        case let (from?, to?): return "\(f.string(from: from))–\(f.string(from: to))"
        case let (from?, nil): return "from \(f.string(from: from))"
        case let (nil, to?):   return "to \(f.string(from: to))"
        default:               return ""
        }
    }

    /// D135: "each chip counts its own notes" — over ALL live notes (not the
    /// filtered view), like the Mac's sidebar. `.all` carries no number.
    var chipCounts: [QueueFilter: Int] {
        let enhanced = enhancedMemoIDs
        return NotesListModel.chipCounts(
            needsWork: memos.filter { ProcessPile.matches(.needsWork, $0, enhancedIDs: enhanced) }.count,
            done: memos.filter { ProcessPile.matches(.done, $0, enhancedIDs: enhanced) }.count,
            notRated: ProcessPile.unrated(memos: memos).count)
    }

    /// The pile a polisher would pick up, by the shared rule. Built off ONE
    /// enhancements query rather than a fetch per memo (body-safe).
    var processPile: [Memo] {
        ProcessPile.waiting(memos: memos, enhancedIDs: enhancedMemoIDs)
    }

    var enhancedMemoIDs: Set<UUID> {
        Set(enhancements.lazy.filter(\.isProcessed).map(\.memoID))
    }

    /// memoID → the Mac's GENERATED title, off the same one query (never a fetch per row).
    /// Lets a row show a real title where the user hasn't chosen one, instead of falling
    /// through to the body — which is what made the list disagree with the detail screen.
    /// Built ONCE per render inside `derived` now (R92/C278) — was a computed
    /// property read per-row inside `ForEach`, rebuilding the whole dictionary N times.
    func enhancedTitleByMemoID() -> [UUID: String] {
        Dictionary(enhancements.lazy.compactMap { e -> (UUID, String)? in
            let t = e.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : (e.memoID, t)
        }, uniquingKeysWith: { a, _ in a })
    }

    /// D135/D136: the phone's header simplifies to JUST Notes + Select — Import,
    /// Scan and Filter all leave it (Import/Scan fold into the shared `verbRow`'s
    /// Import menu below; Filter moves into the chip bar's icon-only button).
    var headerRow: some View {
        HStack(spacing: 18) {
            ScreenTitle("Notes")
            Spacer(minLength: 0)
            Button(editMode.isEditing ? "Done" : "Select") {
                withAnimation(Theme.Motion.snappy) {
                    if editMode.isEditing { editMode = .inactive; selected.removeAll() }
                    else { editMode = .active }
                }
            }
            .font(.system(size: 16))
            .tint(.skAccent)
            .accessibilityIdentifier("select-button")
            // (The ⋯ shelf entry lived here 2026-07-18 → 2026-07-21. Q-placement
            // pick B, mocks/wayout-phone-placement.html: the conveyor's one home
            // is the Review feed now — same room as the Mac.)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }
}
