#if os(macOS)
import SwiftUI
import QuotaCore

struct MenuBarSettings: View {
    @EnvironmentObject private var store: AccountStore
    var body: some View {
        Form {
            Section("Menu bar") {
                Picker("Display", selection: $store.menuBarDisplayRaw) {
                    ForEach(MenuBarDisplay.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Picker("Pinned account", selection: Binding(get: { store.pinnedAccountID }, set: { store.pinAccount($0) })) {
                    Text("No pinned account").tag("")
                    ForEach(store.accounts) { Text(store.presentationMode ? $0.provider.title + " account" : "\($0.name) · \($0.provider.title)").tag($0.id.uuidString) }
                }
                if let account = store.pinnedAccount {
                    Picker("Allowance window", selection: $store.pinnedWindowID) {
                        Text("Most constrained window").tag("")
                        ForEach(account.snapshot?.windows ?? []) { Text($0.title).tag($0.id) }
                        if !store.pinnedWindowID.isEmpty, !(account.snapshot?.windows.contains { $0.id == store.pinnedWindowID } ?? false) {
                            Text("Selected window unavailable").tag(store.pinnedWindowID)
                        }
                    }
                }
                Text("Shows your selected reading beside the menu bar icon. Credits are reported for eligible OpenAI accounts; missing balances remain unknown. A ~ marks a stale reading; — means no reading or a reset awaiting confirmation.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 8, for: .scrollContent)
        .softScrollEdges()
    }

}
#endif
