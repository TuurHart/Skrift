import SwiftUI

/// Pair a Mac (mockup3): Bonjour auto-discovery + a manual host/port fallback.
/// No QR. The native Mac server advertises `_skrift._tcp`; tapping a discovered
/// Mac resolves + saves its host/port. Live discovery is device/network-owed
/// (the sim seeds entries via `-seedDiscoveredMacs`).
struct PairMacView: View {
    @StateObject private var discovery = MacDiscovery()
    @State private var connection = MacConnection.load()
    @State private var manualHost = ""
    @State private var manualPort = "8000"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel("ON YOUR NETWORK").padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 8)

                groupCard {
                    ForEach(discovery.macs) { mac in
                        discoveredRow(mac)
                        Divider().overlay(Color.skBorder)
                    }
                    HStack(spacing: 11) {
                        ProgressView().controlSize(.small).tint(.skAccent)
                        Text("Looking for more Macs…").font(.system(size: 13)).foregroundStyle(Color.skTextDim)
                        Spacer()
                    }
                    .padding(.horizontal, 14).padding(.vertical, 13)
                }

                SectionLabel("MANUALLY").padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 8)

                groupCard {
                    HStack {
                        TextField("Host (e.g. 192.168.1.22)", text: $manualHost)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityIdentifier("pair-host-field")
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    Divider().overlay(Color.skBorder)
                    HStack {
                        TextField("Port", text: $manualPort)
                            .keyboardType(.numberPad)
                            .frame(width: 90)
                            .accessibilityIdentifier("pair-port-field")
                        Spacer()
                        Button("Connect", action: connectManual)
                            .font(.system(size: 14, weight: .bold)).foregroundStyle(Color.skAccent)
                            .disabled(manualHost.trimmingCharacters(in: .whitespaces).isEmpty)
                            .accessibilityIdentifier("manual-connect-button")
                    }
                    .padding(.horizontal, 14).padding(.vertical, 11)
                }

                Text("Keep your iPhone and Mac on the same Wi-Fi. Discovery uses Bonjour — no QR or codes needed.")
                    .font(.system(size: 12)).foregroundStyle(Color.skTextFaint)
                    .padding(.horizontal, 22).padding(.top, 14)
            }
        }
        .background(Color.skBg.ignoresSafeArea())
        .navigationTitle("Pair a Mac")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { discovery.start() }
        .onDisappear { discovery.stop() }
    }

    @ViewBuilder private func groupCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(Color.skSurface, in: .rect(cornerRadius: Theme.Radius.group, style: .continuous))
            .overlay(RoundedRectangle.sk(Theme.Radius.group).stroke(Color.skBorder, lineWidth: 1))
            .padding(.horizontal, 16)
    }

    private func discoveredRow(_ mac: DiscoveredMac) -> some View {
        HStack(spacing: 11) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 16))
                .foregroundStyle(isConnected(mac) ? Color(hex: 0xb9acff) : Color.skTextDim)
                .frame(width: 32, height: 32)
                .background(isConnected(mac) ? Color.skAccentSoft : Color.skElev, in: .rect(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(mac.name).font(.system(size: 15)).foregroundStyle(Color.skText)
                if let host = mac.host { Text("\(host) · \(mac.port ?? 8000)").font(.system(size: 12.5)).foregroundStyle(Color.skTextFaint) }
            }
            Spacer()
            if isConnected(mac) {
                Label("Connected", systemImage: "checkmark")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(Color.skGreen)
                    .labelStyle(.titleAndIcon)
            } else {
                Button("Connect") { connectDiscovered(mac) }
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(Color.skAccent)
                    .accessibilityIdentifier("discovered-connect")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 13)
    }

    private func isConnected(_ mac: DiscoveredMac) -> Bool {
        guard let conn = connection, let host = mac.host else { return false }
        return conn.host == host && conn.port == (mac.port ?? MacConnection.defaultPort)
    }

    private func connectDiscovered(_ mac: DiscoveredMac) {
        Task {
            if let conn = await discovery.resolve(mac) {
                conn.save()
                connection = conn
            }
        }
    }

    private func connectManual() {
        let host = manualHost.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { return }
        let conn = MacConnection(host: host, port: Int(manualPort) ?? MacConnection.defaultPort)
        conn.save()
        connection = conn
    }
}
