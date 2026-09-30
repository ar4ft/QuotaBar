#if os(macOS)
import SwiftUI
import QuotaCore

extension Provider {
    var tint: Color { self == .openAI ? Color(red: 0.13, green: 0.60, blue: 0.46) : Color(red: 0.78, green: 0.44, blue: 0.30) }
    var symbol: String { self == .openAI ? "sparkle" : "sun.max" }
}
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
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 10) {
                    Image(systemName: "chart.bar.xaxis").font(.title2).foregroundStyle(.mint)
                    Text("QuotaBar").font(.title3.weight(.semibold))
                }.padding(.horizontal, 20).padding(.top, 24)
                Text("WORKSPACE").font(.system(size: 10, weight: .semibold)).tracking(1.5)
                    .foregroundStyle(.secondary).padding(.horizontal, 20)
                List(AccountFilter.allCases, selection: $filter) { item in
                    HStack {
                        Label(item.title, systemImage: item.symbol)
                        Spacer()
                        Text("\(count(item))").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }.padding(.vertical, 5).tag(item)
                }.listStyle(.sidebar)
                Spacer()
                VStack(alignment: .leading, spacing: 8) {
                    Label("Stored on this Mac", systemImage: "lock.shield").font(.caption.weight(.medium))
                    Text("Independent accounts.\nOne clear view of your limits.")
                        .font(.caption).foregroundStyle(.secondary).lineSpacing(3)
                }.padding(20)
            }.navigationSplitViewColumnWidth(min: 190, ideal: 215, max: 260)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header
                    HStack(spacing: 16) {
                        MetricTile(title: "CONNECTED", value: "\(filtered.count)", detail: "subscription accounts", symbol: "person.2")
                        MetricTile(title: "AVAILABLE", value: "\(filtered.filter { store.availability($0).status.isAvailable }.count)", detail: "accounts with allowance left", symbol: "checkmark.circle")
                        MetricTile(title: "NEXT RESET", value: nextReset, detail: "earliest upcoming window", symbol: "clock.arrow.circlepath")
                    }
                    HStack {
                        Text("YOUR ACCOUNTS").font(.system(size: 11, weight: .semibold)).tracking(1.5).foregroundStyle(.secondary)
                        Spacer()
                        Toggle("Available only", isOn: $availableOnly).toggleStyle(.button).controlSize(.small)
                        Picker("Sort accounts", selection: $store.accountSortRaw) {
                            ForEach(AccountSort.allCases) { Text($0.title).tag($0.rawValue) }
                        }.labelsHidden().frame(width: 175)
                        Picker("Layout", selection: $listLayout) {
                            Image(systemName: "square.grid.2x2").tag(false)
                            Image(systemName: "list.bullet").tag(true)
                        }.pickerStyle(.segmented).frame(width: 90)
                    }
                    if store.accounts.isEmpty { emptyState }
                    else if filtered.isEmpty {
                        ContentUnavailableView("No matching accounts", systemImage: "line.3.horizontal.decrease.circle",
                                               description: Text("Try another search or turn off the availability filter."))
                    } else if listLayout {
                        LazyVStack(spacing: 12) { ForEach(filtered) { account in card(account) } }
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], alignment: .leading, spacing: 16) {
                            ForEach(filtered) { account in card(account) }
                        }
                    }
                    Text("OpenAI readings reflect Codex allowance. Limits and reset times come from each provider.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(30).frame(maxWidth: 1350)
            }.background(Color(nsColor: .windowBackgroundColor))
            .navigationTitle("")
            .searchable(text: $search, placement: .toolbar, prompt: "Find an account")
            .toolbar {
                ToolbarItem {
                    Button { Task { await store.refreshAll() } } label: { Image(systemName: "arrow.clockwise") }
                        .help("Refresh all accounts").disabled(!store.refreshing.isEmpty)
                }
            }
        }
        .sheet(item: $store.presentedConnection) { request in ConnectAccountView(request: request).environmentObject(store) }
        .sheet(item: $historyAccount) { account in UsageHistoryView(account: account).environmentObject(store) }
        .alert("Rename account", isPresented: Binding(get: { renameAccount != nil }, set: { if !$0 { renameAccount = nil } })) {
            TextField("Account name", text: $newName)
            Button("Cancel", role: .cancel) { renameAccount = nil }
            Button("Save") { if let account = renameAccount { store.rename(account.id, name: newName) }; renameAccount = nil }
        }
        .alert("Remove this account?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Cancel", role: .cancel) { deleting = nil }
            Button("Remove", role: .destructive) { if let account = deleting { store.remove(account.id) }; deleting = nil }
        } message: { Text("This removes its saved credentials from QuotaBar and Keychain.") }
        .alert("Storage error", isPresented: Binding(get: { store.globalError != nil }, set: { if !$0 { store.globalError = nil } })) {
            Button("OK") { store.globalError = nil }
        } message: { Text(store.globalError ?? "") }
    }
    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Account overview").font(.system(size: 30, weight: .semibold, design: .rounded))
                Text("Keep an eye on usage. Know when you’re ready again.").foregroundStyle(.secondary)
            }
            Spacer()
            Button { store.connect() } label: { Label("Add account", systemImage: "plus") }
                .buttonStyle(.borderedProminent).tint(.primary).controlSize(.large)
        }
    }
    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "person.crop.circle.badge.plus").font(.system(size: 42, weight: .light)).foregroundStyle(.mint)
            Text("Your accounts, together").font(.title2.weight(.semibold))
            Text("Connect OpenAI or Claude to see usage windows and upcoming resets here and in your menu bar.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 390)
            Button("Connect your first account") { store.connect() }.buttonStyle(.borderedProminent)
        }.frame(maxWidth: .infinity).padding(.vertical, 65)
            .background(.background, in: RoundedRectangle(cornerRadius: 18))
    }
    private func card(_ account: Account) -> some View {
        AccountCard(account: account, error: store.errors[account.id], refreshing: store.refreshing.contains(account.id),
                    showRemaining: store.showRemaining, availability: store.availability(account),
                    history: { historyAccount = account },
                    refresh: { Task { await store.refresh(account.id) } }, reconnect: { store.connect(account) },
                    rename: { newName = account.name; renameAccount = account }, remove: { deleting = account })
    }
    private func count(_ item: AccountFilter) -> Int {
        store.accounts.filter { item == .all || $0.provider.rawValue == item.rawValue }.count
    }
    private var nextReset: String {
        guard let date = filtered.flatMap({ $0.snapshot?.windows ?? [] }).compactMap(\.resetsAt).filter({ $0 > Date() }).min() else { return "—" }
        let hours = max(1, Int(ceil(date.timeIntervalSinceNow / 3600)))
        if hours >= 24 { return "\(hours / 24)d \(hours % 24)h" }
        return "\(hours)h"
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
                Text(title).font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(.secondary)
                Spacer(); Image(systemName: symbol).foregroundStyle(.secondary)
            }
            Text(value).font(.system(size: 28, weight: .medium, design: .rounded)).monospacedDigit()
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 14))
    }
}
#endif
