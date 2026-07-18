import SwiftUI
import SwiftData

/// The Mac shelves (mock `fading-shelf.html`, signed 2026-07-17): Fading +
/// Recently Deleted as Review column swaps, entered from the paired rail rows.
/// Lifecycle actions (Keep / sweep / restore) are the ONE deliberate exception
/// to Review's read-only stance — they write through the cloud container and
/// sync everywhere. Permanent deletion stays phone-owned (its trash purge);
/// the Mac never hard-deletes.
@MainActor
enum MacFadingSweep {
    static let armedKey = "fadingTimersArmed"   // same key string as the phone; per-device value
    static var armed: Bool { UserDefaults.standard.bool(forKey: armedKey) }
    static func arm() { UserDefaults.standard.set(true, forKey: armedKey) }

    /// Timed sweep (60d) — armed-gated, idempotent; rides Review's refresh.
    static func run(memos: [Memo], context: ModelContext, now: Date = Date()) {
        guard armed else { return }
        let live = memos.filter { $0.deletedAt == nil }
        let backlinked = MemoLifecycle.backlinkedIDs(in: live)
        var swept = 0
        for memo in live where MemoLifecycle.sweepDue(memo, backlinked: backlinked, now: now) {
            memo.deletedAt = now
            swept += 1
        }
        if swept > 0 { try? context.save() }
    }
}

struct FadingShelfColumn: View {
    let fading: [Memo]
    var context: ModelContext?
    var onChanged: () -> Void
    var onBack: () -> Void

    @State private var armed = MacFadingSweep.armed

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if !armed && !fading.isEmpty { firstRun }
            if fading.isEmpty {
                Text("Nothing is fading. Untouched notes land here after \(MemoLifecycle.fadeAfterDays) days.")
                    .font(.system(size: 12)).foregroundStyle(Theme.textMuted)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(fading.sorted { MemoLifecycle.fadesAt($0) < MemoLifecycle.fadesAt($1) },
                            id: \.persistentModelID) { memo in
                        row(memo)
                    }
                }
            }
            Text("Do nothing and each note moves to Recently Deleted on its day — restorable there for \(TrashPolicy.retentionDays) more days. Keep = never fades again.")
                .font(.system(size: 11)).foregroundStyle(Theme.textMuted)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 24).padding(.horizontal, 30)
    }

    private var header: some View {
        HStack {
            Text("Fading · \(fading.count) note\(fading.count == 1 ? "" : "s")")
                .font(.system(size: 17, weight: .bold))
            Spacer()
            Button { onBack() } label: {
                Label("Back", systemImage: "xmark")
                    .font(.system(size: 11)).foregroundStyle(Theme.textMuted)
            }
            .buttonStyle(.plain)
        }
    }

    private var firstRun: some View {
        HStack(spacing: 12) {
            (Text("First sweep. ").foregroundStyle(Theme.amber).bold()
             + Text("These \(fading.count) notes qualified from your existing corpus. Nothing moves automatically until you've seen this once."))
                .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            Spacer()
            capsuleButton("Start the timers", prominent: true) {
                MacFadingSweep.arm(); armed = true
                if let context { MacFadingSweep.run(memos: fading, context: context) }
                onChanged()
            }
            capsuleButton("Sweep all now", prominent: false) {
                MacFadingSweep.arm(); armed = true
                sweepAll()
            }
        }
        .padding(12)
        .background(Theme.amber.opacity(0.06), in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Theme.amber.opacity(0.3), lineWidth: 1))
    }

    private func row(_ memo: Memo) -> some View {
        let days = MemoLifecycle.daysUntilSweep(memo)
        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(rowTitle(memo))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary).lineLimit(1)
                HStack(spacing: 10) {
                    Text(memo.recordedAt.formatted(date: .abbreviated, time: .omitted))
                    if let place = memo.metadata?.location?.placeName { Text(place) }
                    if memo.duration > 0 { Text(Self.mmss(memo.duration)) }
                }
                .font(.system(size: 10.5)).foregroundStyle(Theme.textMuted)
            }
            Spacer(minLength: 8)
            Text(days == 0 ? "fades today" : "fades in \(days) day\(days == 1 ? "" : "s")")
                .font(.system(size: 10.5))
                .foregroundStyle(days <= 3 ? Theme.destructive : Theme.amber)
            capsuleButton("Keep", prominent: false) {
                memo.keptAt = Date()
                try? context?.save()
                onChanged()
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline.opacity(0.07), lineWidth: 1))
        .frame(maxWidth: 760, alignment: .leading)
    }

    private func sweepAll() {
        let now = Date()
        for memo in fading { memo.deletedAt = now }
        try? context?.save()
        onChanged()
    }

    private func rowTitle(_ memo: Memo) -> String {
        let t = (memo.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        let body = (memo.transcript ?? "").replacingOccurrences(of: "\n", with: " ")
        return body.isEmpty ? "Voice note" : String(body.prefix(80))
    }

    private static func mmss(_ d: TimeInterval) -> String {
        let s = Int(d.rounded()); return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Recently Deleted on the Mac — the memo trash (cloud store), with Restore.
/// The phone's startup purge owns permanent deletion.
struct MacTrashColumn: View {
    let trashed: [Memo]
    var context: ModelContext?
    var onChanged: () -> Void
    var onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recently Deleted · \(trashed.count)")
                    .font(.system(size: 17, weight: .bold))
                Spacer()
                Button { onBack() } label: {
                    Label("Back", systemImage: "xmark")
                        .font(.system(size: 11)).foregroundStyle(Theme.textMuted)
                }
                .buttonStyle(.plain)
            }
            Text("Kept for \(TrashPolicy.retentionDays) days, then deleted permanently (your iPhone does the deleting).")
                .font(.system(size: 12)).foregroundStyle(Theme.textMuted)
            ScrollView {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(trashed.sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) },
                            id: \.persistentModelID) { memo in
                        row(memo)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 24).padding(.horizontal, 30)
    }

    private func row(_ memo: Memo) -> some View {
        let left = daysLeft(memo)
        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text((memo.title?.isEmpty == false ? memo.title! : String((memo.transcript ?? "Voice note").prefix(80))))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary).lineLimit(1)
                Text(memo.recordedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 10.5)).foregroundStyle(Theme.textMuted)
            }
            Spacer(minLength: 8)
            Text(left <= 0 ? "deleting soon" : "\(left) day\(left == 1 ? "" : "s") left")
                .font(.system(size: 10.5)).foregroundStyle(left <= 3 ? Theme.destructive : Theme.textMuted)
            capsuleButton("Restore", prominent: false) {
                memo.deletedAt = nil
                try? context?.save()
                onChanged()
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline.opacity(0.07), lineWidth: 1))
        .frame(maxWidth: 760, alignment: .leading)
    }

    private func daysLeft(_ memo: Memo) -> Int {
        guard let deleted = memo.deletedAt else { return TrashPolicy.retentionDays }
        let gone = deleted.addingTimeInterval(TrashPolicy.retention)
        return max(0, Int(ceil(gone.timeIntervalSinceNow / 86_400)))
    }
}

/// hostPNG-safe capsule button (system button styles render wrong offscreen —
/// memory `project_connections_panel`).
@ViewBuilder
func capsuleButton(_ title: String, prominent: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(prominent ? .white : Theme.accent)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(prominent ? Theme.accent : Theme.accent.opacity(0.12), in: Capsule())
    }
    .buttonStyle(.plain)
}
