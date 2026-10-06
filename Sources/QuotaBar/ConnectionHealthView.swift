#if os(macOS)
import SwiftUI
import QuotaCore

struct ConnectionHealthView: View {
    @EnvironmentObject private var store: AccountStore
    @Environment(\.dismiss) private var dismiss
    private var accounts: [Account] {
        store.orderedAccounts.sorted { store.health($0).needsAttention && !store.health($1).needsAttention }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Connection health").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if store.presentationMode {
                ContentUnavailableView("Account details hidden", systemImage: "eye.slash",
                                       description: Text("Turn off presentation mode to inspect connections."))
            } else if accounts.isEmpty {
                ContentUnavailableView("No connected accounts", systemImage: "person.crop.circle")
            } else {
                Text("\(store.attentionCount) \(store.attentionCount == 1 ? "account needs" : "accounts need") attention. Usage limits do not count as connection failures.")
                    .font(.caption).foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(accounts) { account in
                            let health = store.health(account)
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(account.name).font(.headline)
                                    Text(account.provider.title).font(.caption).foregroundStyle(.secondary)
                                    Spacer()
                                    if store.refreshing.contains(account.id) { ProgressView().controlSize(.small) }
                                    Button(store.connectionIssues[account.id] == .keychainAccess ? "Allow Keychain access…" : health.needsReconnect ? "Reconnect…" : "Refresh") {
                                        if store.connectionIssues[account.id] == .keychainAccess { Task { await store.allowKeychainAccess(account.id) } }
                                        else if health.needsReconnect { dismiss(); store.connect(account) }
                                        else { Task { await store.refresh(account.id) } }
                                    }.disabled(store.refreshing.contains(account.id) || (store.retryDate(account.id).map { $0 > store.clock } ?? false))
                                }
                                Label(health.title, systemImage: health.needsAttention ? "exclamationmark.circle" : "checkmark.circle")
                                    .foregroundStyle(health.needsAttention ? Color.orange : Color.green)
                                Text(health.lastSuccess.map { "Last successful refresh: " + $0.formatted(date: .abbreviated, time: .shortened) } ?? "No successful refresh yet")
                                    .font(.caption).foregroundStyle(.secondary)
                                if let retry = store.retryDate(account.id), retry > store.clock {
                                    Text("Retry after " + retry.formatted(date: .omitted, time: .shortened)).font(.caption)
                                }
                                if let error = store.errors[account.id] { Text(error).font(.caption).foregroundStyle(.secondary) }
                            }
                            Divider()
                        }
                    }
                }
            }
        }.padding(24).frame(minWidth: 520, idealWidth: 660, maxWidth: .infinity, minHeight: 380, idealHeight: 520, maxHeight: .infinity)
    }
}

struct ForecastSummary: View {
    let forecast: UsageForecast
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(forecast.resetArrivesFirst ? "At recent pace, reset arrives before the limit" :
                    "Estimated limit: " + forecast.estimatedLimitAt.formatted(date: .abbreviated, time: .shortened), systemImage: "chart.line.uptrend.xyaxis")
            Text("Estimate from \(forecast.sampleCount) readings · \(forecast.percentPerHour.formatted(.number.precision(.fractionLength(0...1)))) percentage points/hour. Pace can change.")
                .foregroundStyle(.secondary)
        }.font(.caption)
    }
}
#endif
