#if os(macOS)
import SwiftUI
import AppKit
import QuotaCore

struct MenuBarView: View {
    @EnvironmentObject private var store: AccountStore
    @EnvironmentObject private var updater: AppUpdater
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("QuotaBar", systemImage: "chart.bar.xaxis").font(.headline)
                Spacer()
                if !store.refreshing.isEmpty { ProgressView().controlSize(.small) }
                else {
                    Button { Task { await store.refreshAll() } } label: { Label("Refresh accounts", systemImage: "arrow.clockwise") }
                        .buttonStyle(.borderless).labelStyle(.iconOnly).help("Refresh all accounts")
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
                    LazyVStack(spacing: 0) {
                        ForEach(store.orderedAccounts) { account in
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Image(systemName: account.provider.symbol).foregroundStyle(account.provider.tint).accessibilityHidden(true)
                                    Text(store.presentationMode ? account.provider.title + " account" : account.name).font(.headline).lineLimit(1)
                                    Spacer()
                                    Button { dashboard(); store.requestSwitch(account) } label: {
                                        Label("Use this account", systemImage: "arrow.left.arrow.right")
                                    }.buttonStyle(.borderless).labelStyle(.iconOnly).help("Use this account in the CLI")
                                        .disabled(store.presentationMode)
                                        .accessibilityLabel(store.presentationMode ? "Use account" : "Use \(account.name) in \(account.provider == .openAI ? "Codex" : "Claude Code")")
                                    Button {
                                        store.pinAccount(store.pinnedAccountID == account.id.uuidString ? "" : account.id.uuidString)
                                    } label: {
                                        Image(systemName: store.pinnedAccountID == account.id.uuidString ? "pin.fill" : "pin")
                                    }.buttonStyle(.borderless).help("Pin account allowance in menu bar")
                                        .accessibilityLabel(store.pinnedAccountID == account.id.uuidString ? "Unpin account" : "Pin account")
                                        .accessibilityValue(store.pinnedAccountID == account.id.uuidString ? "Pinned" : "Not pinned")
                                    Button { dashboard(); store.connect(account) } label: { Label("Reconnect account", systemImage: "person.crop.circle.badge.checkmark") }
                                        .buttonStyle(.borderless).labelStyle(.iconOnly).help("Reconnect account").disabled(store.presentationMode)
                                }
                                if store.presentationMode {
                                    Text("Account details and balances hidden").font(.caption).foregroundStyle(.secondary)
                                } else {
                                    AccountStatusLabel(status: store.availability(account).status)
                                    if store.activeAccountID(account.provider) == account.id.uuidString {
                                        Label("Selected for CLI", systemImage: "person.crop.circle.badge.checkmark").font(.caption).foregroundStyle(.secondary)
                                    }
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
                    Button("Connection health…") { dashboard(); store.showConnectionHealth = true }
                    Toggle("Presentation mode", isOn: $store.presentationMode)
                    Button("Check for Updates…") { updater.check() }.disabled(!updater.canCheck)
                    SettingsLink { Text("Settings…") }
                    Button("Quit QuotaBar") { NSApplication.shared.terminate(nil) }
                } label: { Label("Settings and actions", systemImage: "gearshape") }.menuStyle(.borderlessButton).fixedSize().labelStyle(.iconOnly).accessibilityLabel("Settings and actions")
            }.padding(14)
        }.frame(width: 380)
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
                Image(systemName: "chart.bar.xaxis").accessibilityHidden(true)
                if !store.presentationMode, let account = store.pinnedAccount {
                    let reading = MenuBarReading.make(snapshot: account.snapshot,
                        mode: MenuBarDisplay(rawValue: store.menuBarDisplayRaw) ?? .allowance, windowID: store.pinnedWindowID,
                        hasError: store.errors[account.id] != nil, now: context.date)
                    if let text = reading.text { Text(text).monospacedDigit() }
                }
                if !store.refreshing.isEmpty { Text("↻") }
            }
            .help(help(now: context.date))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("QuotaBar")
            .accessibilityValue(help(now: context.date))
        }
    }
    private func help(now: Date) -> String {
        if store.presentationMode { return "QuotaBar · presentation mode · details hidden" }
        guard let account = store.pinnedAccount else { return "QuotaBar · subscription usage" }
        let reading = MenuBarReading.make(snapshot: account.snapshot,
            mode: MenuBarDisplay(rawValue: store.menuBarDisplayRaw) ?? .allowance, windowID: store.pinnedWindowID,
            hasError: store.errors[account.id] != nil, now: now)
        if store.menuBarDisplayRaw == MenuBarDisplay.iconOnly.rawValue { return "QuotaBar · subscription usage" }
        return "\(account.name) · \(reading.detail)"
    }
}
#endif
