import SwiftUI

@main
struct GlassLabApp: App {
    var body: some Scene {
        WindowGroup { GlassLabView() }
    }
}

/// Scene chosen by a launch arg (`-scene static|scroll|skrift`) for XCUITests, or by
/// the in-app segmented picker for hands-on device evaluation.
struct GlassLabView: View {
    @State private var scene: String = {
        let a = ProcessInfo.processInfo.arguments
        if let i = a.firstIndex(of: "-scene"), i + 1 < a.count { return a[i + 1] }
        return "static"
    }()

    @State private var dark: Bool = ProcessInfo.processInfo.arguments.contains("-dark")

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                switch scene {
                case "scroll": ScrollScene()
                case "skrift": SkriftScene()
                default:       StaticScene()
                }
            }
            .ignoresSafeArea()

            VStack(spacing: 6) {
                Picker("", selection: $scene) {
                    Text("Static").tag("static")
                    Text("Scroll").tag("scroll")
                    Text("Skrift").tag("skrift")
                }
                .pickerStyle(.segmented)
                Toggle(isOn: $dark) { Text("Dark mode").font(.caption).foregroundStyle(.white) }
                    .toggleStyle(.switch)
            }
            .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 8)
            .background(.black.opacity(0.4))
        }
        .preferredColorScheme(dark ? .dark : .light)
    }
}

// MARK: - Skrift scene: faithful replica of MemoDetail (dark bg, light-gray transcript,
// a photo) with the EXACT bottomChrome glass treatment — the real target to tune.

struct SkriftScene: View {
    private let bg = Color(.sRGB, red: 15/255, green: 17/255, blue: 23/255, opacity: 1)
    private let text = Color(.sRGB, red: 228/255, green: 228/255, blue: 231/255, opacity: 1)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Harbour at dawn").font(.system(size: 24, weight: .bold)).foregroundStyle(text)
                ForEach(0..<6) { i in
                    Text("Line \(i): the harbour was quiet at dawn and the light came in sideways across the water, slow and gold.")
                        .font(.system(size: 15.5)).foregroundStyle(text)
                }
                photo
                ForEach(6..<12) { i in
                    Text("Line \(i): then the ferry crossed and everyone on the quay went quiet for a moment.")
                        .font(.system(size: 15.5)).foregroundStyle(text)
                }
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(bg.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { skriftBar }
    }

    /// A stand-in photo (contrasty) like a real memo image. Tall so it sits behind
    /// the bottom bar at rest — the decisive "glass over a photo" case.
    private var photo: some View {
        LinearGradient(colors: [.orange, .pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
            .frame(height: 460)
            .overlay(Image(systemName: "mountain.2.fill").font(.system(size: 52)).foregroundStyle(.white.opacity(0.9)))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// Proposed real fix: a LIGHT glass "island" (forced light colorScheme → bright,
    /// clear glass — the look you liked) with DARK content so it reads, floating over
    /// the dark app. This is how you keep bright Liquid Glass in a dark UI.
    @ViewBuilder private var skriftBar: some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        let ink = Color(.sRGB, red: 0.13, green: 0.13, blue: 0.15, opacity: 1)   // dark content on bright glass
        let accent = Color(.sRGB, red: 124/255, green: 107/255, blue: 245/255, opacity: 1)
        let content = VStack(spacing: 10) {
            Capsule().fill(ink.opacity(0.20)).frame(height: 4)
            HStack(spacing: 34) {
                Image(systemName: "gobackward.10")
                Image(systemName: "play.fill").font(.system(size: 22)).foregroundStyle(.white)
                    .frame(width: 60, height: 60).background(accent, in: .circle)
                Image(systemName: "goforward.10")
            }
            .font(.system(size: 24)).foregroundStyle(ink)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)

        Group {
            if #available(iOS 26.0, *) {
                GlassEffectContainer { content.glassEffect(.regular, in: shape) }
            } else {
                content.background(.ultraThinMaterial, in: shape)
            }
        }
        .environment(\.colorScheme, .light)   // bright glass even though the app is dark
        .padding(.horizontal, 20).padding(.bottom, 6)
        .accessibilityIdentifier("skrift-bar")
    }
}

// MARK: - Vivid backdrop (high-frequency so any lensing/blur is obvious)

/// A rainbow gradient overlaid with thin white stripes + big glyphs. Liquid Glass
/// lensing bends the straight stripes near a shape's edge; a plain blur just softens
/// them. Either way the effect is unmistakable here (unlike over Skrift's dark text).
struct Backdrop: View {
    var body: some View {
        LinearGradient(colors: [.red, .orange, .yellow, .green, .cyan, .blue, .purple],
                       startPoint: .top, endPoint: .bottom)
            .overlay(stripes)
            .overlay(glyphs)
            .ignoresSafeArea()
    }

