import SwiftUI

/// C155 (mock `SkriftDesktop/mocks/Q484-sync-health.html`): the list banner, the note line and
/// the account-switch sheet, drawn once for both apps in each app's `NoteCardStyle` colours.

/// The amber list banner above search, in the two-versions banner's shape (`EditConflictBanner`).
/// `actionLabel` nil = no button (the Mac's banner has no Show: its rows carry the pill).
struct SyncHealthBannerView: View {
    let banner: SyncHealth.Banner
    let style: NoteCardStyle
    var actionLabel: String?
    var action: () -> Void = {}

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "icloud.slash")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(style.amber)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(banner.title).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(style.text)
                Text(banner.line).font(.system(size: 12)).foregroundStyle(style.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            if let actionLabel {
                Button(actionLabel, action: action)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(style.amber)
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("sync-banner-action")
            }
        }
        .padding(12)
        .background(style.amber.opacity(0.13), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(style.amber.opacity(0.45), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sync-banner")
    }
}

/// The note's one line ("Not synced yet · iCloud is full"), with What now after a switch.
struct SyncHealthNoteLine: View {
    let text: String
    let style: NoteCardStyle
    var size: CGFloat = 12
    var onWhatNow: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "icloud.slash").font(.system(size: size))
            Text(text).font(.system(size: size))
            Spacer(minLength: 6)
            if let onWhatNow {
                Button(SyncHealth.whatNowVerb, action: onWhatNow)
                    .font(.system(size: size, weight: .semibold))
                    .buttonStyle(.plain)
            }
        }
        .foregroundStyle(style.amber)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sync-note-line")
    }
}

/// "Syncing is stopped": what happened, what is still here and how to sync again. D218: the Mac
/// adds the copy button (`SyncHealth.copyVerb`, `onCopy`); the phone has nothing left to copy (Apple
/// wipes its store on a switch), so it gets OK only.
struct SyncWhatNowView: View {
    let content: SyncHealth.WhatNow
    let style: NoteCardStyle
    var onCopy: (() -> Void)?
    let onOK: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "icloud.slash")
                .font(.system(size: 20)).foregroundStyle(style.amber)
                .frame(width: 44, height: 44)
                .background(style.amber.opacity(0.13), in: Circle())
            Text(content.title).font(.system(size: 19, weight: .bold)).foregroundStyle(style.text)
            Text(content.lead).font(.system(size: 13.5)).foregroundStyle(style.textDim)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(content.facts.enumerated()), id: \.offset) { i, fact in
                    if i > 0 { Divider() }
                    Text(fact).font(.system(size: 13.5)).foregroundStyle(style.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 9)
                }
            }
            .padding(.horizontal, 12)
            .background(style.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(style.border, lineWidth: 1))
            Button(action: onOK) {
                Text("OK").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(style.accent, in: RoundedRectangle(cornerRadius: 12))
                    .contentShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("sync-whatnow-ok")
            if let onCopy {
                Button(action: onCopy) {
                    Text(SyncHealth.copyVerb).font(.system(size: 15, weight: .semibold)).foregroundStyle(style.accentText)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(style.accentSoft, in: RoundedRectangle(cornerRadius: 12))
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sync-whatnow-copy")
                Text(SyncHealth.copyFootnote).font(.system(size: 11.5)).foregroundStyle(style.textDim)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .accessibilityIdentifier("sync-whatnow")
    }
}
