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
                        ForEach(store.orderedAccounts) { account in
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Image(systemName: account.provider.symbol).foregroundStyle(account.provider.tint)
                                    Text(store.presentationMode ? account.provider.title + " account" : account.name).font(.headline).lineLimit(1)
                                    Spacer()
                                    Button {
                                        store.pinAccount(store.pinnedAccountID == account.id.uuidString ? "" : account.id.uuidString)
                                    } label: {
                                        Image(systemName: store.pinnedAccountID == account.id.uuidString ? "pin.fill" : "pin")
                                    }.buttonStyle(.plain).help("Pin account allowance in menu bar")
                                    Button { dashboard(); store.connect(account) } label: { Image(systemName: "person.crop.circle.badge.checkmark") }
                                        .buttonStyle(.plain).help("Reconnect account").disabled(store.presentationMode)
                                }
                                if store.presentationMode {
                                    Text("Account details and balances hidden").font(.caption).foregroundStyle(.secondary)
                                } else {
                                    Text(store.availability(account).status.title).font(.caption).foregroundStyle(.secondary)
                                    if let snapshot = account.snapshot {
                                        CreditSummary(snapshot: snapshot, provider: account.provider)
                                        ForEach(snapshot.windows) { window in UsageMeter(window: window, tint: account.provider.tint, showRemaining: store.showRemaining) }
                                        if snapshot.isStale || store.errors[account.id] != nil {
                                            Text("Last reading · \(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))")
                                                .font(.caption).foregroundStyle(.orange)
                                        }
                                    } else { Text("No usage reading yet").font(.caption).foregroundStyle(.secondary) }
                                    if let error = store.errors[account.id] {
                                        Text(error).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                                    }
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
                    Toggle("Presentation mode", isOn: $store.presentationMode)
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
struct MenuBarLabel: View {
    @EnvironmentObject private var store: AccountStore
    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            HStack(spacing: 5) {
                Image(systemName: "chart.bar.xaxis")
                if !store.presentationMode, let account = store.pinnedAccount {
                    let reading = PinnedAllowance.make(snapshot: account.snapshot, windowID: store.pinnedWindowID,
                                                       hasError: store.errors[account.id] != nil, now: context.date)
                    Text(reading.text).monospacedDigit()
                }
                if !store.refreshing.isEmpty { Text("↻") }
            }
            .help(help(now: context.date))
        }
    }
    private func help(now: Date) -> String {
        if store.presentationMode { return "QuotaBar · presentation mode · details hidden" }
        guard let account = store.pinnedAccount else { return "QuotaBar · subscription usage" }
        let reading = PinnedAllowance.make(snapshot: account.snapshot, windowID: store.pinnedWindowID,
                                           hasError: store.errors[account.id] != nil, now: now)
        return "\(account.name) · \(reading.windowTitle ?? "No reading") · \(reading.text)" +
            (reading.isStale ? " · last reading; refresh to confirm" : "")
    }
}
#endif
