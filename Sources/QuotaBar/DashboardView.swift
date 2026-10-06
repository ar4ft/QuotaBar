#if os(macOS)
import SwiftUI
import AppKit
import QuotaCore

struct DashboardView: View {
    @EnvironmentObject private var store: AccountStore
    @Environment(\.openWindow) private var openWindow
    @State private var filter: AccountFilter? = .all
    @State private var search = ""
    @AppStorage("listLayout") private var listLayout = false
    @State private var renameAccount: Account?
    @State private var newName = ""
    @State private var deleting: Account?
    @State private var historyAccount: Account?
    @State private var availableOnly = false
    private var filtered: [Account] {
        store.orderedAccounts.filter {
            (filter == nil || filter == .all || $0.provider.rawValue == filter?.rawValue) &&
            (search.isEmpty || $0.name.localizedStandardContains(search) || ($0.detail?.localizedStandardContains(search) ?? false)) &&
            (!availableOnly || store.availability($0).status.isAvailable)
        }
    }
    var body: some View {
        NavigationSplitView {
            List(selection: $filter) {
                Section("Accounts") {
                    ForEach(AccountFilter.allCases) { item in
                        HStack {
                            Label(item.title, systemImage: item.symbol)
                                .foregroundStyle(.primary)
                            Spacer()
                            Text("\(count(item))").monospacedDigit().foregroundStyle(.secondary)
                        }.tag(item)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("\(item.title), \(count(item)) connected")
                    }
                }
            }.listStyle(.sidebar)
                .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 280)
                .safeAreaInset(edge: .bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Runs in your menu bar", systemImage: "menubar.rectangle")
                        Label("Stored on this Mac", systemImage: "lock.shield")
                    }.font(.caption).foregroundStyle(.secondary).padding(16)
                }
        } detail: {
            ScrollView {
                let accounts = filtered
                VStack(alignment: .leading, spacing: AppStyle.sectionSpacing) {
                    if !store.accounts.isEmpty {
                        DashboardMetrics(accounts: accounts, presentationMode: store.presentationMode,
                                         errorIDs: Set(store.errors.keys))
                        Divider()
                        ViewThatFits(in: .horizontal) {
                            HStack { Text("Accounts").font(.headline); Spacer(); accountControls }
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Accounts").font(.headline)
                                HStack { accountControls }
                            }
                        }
                    }
                    if store.accounts.isEmpty { emptyState }
                    else if accounts.isEmpty {
                        ContentUnavailableView("No matching accounts", systemImage: "line.3.horizontal.decrease.circle",
                                               description: Text("Try another search or turn off the availability filter."))
                    } else if listLayout {
                        LazyVStack(spacing: 12) { ForEach(accounts) { account in card(account) } }
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
                            ForEach(accounts) { account in card(account) }
                        }
                    }
                    Button {
                        store.showConnectionHealth = true
                    } label: {
                        Label(store.presentationMode ? "Connection health" : store.attentionCount == 0 ? "All connections healthy" : "\(store.attentionCount) connections need attention", systemImage: "network")
                    }.buttonStyle(.plain).foregroundStyle(.secondary)
                    Text("OpenAI readings reflect Codex allowance. Limits and reset times come from each provider.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(AppStyle.pagePadding).frame(maxWidth: 1350)
            }.background(Color(nsColor: .windowBackgroundColor))
            .navigationTitle(filter?.title ?? "All accounts")
            .navigationSubtitle(store.accounts.isEmpty ? "Subscription accounts" : "\(filtered.count) accounts")
            .searchable(text: $search, placement: .toolbar, prompt: "Find an account")
            .toolbar {
                ToolbarItemGroup {
                    Toggle(isOn: $store.presentationMode) {
                        Label("Presentation mode", systemImage: store.presentationMode ? "eye.slash.fill" : "eye")
                    }.toggleStyle(.button)
                        .help("Hide account details and silence usage alerts")
                        .accessibilityLabel("Presentation mode")
                    Button { Task { await store.refreshAll() } } label: {
                        Label("Refresh accounts", systemImage: "arrow.clockwise")
                    }.help("Refresh all accounts").disabled(!store.refreshing.isEmpty)
                    Button { store.connect() } label: { Label("Add account", systemImage: "plus") }
                        .help("Add an account").disabled(store.presentationMode)
                    Button { DashboardWindowController.keepRunningInMenuBar() } label: {
                        Label("Keep Running in Menu Bar", systemImage: "menubar.rectangle")
                    }.help("Close the dashboard and keep monitoring in the menu bar")
                }
            }
        }
        .tint(AppStyle.signal)
        .frame(minWidth: 740, minHeight: 500)
        .background(DashboardWindowBridge().frame(width: 0, height: 0))
        .task {
            StartupDiagnostics.verifyResponsivenessIfRequested(reopenDashboard: {
                DashboardWindowController.showDashboard { openWindow(id: "dashboard") }
            }, clock: { store.clock })
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
            guard let window = notification.object as? NSWindow,
                  window === DashboardWindowController.window else { return }
            NSApplication.shared.setActivationPolicy(.accessory)
        }
        .onChange(of: store.presentationMode) { _, hidden in
            if hidden { search = ""; availableOnly = false; renameAccount = nil; deleting = nil; historyAccount = nil }
        }
        .sheet(item: $store.presentedConnection) { request in ConnectAccountView(request: request).environmentObject(store) }
        .sheet(item: $store.presentedSwitch) { account in ClientSwitchView(account: account).environmentObject(store) }
        .sheet(isPresented: $store.showConnectionHealth) { ConnectionHealthView().environmentObject(store) }
        .sheet(item: $historyAccount) { account in UsageHistoryView(account: account).environmentObject(store) }
        .alert("Rename account", isPresented: Binding(get: { renameAccount != nil }, set: { if !$0 { renameAccount = nil } })) {
            TextField("Account name", text: $newName)
            Button("Cancel", role: .cancel) { renameAccount = nil }.keyboardShortcut(.cancelAction)
            Button("Save") { if let account = renameAccount { store.rename(account.id, name: newName) }; renameAccount = nil }.keyboardShortcut(.defaultAction)
        }
        .alert("Remove this account?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Cancel", role: .cancel) { deleting = nil }
            Button("Remove", role: .destructive) { if let account = deleting { store.remove(account.id) }; deleting = nil }
        } message: { Text("This removes the account, its saved QuotaBar credentials, and its recorded usage history. It does not sign the CLI out or delete recovery backups.") }
        .alert("Storage error", isPresented: Binding(get: { store.globalError != nil }, set: { if !$0 { store.globalError = nil } })) {
            Button("OK") { store.globalError = nil }
        } message: { Text(store.globalError ?? "") }
    }
    @ViewBuilder private var accountControls: some View {
        Toggle("Available only", isOn: $availableOnly).disabled(store.presentationMode).toggleStyle(.checkbox)
        Picker("Sort accounts", selection: $store.accountSortRaw) {
            ForEach(AccountSort.allCases) { Text($0.title).tag($0.rawValue) }
        }.labelsHidden().frame(width: 170).accessibilityLabel("Sort accounts")
        Picker("Layout", selection: $listLayout) {
            Label("Grid", systemImage: "square.grid.2x2").tag(false)
            Label("List", systemImage: "list.bullet").tag(true)
        }.labelsHidden().pickerStyle(.segmented).frame(width: 100).accessibilityLabel("Account layout")
    }
    private var emptyState: some View {
        ContentUnavailableView {
            Label("Connect your accounts", systemImage: "person.crop.circle.badge.plus")
        } description: {
            Text("Add an OpenAI or Claude account to see usage and upcoming resets.")
        } actions: {
            Button("Add account") { store.connect() }.buttonStyle(.borderedProminent).disabled(store.presentationMode)
        }.frame(maxWidth: .infinity).padding(.vertical, 40)
    }
    private func card(_ account: Account) -> some View {
        AccountCard(account: account, error: store.errors[account.id], refreshing: store.refreshing.contains(account.id),
                    showRemaining: store.showRemaining, presentationMode: store.presentationMode, forecast: store.forecast(account), availability: store.availability(account),
                    history: { historyAccount = account },
                    refresh: { Task { await store.refresh(account.id) } }, reconnect: { store.connect(account) },
                    rename: { newName = account.name; renameAccount = account }, remove: { deleting = account },
                    useAccount: { store.requestSwitch(account) }, selectedForClient: store.activeAccountID(account.provider) == account.id.uuidString)
    }
    private func count(_ item: AccountFilter) -> Int {
        store.accounts.filter { item == .all || $0.provider.rawValue == item.rawValue }.count
    }
}
#endif
