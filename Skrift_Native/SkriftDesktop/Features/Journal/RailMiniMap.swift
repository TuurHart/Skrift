import SwiftUI
import MapKit

/// The ambient mini-map at the bottom of the Review rail — mock
/// `mocks/review-minimap.html` #m1, picked by Tuur 2026-07-17. A STATIC
/// `MKMapSnapshotter` shot fitted to every pin (no live Map idling in the rail),
/// with the SAME merged clusters as the real map drawn on top. Click anywhere →
/// the full map column, camera fitting all pins. Hidden by the caller when
/// nothing is located.
struct RailMiniMap: View {
    let clusters: [PlaceCluster]
    var onOpen: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var shot: NSImage?
    @State private var pins: [MiniPin] = []

    /// Shot at the exact displayed size so `snapshot.point(for:)` maps 1:1.
    private static let size = CGSize(width: 224, height: 150)

    struct MiniPin: Identifiable {
        let id: String
        let count: Int
        let extra: Int      // merged-in places beyond the host ("+N")
        let point: CGPoint
    }

    var body: some View {
        Button(action: onOpen) {
            ZStack {
                Group {
                    if let shot {
                        Image(nsImage: shot).resizable()
                    } else {
                        // Placeholder while the async shot loads (and in headless
                        // fixtures, where the snapshotter never resolves).
                        Rectangle().fill(Theme.surfaceHover.opacity(0.45))
                    }
                }
                ForEach(pins) { pin in
                    pinBubble(pin).position(pin.point)
                }
                Text("click → full map")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Theme.bg.opacity(0.72), in: RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.hairline.opacity(0.07), lineWidth: 1))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(7)
            }
            .frame(width: Self.size.width, height: Self.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline.opacity(0.08), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .help("Show the full map")
        .task(id: shotKey) { await reshoot() }
    }

    private func pinBubble(_ pin: MiniPin) -> some View {
        HStack(spacing: 2) {
            Text("\(pin.count)").font(.system(size: 10.5, weight: .bold))
            if pin.extra > 0 {
                Text("+\(pin.extra)").font(.system(size: 8.5, weight: .semibold)).opacity(0.85)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .frame(minWidth: 22, minHeight: 22)
        .background(Capsule().fill(Theme.accent))
        .shadow(color: Theme.accent.opacity(0.45), radius: 4, y: 1)
    }

    /// Re-shoot when the clusters or the appearance change — not on every body eval.
    private var shotKey: String {
        "\(scheme)|" + clusters.map { "\($0.id):\($0.memos.count)" }.joined(separator: "·")
    }

    private func reshoot() async {
        guard let region = PlaceCluster.fitRegion(for: clusters) else {
            shot = nil; pins = []; return
        }
        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = Self.size
        options.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        // Ambient map: no POI labels/icons competing with the pins.
        options.pointOfInterestFilter = .excludingAll
        guard let snap = try? await MKMapSnapshotter(options: options).start() else { return }
        let merged = PlaceCluster.merged(clusters, span: region.span)
        pins = merged.map { c in
            MiniPin(id: c.id, count: c.memos.count,
                    extra: max(0, c.id.split(separator: "+").count - 1),
                    point: snap.point(for: c.coordinate))
        }
        shot = snap.image
    }
}
