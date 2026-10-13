import SwiftUI

/// Q379 tabs option A (D198, signed mock Q378-ipad-apple): at regular width the four tabs are a
/// slim glass control at the top of the list column, above the list header; the system tab bar
/// is hidden. The control leaves with the list when ◧ hides it. `AppTabView` hands the current
/// tab and the switch down through the environment.
struct IPadTabContext {
    var current: AppTabView.Tab
    var select: (AppTabView.Tab) -> Void
}

private struct IPadTabKey: EnvironmentKey { static let defaultValue: IPadTabContext? = nil }
extension EnvironmentValues {
    var ipadTab: IPadTabContext? {
        get { self[IPadTabKey.self] }
        set { self[IPadTabKey.self] = newValue }
    }
}

/// The capsule: four equal segments, the current one accent-soft.
struct IPadTabControl: View {
    @Environment(\.ipadTab) private var ctx

    var body: some View {
        if let ctx {
            HStack(spacing: 2) {
                ForEach(IPadLayout.tabs, id: \.self) { tab in
                    let on = ctx.current == tab
                    let title = IPadLayout.tabTitle(tab)
                    Button { ctx.select(tab) } label: {
                        Text(title)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .foregroundStyle(on ? Color.skAccentText : Color.skTextDim)
                            .frame(maxWidth: .infinity)
                            .frame(height: IPadLayout.glassHeight - 6)
                            .background(on ? Color.skAccentSoft : Color.clear, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("ipad-tab-\(title)")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(3)
            .frame(height: IPadLayout.glassHeight)
            .ipadGlass(in: Capsule())
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("ipad-tab-control")
        }
    }
}

/// The 60 pt row the control sits in: it clears the screen-pinned ◧ on the leading side.
struct IPadTabRow: View {
    var body: some View {
        IPadTabControl()
            .padding(.leading, IPadLayout.tabRowLeading)
            .padding(.trailing, IPadLayout.tabRowTrailing)
            .frame(height: IPadLayout.rowHeight)
    }
}

extension View {
    /// Per tab: the system tab bar only on the phone layout; at regular width the non-Notes tabs
    /// carry the tab row at the top-leading corner, at the list column's width, where the Notes
    /// tab carries it inside its list column (`MemosListView`).
    @ViewBuilder func ipadTabChrome(_ size: UserInterfaceSizeClass?, hostsOwnRow: Bool) -> some View {
        let regular = !IPadLayout.showsSystemTabBar(size)
        // Q387: at compact width set NOTHING for the tab bar: an explicit `.automatic` here wins over
        // the open note's `.toolbar(.hidden, for: .tabBar)` (D200), so the phone's note kept the bar.
        TabBarVisibility(regular: regular, content: self)
            .safeAreaInset(edge: .top, spacing: 0) {
                if regular && !hostsOwnRow {
                    HStack(spacing: 0) {
                        IPadTabRow().frame(width: IPadLayout.listColumnWidth)
                        Spacer(minLength: 0)
                    }
                }
            }
    }
}

/// Hides the tab bar at regular width only; at compact it adds no tab-bar preference at all, so a
/// pushed note can hide it (D200). The branch only flips when the size class does.
private struct TabBarVisibility<Content: View>: View {
    let regular: Bool
    let content: Content
    var body: some View {
        if regular { content.toolbar(.hidden, for: .tabBar) } else { content }
    }
}
