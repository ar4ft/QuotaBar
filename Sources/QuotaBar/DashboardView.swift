#if os(macOS)
import SwiftUI
import QuotaCore

private enum AccountFilter: String, CaseIterable, Identifiable {
    case all, openAI, claude
    var id: String { rawValue }
    var title: String { self == .all ? "All accounts" : self == .openAI ? "OpenAI" : "Claude" }
    var symbol: String { self == .all ? "square.grid.2x2" : self == .openAI ? "sparkle" : "sun.max" }
}
struct DashboardView: View {
    @EnvironmentObject private var store: AccountStore
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
            (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || ($0.detail?.localizedCaseInsensitiveContains(search) ?? false)) &&
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
                    Label("Stored on this Mac", systemImage: "lock.shield")
                        .font(.caption).foregroundStyle(.secondary).padding(16)
                }
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    Button {
                        store.showConnectionHealth = true
                    } label: {
                        Label(store.presentationMode ? "Connection health" : "Connection health · \(store.attentionCount) need attention",
                              systemImage: "network")
                    }.buttonStyle(.plain).foregroundStyle(.secondary)
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 12) { metrics }
                        VStack(spacing: 12) { metrics }
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack { accountControls }
                        VStack(alignment: .leading, spacing: 12) { accountControls }
                    }
                    if store.accounts.isEmpty { emptyState }
                    else if filtered.isEmpty {
                        ContentUnavailableView("No matching accounts", systemImage: "line.3.horizontal.decrease.circle",
                                               description: Text("Try another search or turn off the availability filter."))
                    } else if listLayout {
                        LazyVStack(spacing: 12) { ForEach(filtered) { account in card(account) } }
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
                            ForEach(filtered) { account in card(account) }
                        }
                    }
                    Text("OpenAI readings reflect Codex allowance. Limits and reset times come from each provider.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(24).frame(maxWidth: 1350)
            }.background(Color(nsColor: .windowBackgroundColor))
            .navigationTitle(filter?.title ?? "All accounts")
            .navigationSubtitle("\(filtered.count) connected")
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
                }
            }
        }
        .frame(minWidth: 740, minHeight: 500)
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
        } message: { Text("This removes the account, its credentials from Keychain, and its recorded usage history.") }
        .alert("Storage error", isPresented: Binding(get: { store.globalError != nil }, set: { if !$0 { store.globalError = nil } })) {
            Button("OK") { store.globalError = nil }
        } message: { Text(store.globalError ?? "") }
    }
    @ViewBuilder private var metrics: some View {
        MetricTile(title: "Connected", value: "\(filtered.count)", detail: "subscription accounts", symbol: "person.2")
        MetricTile(title: "Available", value: store.presentationMode ? "—" : "\(filtered.filter { store.availability($0).status.isAvailable }.count)", detail: "accounts with allowance left", symbol: "checkmark.circle")
        MetricTile(title: "Next reset", value: store.presentationMode ? "—" : nextReset, detail: "earliest upcoming window", symbol: "clock.arrow.circlepath")
    }
    @ViewBuilder private var accountControls: some View {
        Text("Accounts").font(.headline).accessibilityAddTraits(.isHeader)
        Spacer(minLength: 12)
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
    private var nextReset: String {
        guard let date = filtered.flatMap({ $0.snapshot?.windows ?? [] }).compactMap(\.resetsAt).filter({ $0 > Date() }).min() else { return "—" }
        let minutes = max(1, Int(ceil(date.timeIntervalSinceNow / 60)))
        if minutes >= 1440 { return "\(minutes / 1440)d \((minutes % 1440) / 60)h" }
        if minutes >= 60 { return "\(minutes / 60)h \(minutes % 60)m" }
        return "\(minutes)m"
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let detail: String
    let symbol: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.callout).foregroundStyle(.secondary)
                Spacer(); Image(systemName: symbol).foregroundStyle(.secondary).accessibilityHidden(true)
            }
            Text(value).font(.title.weight(.semibold)).monospacedDigit()
            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2, reservesSpace: true)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .modifier(AccountSurface())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title).accessibilityValue(value + ", " + detail)
    }
}
#endif
