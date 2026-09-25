import SwiftUI

extension MemosListView {
    // MARK: - Bottom bars

    /// "Importing N share(s)…" — visible only while the drainer is copying inbox
    /// blobs (A14). Same capsule styling as the sync banner so the top edge stays
    /// one visual language.
    var importPendingPill: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(drainState.pendingCount == 1 ? "Importing share…"
                 : "Importing \(drainState.pendingCount) shares…")
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Color.skText)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Color.skElev, in: .capsule)
        .overlay(Capsule().stroke(Color.skBorder, lineWidth: 1))
        .padding(.top, 6)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityIdentifier("import-pending-pill")
    }

    @ViewBuilder var syncBannerView: some View {
        if let syncBanner {
            Text(syncBanner)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.skText)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Color.skElev, in: .capsule)
                .overlay(Capsule().stroke(Color.skBorder, lineWidth: 1))
                .padding(.top, 6)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    /// Show the top banner briefly. The token keeps an earlier banner's expiry
    /// from clipping a newer one.
    func flashBanner(_ text: String) {
        bannerToken += 1
        let token = bannerToken
        syncBanner = text
        Task {
            try? await Task.sleep(for: .seconds(2.2))
            if bannerToken == token { syncBanner = nil }
        }
    }

    /// Present the recorder + auto-start for a Record intent / widget / deep link.
    /// `lastHandledStart` makes it fire once per request and catches a request that
    /// arrived during a cold launch before `.onChange` was subscribed.
    func handleStartRequest() {
        guard intentBridge.startRequestID > lastHandledStart else { return }
        lastHandledStart = intentBridge.startRequestID
        // Just present — RecordView consumes the bridge's pending start once it's
        // foreground-active (no stale-flag propagation through the cover).
        showRecord = true
    }

    /// A shared video imported on foreground → open it. It relocates to the
    /// video's filming date, so it'd otherwise vanish from the top of the list;
    /// resetting the path to it (like the record-saved path) lands the user on it.
    func handleOpenRequest() {
        if let id = memoOpen.consume() { openMemo(id) }
    }

    /// A New Note request (widget / Control Center / Siri / `skrift://newnote`)
    /// → open the same quick-note screen the app's own ✎ opens.
    /// `lastHandledQuickNote` fires it once per request and catches a request
    /// that arrived during a cold launch before `.onChange` was subscribed.
    func handleQuickNoteRequest() {
        guard quickNoteBridge.requestID > lastHandledQuickNote else { return }
        lastHandledQuickNote = quickNoteBridge.requestID
        newTypedNote()
    }

    // (recordFAB moved into NotesBottomChrome — the Option-A split row at the
    // bottom of this file.)

    var selectionBar: some View {
        HStack {
            Text("\(selected.count) selected").font(.subheadline.weight(.semibold)).foregroundStyle(Color.skTextDim)
            Spacer()
            Button(role: .destructive, action: deleteSelected) {
                Label("Delete", systemImage: "trash")
            }
            .disabled(selected.isEmpty)
            .accessibilityIdentifier("delete-selected-button")
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .background(.ultraThinMaterial)
        .clipShape(.rect(topLeadingRadius: 20, topTrailingRadius: 20))
    }

    // MARK: - Actions

    func deleteSelected() {
        for id in selected {
            guard let memo = memos.first(where: { $0.id == id }) else { continue }
            deleteMemo(memo)
        }
        selected.removeAll()
        editMode = .inactive
    }

    /// Quick copy straight from the list: transcript (fallback: title) → pasteboard,
    /// with a light haptic + the same top banner as sync. An empty memo says so
    /// instead of silently copying nothing.
    /// Lock (instant; honesty copy lives on the detail page too) / remove lock
    /// (requires auth — Apple Notes idiom). Locking an already-published memo
    /// surfaces the vault notice; Skrift never deletes vault files.
    func toggleLock(_ memo: Memo) {
        if memo.locked {
            Task {
                guard await LockGate.shared.authorizeRemoveLock() else { return }
                memo.locked = false
                memo.markEdited(stampWords: false)   // lock isn't title/body/tags (C98)
                NotesRepository.shared.save()
            }
        } else {
            guard LockGate.shared.canAuthenticate() else { return }
            memo.locked = true
            memo.markEdited(stampWords: false)   // lock isn't title/body/tags (C98)
            NotesRepository.shared.save()
            if ObsidianVault.hasPublished(memo.id) { lockVaultNotice = true }
        }
    }

    /// R88: `copyableText` itself refuses a locked, unauthenticated memo — this
    /// just supplies the right banner instead of the generic "nothing to copy".
    func copyTranscript(_ memo: Memo) {
        guard let text = memo.copyableText else {
            flashBanner(LockGate.shared.isLocked(memo) ? "Locked note" : "Nothing to copy yet")
            return
        }
        UIPasteboard.general.string = text
        Haptics.tap(.light)
        flashBanner("Copied")
    }

    /// Soft-delete: move the memo to Recently Deleted (audio + sidecars stay on
    /// disk so Restore is lossless; purged for good after ~2 weeks at startup).
    /// Shared by multi-select delete, swipe-to-delete, and the context menu —
    /// all three entry points funnel through here, so gating it once (R88)
    /// covers all three: a locked note needs auth first, the same idiom
    /// `toggleLock`'s Remove-Lock path already uses.
    func deleteMemo(_ memo: Memo) {
        guard LockGate.shared.isLocked(memo) else {
            repository.softDelete(memo)
            return
        }
        Task {
            guard await LockGate.shared.unlock(memo.id) else { return }
            repository.softDelete(memo)
        }
    }
}
