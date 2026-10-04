import SwiftUI

extension MemosListView {
    // MARK: - Toolbar

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
                // Q48/D145: minHeight 44 (HIG tap floor) lives in `VerbButtonStyle.phone`.
                ImportVerbLabel(style: .phone)
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
                RecordVerbLabel(title: SharedCopy.recordVerb, style: .phone)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("ipad-record-button")
            .accessibilityLabel("Record a voice memo")

            // A typed note (the Mac's ✎/⌘N, mocks/mac-new-note.html m2):
            // Import and Record name their sources, typing is the third verb —
            // a quiet fixed-width chip, ⌘N on a hardware keyboard.
            Button { newTypedNote() } label: {
                // Widened alongside the height (34 → 44) so the square stays a
                // square, not a tall sliver next to the two wide buttons.
                NewNoteVerbLabel(style: .phone)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(AppShortcuts.newNote)
            .accessibilityIdentifier("ipad-new-note-button")
            .accessibilityLabel(SharedCopy.newNoteLabel)
            .help(SharedCopy.newNoteTooltip)
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
                    let pile = processPile
                    Button { PolishCenter.shared.processPile(pile) } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "play.fill").font(.system(size: 10, weight: .bold))
                            Text(SharedCopy.processVerb).font(.system(size: 12.5, weight: .semibold))
                            if !pile.isEmpty {
                                Text("\(pile.count)")
                                    .font(.system(size: 12, weight: .bold).monospacedDigit())
                                    .opacity(0.8)
                            }
                        }
                        .lineLimit(1)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(Color.skAccent.opacity(pile.isEmpty ? 0.4 : 1),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(pile.isEmpty)
                    .accessibilityIdentifier("ipad-process-pile-button")
                }
            }
        }
        .padding(.horizontal, 14)
    }

    /// Q66/D148 (option A, `mocks/Q49-one-filter.html`): the chip row carries
    /// EVERYTHING now. All / Needs Work / Done / Unrated (verbatim, one shared
    /// `QueueFilter`) come first, then Date past them (D168: Unsynced is gone), then a
    /// sort word ending the row (`MemoSort.short`/`.next`). The Filter icon,
    /// the Sort & Filter sheet's Sort section and the sheet's
    /// separate "Not rated" toggle are gone — the toggle was the SAME set as
    /// the Unrated chip (BUGS §2: the phone filtered Unrated twice, together
    /// they emptied the list). The whole row scrolls sideways when it doesn't
    /// fit (a 390pt phone with a live date range, per the mock's own admission).
    var filterChips: some View {
        // Computed ONCE for the whole row, not per chip — `chipCounts` used to
        // be read as a property inside the ForEach, so its 3 corpus filters +
        // `enhancedMemoIDs` rebuild reran on each of the 4 chip iterations.
        let counts = chipCounts
        let chipStyle = ChipRowStyle.phone
        return VStack(spacing: 6) {
            HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(QueueFilter.allCases, id: \.self) { chip in
                    let on = listChip == chip
                    StatusChip(label: chip.rawValue, count: counts[chip], on: on, style: chipStyle)
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
                ExtraFilterChip(label: DateChipText.title(from: filter.from, to: filter.to),
                                active: filter.dateActive || showDateStrip, style: chipStyle)
                    .onTapGesture { showDateStrip.toggle() }
                    .accessibilityIdentifier("chip-date")
            }
            // Scoped to this row ONLY — the highlight pill still gets one quick,
            // consistent motion on every chip switch. It does not reach the List
            // below (a sibling, not a descendant), so the row content swaps
            // instantly with no section-by-section animation.
            .animation(Theme.Motion.snappy, value: listChip)
            }
            .chipRowFade()
            .accessibilityIdentifier("filter-chip-scroll")
            // Pinned outside the scroll (mock A: the word ends the row and is
            // always reachable); one tap = the next sort.
            SortCycleWord(word: sort.short, style: chipStyle) { sort = sort.next }
                .accessibilityIdentifier("sort-cycle-word")
            }
            if showDateStrip {
                DateRangeStrip(style: chipStyle, from: $filter.from, to: $filter.to,
                               fieldLabels: MemoDateField.allCases.map(\.rawValue),
                               fieldIndex: Binding(
                                   get: { MemoDateField.allCases.firstIndex(of: filter.dateField) ?? 0 },
                                   set: { filter.dateField = MemoDateField.allCases[$0] }))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
        .padding(.bottom, 4)
    }

    /// D135: "each chip counts its own notes" — over ALL live notes (not the
    /// filtered view), like the Mac's sidebar. `.all` carries no number.
    var chipCounts: [QueueFilter: Int] {
        let enhanced = enhancedMemoIDs
        return NotesListModel.chipCounts(
            needsWork: memos.filter { QueueFilter.needsWork.admits($0, enhancedIDs: enhanced) }.count,
            done: memos.filter { QueueFilter.done.admits($0, enhancedIDs: enhanced) }.count,
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

    /// D135/D136: the phone's header is JUST Notes + Select — Import and Scan live in the
    /// shared `verbRow`'s Import menu below, and the chip row carries Date (Q66).
    var headerRow: some View {
        HStack(spacing: 18) {
            ScreenTitle(SharedCopy.notesTitle)
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
