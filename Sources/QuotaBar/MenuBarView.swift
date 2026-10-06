#if os(macOS)
import SwiftUI
import AppKit
import QuotaCore

struct MenuBarView: View {
    var openSettings: @MainActor () -> Void = {}
    @EnvironmentObject private var store: AccountStore
    @EnvironmentObject private var updater: AppUpdater
    @Environment(\.openWindow) private var openWindow
    @State private var search = ""
    private var accounts: [Account] {
        store.orderedAccounts.filter {
            store.presentationMode || search.isEmpty || $0.name.localizedStandardContains(search) ||
            ($0.detail?.localizedStandardContains(search) ?? false)
        }
    }
    private var providers: [Provider] { Provider.allCases.filter { provider in accounts.contains { $0.provider == provider } } }
    private var listHeight: CGFloat {
        min(420, CGFloat(accounts.count) * (store.presentationMode ? 58 : 72) + CGFloat(providers.count) * 32 + 16)
    }
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if store.accounts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.badge.plus").font(.title2).foregroundStyle(.secondary)
                    Text("Your accounts, at a glance").font(.headline)
                    Text("Connect OpenAI or Claude to get started.").font(.caption).foregroundStyle(.secondary)
                    Button("Add account") { dashboard(); store.connect() }.buttonStyle(.borderedProminent)
                        .disabled(store.presentationMode)
                }.frame(maxWidth: .infinity).padding(24)
            } else {
                if store.accounts.count > 6 && !store.presentationMode {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                        TextField("Find an account", text: $search).textFieldStyle(.plain)
                        if !search.isEmpty {
                            Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Clear account search")
                        }
                    }.padding(10).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal, 12).padding(.top, 12)
                }
                if accounts.isEmpty {
                    Text("No matching accounts").font(.callout).foregroundStyle(.secondary).padding(24)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(providers) { provider in
                                HStack {
                                    Text(provider.title).font(.caption.weight(.semibold))
                                    Spacer()
                                    Text(accounts.count { $0.provider == provider }.formatted()).font(.caption).monospacedDigit()
                                }.foregroundStyle(.secondary).padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 2)
                                ForEach(accounts.filter { $0.provider == provider }) { account in
                                    MenuAccountRow(account: account,
                                        useAccount: { dashboard(); store.requestSwitch(account) },
                                        reconnect: { dashboard(); store.connect(account) },
                                        allowKeychainAccess: { dashboard(); Task { await store.allowKeychainAccess(account.id) } })
                                        .environmentObject(store)
                                }
                            }
                        }.padding(8)
                    }.frame(height: listHeight)
                }
            }
            Divider()
            HStack(spacing: 12) {
                Button("Open Dashboard", action: dashboard).buttonStyle(.borderless)
                Spacer()
                Button(action: openSettings) { Image(systemName: "gearshape") }
                    .buttonStyle(.borderless).help("Settings").accessibilityLabel("Settings")
                Menu {
                    Button("Keep Running in Menu Bar") { DashboardWindowController.keepRunningInMenuBar() }
                    Divider()
                    Button("Connection health…") { dashboard(); store.showConnectionHealth = true }
                    Toggle("Presentation mode", isOn: $store.presentationMode)
                    Button("Check for Updates…") { updater.check() }.disabled(!updater.canCheck)
                    Divider()
                    Button("Quit QuotaBar") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
                } label: { Image(systemName: "ellipsis").frame(width: 22, height: 22) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .accessibilityLabel("More actions").help("More actions")
            }.padding(.horizontal, 16).padding(.vertical, 12)
        }.frame(width: 380).tint(AppStyle.signal)
            .onChange(of: store.presentationMode) { _, hidden in if hidden { search = "" } }
    }
    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("QuotaBar").font(.headline)
                Text(store.presentationMode ? "Presentation mode" : "\(store.accounts.count) connected \(store.accounts.count == 1 ? "account" : "accounts")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !store.refreshing.isEmpty { ProgressView().controlSize(.small).accessibilityLabel("Refreshing accounts") }
            else {
                Button { Task { await store.refreshAll() } } label: { Image(systemName: "arrow.clockwise").frame(width: 24, height: 24) }
                    .buttonStyle(.borderless).help("Refresh all accounts").accessibilityLabel("Refresh all accounts")
            }
            Button { dashboard(); store.connect() } label: { Image(systemName: "plus").frame(width: 24, height: 24) }
                .buttonStyle(.borderless).disabled(store.presentationMode).help("Add account").accessibilityLabel("Add account")
        }.padding(16)
    }
    private func dashboard() {
        DashboardWindowController.showDashboard { openWindow(id: "dashboard") }
    }
}
struct MenuBarLabel: View {
    @EnvironmentObject private var store: AccountStore
    var body: some View {
        // MenuBarExtra converts this label into native status-item content.
        // A TimelineView here can repeatedly invalidate the status item on macOS 15.5.
        // The shared store already advances its clock every fifteen seconds.
        let now = store.clock
        HStack(spacing: 5) {
            Image(systemName: "chart.bar.xaxis").accessibilityHidden(true)
            if !store.presentationMode, let account = store.pinnedAccount {
                let reading = MenuBarReading.make(snapshot: account.snapshot,
                    mode: MenuBarDisplay(rawValue: store.menuBarDisplayRaw) ?? .allowance, windowID: store.pinnedWindowID,
                    hasError: store.errors[account.id] != nil, now: now)
                if let text = reading.text { Text(text).monospacedDigit() }
            }
            if !store.refreshing.isEmpty { Text("↻") }
        }
        .help(help(now: now))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("QuotaBar")
        .accessibilityValue(help(now: now))
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
