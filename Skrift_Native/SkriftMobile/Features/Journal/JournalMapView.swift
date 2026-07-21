import SwiftUI
import MapKit

/// Places map — brought up to the Mac's signed 2026-07-17 interaction model
/// (ported 2026-07-21 after Tuur's device round found the phone a generation
/// behind: no dive-on-tap, and the bottom card auto-pinned the biggest place
/// regardless of where you panned — "Leiden notes while I'm looking at
/// Portugal"):
/// - the camera is OWNED (`position:`) — automatic framing re-fits all pins on
///   every re-cluster and fights the user's gesture (the Mac's "glitchy map"
///   device finding);
/// - pin tap DIVES city-level (merged pins split into their members); tapping
///   the selected pin again deselects;
/// - with NO selection, the card shows the notes IN FRAME — the map is the
///   filter, pan/zoom refines the list. No auto-selection, ever.
struct JournalMapView: View {
    private let repository = NotesRepository.shared
    @State private var clusters: [PlaceCluster] = []
    @State private var selected: PlaceCluster?
    /// Current camera span — drives Photos-style zoom-adaptive clustering
    /// (Tuur, 2026-07-07): zoomed out, nearby places COLLECT into one pin;
    /// zooming in pulls them apart.
    @State private var span = MKCoordinateSpan(latitudeDelta: 40, longitudeDelta: 40)
    /// The viewport — drives the in-frame list (the map is the filter).
    @State private var visibleRegion: MKCoordinateRegion?
    /// Explicit camera — never `.automatic` after the first gesture (see above).
    @State private var camera: MapCameraPosition = .automatic
    /// True while a dive animation is landing — its onEnd must not clear the
    /// selection the tap just made; every REAL gesture does clear it, so the
    /// card always tracks the view unless you just tapped a pin (Tuur's b89
    /// round: a pinned card kept saying "4 notes" over an empty viewport).
    @State private var programmaticMove = false

    private var displayed: [PlaceCluster] {
        PlaceCluster.merged(clusters, span: span)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(position: $camera) {
                ForEach(displayed) { cluster in
                    Annotation(cluster.name, coordinate: cluster.coordinate) {
                        pin(cluster)
                    }
                }
            }
            .mapStyle(.standard)
            .onMapCameraChange(frequency: .onEnd) { context in
                // Viewport always updates (cheap, feeds the in-frame list)…
                visibleRegion = context.region
                // A real gesture returns the card to frame mode; a dive's own
                // landing doesn't.
                if programmaticMove { programmaticMove = false }
                else if selected != nil { selected = nil }
                // …but re-cluster only on a MEANINGFUL zoom change (>20%) —
                // every span commit rebuilds all annotations (the Mac's rapid-
                // zoom stutter). Panning never re-clusters.
                let new = context.region.span
                let relLat = abs(new.latitudeDelta - span.latitudeDelta) / max(span.latitudeDelta, 0.0001)
                let relLon = abs(new.longitudeDelta - span.longitudeDelta) / max(span.longitudeDelta, 0.0001)
                if relLat > 0.2 || relLon > 0.2 { span = new }
            }
            bottomCard
        }
        .navigationTitle("Places")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            clusters = PlaceCluster.build(from: repository.allMemos())
        }
    }

    // ── pins ──

    /// Does this (possibly merged) pin show the selected place? Merged pins
    /// carry compound "a+b" ids — match on the id COMPONENT, or the highlight
    /// silently vanishes across a merge (Mac device finding, 2026-07-16).
    private func selectedShownBy(_ cluster: PlaceCluster) -> Bool {
        guard let sel = selected else { return false }
        return cluster.id.split(separator: "+").contains(Substring(sel.id))
    }

    /// Pin tap: DIVE — fly down far enough that a merged pin splits into its
    /// members. Tapping the already-selected pin deselects back to frame mode.
    private func dive(into cluster: PlaceCluster) {
        if selectedShownBy(cluster) {
            selected = nil
            return
        }
        selected = cluster
        let members = Set(cluster.id.split(separator: "+").map(String.init))
        let constituents = clusters.filter { members.contains($0.id) }
        if let region = PlaceCluster.fitRegion(for: constituents.isEmpty ? [cluster] : constituents) {
            // Dive means DOWN: if the target frame is WIDER than what's on
            // screen, don't move — tapping a pin while already zoomed deep used
            // to fly back OUT (Tuur's b89 round). Selecting alone is enough.
            let current = visibleRegion
            let tighter = current.map {
                region.span.latitudeDelta < $0.span.latitudeDelta * 0.95
                    || region.span.longitudeDelta < $0.span.longitudeDelta * 0.95
            } ?? true
            if tighter {
                programmaticMove = true
                withAnimation { camera = .region(region) }
            }
        }
    }

    private func pin(_ cluster: PlaceCluster) -> some View {
        Text("\(cluster.memos.count)")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .frame(minWidth: 22, minHeight: 22)
            .background(Circle().fill(selectedShownBy(cluster) ? Color.skAccent : Color.skAccent.opacity(0.7)))
            .shadow(color: Color.skAccent.opacity(0.5), radius: 5, y: 2)
            .onTapGesture { dive(into: cluster) }
    }

    // ── the bottom card: selected place, else the notes in frame ──

    /// Notes whose place pin sits inside the current viewport. Before the first
    /// camera event (nil region): everything.
    private var inFrameMemos: [Memo] {
        let inFrame: [PlaceCluster]
        if let r = visibleRegion {
            inFrame = clusters.filter {
                abs($0.coordinate.latitude - r.center.latitude) <= r.span.latitudeDelta / 2 &&
                abs($0.coordinate.longitude - r.center.longitude) <= r.span.longitudeDelta / 2
            }
        } else {
            inFrame = clusters
        }
        return inFrame.flatMap(\.memos)
            .sorted { LookbackProvider.journalDate($0) > LookbackProvider.journalDate($1) }
    }

    @ViewBuilder private var bottomCard: some View {
        let title = selected.map { "\($0.name) · \($0.memos.count) note\($0.memos.count == 1 ? "" : "s")" }
            ?? "In view · \(inFrameMemos.count) note\(inFrameMemos.count == 1 ? "" : "s")"
        let memos = selected?.memos ?? inFrameMemos
        if !memos.isEmpty {
            JournalCard {
                VStack(alignment: .leading, spacing: 8) {
                    JournalCardHeader(title: title)
                    // ALL the notes, scrollable — the fixed 3 with no scroll was
                    // "in view 8, shows 3" (Tuur's b89 round).
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(memos, id: \.id) { JournalMemoRow(memo: $0) }
                        }
                    }
                    .frame(maxHeight: 230)
                }
            }
            .padding(12)
            .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        }
    }
}

/// Non-interactive mini map for the Journal home's Places card.
struct JournalMapPreview: View {
    let memos: [Memo]
    var body: some View {
        let clusters = PlaceCluster.build(from: memos)
        Map(interactionModes: []) {
            ForEach(clusters) { cluster in
                Annotation(cluster.name, coordinate: cluster.coordinate) {
                    Text("\(cluster.memos.count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Circle().fill(Color.skAccent))
                }
            }
        }
        .mapStyle(.standard)
        .allowsHitTesting(false)
    }
}
