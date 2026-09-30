#if os(macOS)
import SwiftUI
import AppKit
import QuotaCore

struct MenuBarView: View {
    @EnvironmentObject private var store: AccountStore
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("QuotaBar", systemImage: "chart.bar.xaxis").font(.headline)
                Spacer()
                if !store.refreshing.isEmpty { ProgressView().controlSize(.small) }
                else {
                    Button { Task { await store.refreshAll() } } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.plain).help("Refresh all accounts")
                }
            }.padding(16)
            Divider()
            if store.accounts.isEmpty {
                VStack(spacing: 12) {
                    Text("No connected accounts").foregroundStyle(.secondary)
                    Button("Add account") { dashboard(); store.connect() }.buttonStyle(.borderedProminent)
                }.padding(30)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(store.accounts) { account in
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Image(systemName: account.provider.symbol).foregroundStyle(account.provider.tint)
                                    Text(account.name).font(.headline).lineLimit(1)
                                    Spacer()
                                    Button { dashboard(); store.connect(account) } label: { Image(systemName: "person.crop.circle.badge.checkmark") }
                                        .buttonStyle(.plain).help("Reconnect \(account.name)")
                                }
                                if let snapshot = account.snapshot {
                                    ForEach(snapshot.windows) { window in UsageMeter(window: window, tint: account.provider.tint, showRemaining: store.showRemaining) }
                                    if snapshot.isStale || store.errors[account.id] != nil {
                                        Text("Last reading · \(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))")
                                            .font(.caption).foregroundStyle(.orange)
                                    }
                                } else { Text("No usage reading yet").font(.caption).foregroundStyle(.secondary) }
                                if let error = store.errors[account.id] {
                                    Text(error).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                                }
                            }.padding(16)
                            Divider()
                        }
                    }
                }.frame(maxHeight: 480)
            }
            HStack {
                Button("Open dashboard", action: dashboard)
                Spacer()
                Menu {
                    SettingsLink { Text("Settings…") }
                    Button("Quit QuotaBar") { NSApplication.shared.terminate(nil) }
                } label: { Image(systemName: "gearshape") }.menuStyle(.borderlessButton).fixedSize()
            }.padding(14)
        }.frame(width: 350)
    }
    private func dashboard() {
        openWindow(id: "dashboard"); NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
struct PreferencesView: View {
    @EnvironmentObject private var store: AccountStore
    var body: some View {
        Form {
            Picker("Refresh accounts every", selection: $store.refreshMinutes) {
                Text("1 minute").tag(1); Text("5 minutes").tag(5); Text("15 minutes").tag(15); Text("30 minutes").tag(30)
            }
            Toggle("Show remaining allowance", isOn: $store.showRemaining)
            Text("Provider rate-limit backoff overrides the refresh interval. Credentials are stored in macOS Keychain.")
                .font(.caption).foregroundStyle(.secondary)
        }.formStyle(.grouped).padding().frame(width: 440)
    }
}
#endif