    private var stripes: some View {
        GeometryReader { geo in
            Path { p in
                var x: CGFloat = 0
                while x < geo.size.width { p.move(to: .init(x: x, y: 0)); p.addLine(to: .init(x: x, y: geo.size.height)); x += 16 }
                var y: CGFloat = 0
                while y < geo.size.height { p.move(to: .init(x: 0, y: y)); p.addLine(to: .init(x: geo.size.width, y: y)); y += 16 }
            }
            .stroke(Color.white.opacity(0.55), lineWidth: 1.5)
        }
    }

    private var glyphs: some View {
        VStack(spacing: 30) {
            ForEach(0..<8) { i in
                Text("SKRIFT \(i)").font(.system(size: 40, weight: .black)).foregroundStyle(.white.opacity(0.9))
            }
        }
    }
}

// MARK: - Static scene: four bars over the backdrop, one per effect

enum GlassStyle: String, CaseIterable, Identifiable {
    case regular      = "glassEffect(.regular)"
    case clear        = "glassEffect(.clear)"
    case ultraThin    = ".ultraThinMaterial"
    case regularMat   = ".regularMaterial"
    var id: String { rawValue }
}

struct StaticScene: View {
    var body: some View {
        ZStack {
            Backdrop()
            VStack(spacing: 26) {
                Spacer()
                ForEach(GlassStyle.allCases) { style in
                    BarSample(style: style)
                }
                Spacer()
            }
            .padding(.horizontal, 22)
        }
    }
}

/// A player-bar-shaped pill (label + transport icons) with the chosen effect, so we
/// can compare how each reads over identical busy content.
struct BarSample: View {
    let style: GlassStyle

    private var content: some View {
        VStack(spacing: 8) {
            Text(style.rawValue).font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
            HStack(spacing: 28) {
                Image(systemName: "gobackward.10")
                Image(systemName: "play.fill").font(.system(size: 22))
                Image(systemName: "goforward.10")
            }
            .font(.system(size: 20)).foregroundStyle(.white)
        }
        .padding(.horizontal, 22).padding(.vertical, 14)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder var body: some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        switch style {
        case .regular:
            if #available(iOS 26.0, *) {
                GlassEffectContainer { content.glassEffect(.regular, in: shape) }
            } else { content.background(.ultraThinMaterial, in: shape) }
        case .clear:
            if #available(iOS 26.0, *) {
                GlassEffectContainer { content.glassEffect(.clear, in: shape) }
            } else { content.background(.ultraThinMaterial, in: shape) }
        case .ultraThin:
            content.background(.ultraThinMaterial, in: shape)
        case .regularMat:
            content.background(.regularMaterial, in: shape)
        }
    }
}

// MARK: - Scroll scene: a glass bar via safeAreaInset over a colorful list (mirrors Skrift)

struct ScrollScene: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(0..<40) { i in
                    Text("Row \(i) — the harbour was quiet at dawn and the light came in")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(stripeColor(i), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(16)
        }
        .background(Backdrop())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
            Group {
                if #available(iOS 26.0, *) {
                    GlassEffectContainer {
                        barContent.glassEffect(.regular, in: shape)
                    }
                } else {
                    barContent.background(.ultraThinMaterial, in: shape)
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 6)
            .accessibilityIdentifier("glass-bar")
        }
    }

    private var barContent: some View {
        HStack(spacing: 28) {
            Image(systemName: "gobackward.10")
            Image(systemName: "play.fill").font(.system(size: 22))
            Image(systemName: "goforward.10")
        }
        .font(.system(size: 20)).foregroundStyle(.white)
        .padding(.horizontal, 22).padding(.vertical, 16)
        .frame(maxWidth: .infinity)
    }

    private func stripeColor(_ i: Int) -> Color {
        let palette: [Color] = [.red, .orange, .green, .blue, .purple, .pink]
        return palette[i % palette.count].opacity(0.85)
    }
}
