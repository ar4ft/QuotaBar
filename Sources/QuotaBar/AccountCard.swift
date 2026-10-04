#if os(macOS)
import SwiftUI
import QuotaCore

struct AccountCard: View {
    let account: Account
    let error: String?
    let refreshing: Bool
    let showRemaining: Bool
    let presentationMode: Bool
    let forecast: UsageForecast?
    let availability: AccountAvailability
    let history: () -> Void
    let refresh: () -> Void
    let reconnect: () -> Void
    let rename: () -> Void
    let remove: () -> Void
    let useAccount: () -> Void
    let selectedForClient: Bool
    var body: some View {
        Group {
        if presentationMode {
            VStack(alignment: .leading, spacing: 12) {
                Label(account.provider.title + " account", systemImage: account.provider.symbol)
                Text("Account details and balances hidden").font(.caption).foregroundStyle(.secondary)
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .modifier(AccountSurface())
        } else { content }
        }
    }
    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: account.provider.symbol).accessibilityHidden(true).font(.title3)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(account.name).font(.headline).lineLimit(2).textSelection(.enabled)
                    Text(account.provider.title).font(.caption).foregroundStyle(.secondary)
                    Text(account.detail ?? account.provider.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Menu {
                    Button("Use this account…", action: useAccount)
                    Divider()
                    Button("Refresh", action: refresh)
                    Button("Reconnect…", action: reconnect)
                    Button("Rename…", action: rename)
                    Button("History & export…", action: history)
                    Divider(); Button("Remove account", role: .destructive, action: remove).disabled(refreshing)
                } label: { Label("Account actions", systemImage: "ellipsis").labelStyle(.iconOnly) }
                    .menuStyle(.borderlessButton).fixedSize()
                    .accessibilityLabel("Actions for " + account.name).help("Account actions")
            }
            AccountStatusLabel(status: availability.status)
            if selectedForClient {
                Label("Selected for \(account.provider == .openAI ? "Codex" : "Claude Code")", systemImage: "person.crop.circle.badge.checkmark")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let snapshot = account.snapshot {
                CreditSummary(snapshot: snapshot, provider: account.provider)
                ForEach(snapshot.windows) { window in
                    UsageMeter(window: window, tint: account.provider.tint, showRemaining: showRemaining)
                }
            } else {
                Text(refreshing ? "Reading subscription usage…" : "No usage reading yet")
                    .font(.callout).foregroundStyle(.secondary).padding(.vertical, 14)
            }
            if let forecast { ForecastSummary(forecast: forecast) }
            if let error {
                VStack(alignment: .leading, spacing: 8) {
                    Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Reconnect account", action: reconnect).font(.caption)
                }
            }
            Divider()
            HStack {
                if refreshing { ProgressView().controlSize(.mini); Text("Refreshing…").font(.caption).foregroundStyle(.secondary) }
                else if let snapshot = account.snapshot {
                    TimelineView(.periodic(from: .now, by: 60)) { _ in
                        HStack(spacing: 5) {
                            Image(systemName: snapshot.isStale || error != nil ? "clock" : "checkmark.circle").accessibilityHidden(true)
                            Text(snapshot.isStale || error != nil ? "Last reading" : "Updated")
                            Text(snapshot.fetchedAt, style: .relative)
                        }.font(.caption).foregroundStyle(.secondary)
                    }
                } else { Text("Awaiting first reading").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                if let plan = account.snapshot?.plan { Text(plan.capitalized).font(.caption.weight(.medium)).foregroundStyle(.secondary) }
            }
            HStack {
                Button(selectedForClient ? "Use again" : "Use account",
                       systemImage: "arrow.left.arrow.right", action: useAccount)
                    .disabled(refreshing)
                    .help("Reapply this account if the CLI sign-in changed outside QuotaBar")
                    .accessibilityLabel(selectedForClient ? "Reapply \(account.name) in the CLI" : "Use \(account.name) in the CLI")
                Spacer()
                Button("History", systemImage: "chart.xyaxis.line", action: history)
                    .accessibilityLabel("Usage history for " + account.name)
            }.controlSize(.small)
        }.padding(AppStyle.cardPadding).frame(maxWidth: .infinity, alignment: .leading)
            .modifier(AccountSurface(selected: selectedForClient))
            .accessibilityElement(children: .contain)
    }
}
#endif
