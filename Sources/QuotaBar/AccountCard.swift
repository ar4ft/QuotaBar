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
    private var mainWindows: [UsageWindow] {
        let main = AccountAvailability.mainWindows(account)
        return main.isEmpty ? account.snapshot?.windows ?? [] : main
    }
    private var additionalWindows: [UsageWindow] {
        let ids = Set(mainWindows.map(\.id))
        return account.snapshot?.windows.filter { !ids.contains($0.id) } ?? []
    }
    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            HStack(spacing: 8) {
                AccountStatusLabel(status: availability.status, compact: true)
                Spacer(minLength: 0)
                if selectedForClient {
                    Label("Selected for CLI", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.medium)).foregroundStyle(AppStyle.signal)
                        .help("Last selected by QuotaBar for \(account.provider == .openAI ? "Codex" : "Claude Code")")
                }
            }
            if let snapshot = account.snapshot {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
                    ForEach(mainWindows) { window in
                        UsageMeter(window: window, tint: account.provider.tint, showRemaining: showRemaining)
                    }
                }
                if !additionalWindows.isEmpty || account.provider == .openAI || forecast != nil {
                    DisclosureGroup("Usage details") {
                        VStack(alignment: .leading, spacing: 16) {
                            CreditSummary(snapshot: snapshot, provider: account.provider)
                            ForEach(additionalWindows) { window in
                                UsageMeter(window: window, tint: account.provider.tint, showRemaining: showRemaining)
                            }
                            if let forecast { ForecastSummary(forecast: forecast) }
                        }.padding(.top, 10)
                    }.font(.caption).foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "chart.bar.xaxis").accessibilityHidden(true)
                    Text(refreshing ? "Reading subscription usage…" : "No usage reading yet")
                }.font(.callout).foregroundStyle(.secondary).padding(.vertical, 20)
            }
            if let error {
                VStack(alignment: .leading, spacing: 8) {
                    Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Reconnect account", action: reconnect).font(.caption)
                }
            }
            Spacer(minLength: 0)
            Divider()
            HStack(spacing: 8) {
                freshness
                Spacer(minLength: 4)
                Button(action: history) { Image(systemName: "chart.xyaxis.line") }
                    .buttonStyle(.borderless).help("Usage history and export")
                    .accessibilityLabel("Usage history for " + account.name)
                Button(selectedForClient ? "Use again" : "Use account", action: useAccount)
                    .buttonStyle(.bordered).tint(AppStyle.signal)
                    .disabled(refreshing)
                    .help(selectedForClient ? "Reapply this account if the CLI sign-in changed" : "Use this account in the CLI")
                    .accessibilityLabel(selectedForClient ? "Reapply \(account.name) in the CLI" : "Use \(account.name) in the CLI")
            }.controlSize(.small)
        }.padding(AppStyle.cardPadding).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .modifier(AccountSurface(selected: selectedForClient))
            .accessibilityElement(children: .contain)
    }
    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: account.provider.symbol)
                .font(.system(size: 18, weight: .medium)).foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .background(Color(nsColor: .quaternaryLabelColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(account.name).font(.headline).lineLimit(2).textSelection(.enabled)
                HStack(spacing: 5) {
                    Text(account.provider.title)
                    if let plan = account.snapshot?.plan { Text("·"); Text(plan.capitalized) }
                }.font(.caption).foregroundStyle(.secondary)
                if let detail = account.detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).textSelection(.enabled)
                }
            }
            Spacer(minLength: 0)
            Menu {
                Button("Use this account…", action: useAccount).disabled(refreshing)
                Button("History & export…", action: history)
                Divider()
                Button("Refresh", action: refresh).disabled(refreshing)
                Button("Reconnect…", action: reconnect)
                Button("Rename…", action: rename)
                Divider()
                Button("Remove account", role: .destructive, action: remove).disabled(refreshing)
            } label: {
                Image(systemName: "ellipsis").frame(width: 24, height: 24).contentShape(Rectangle())
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel("Actions for " + account.name).help("Account actions")
        }
    }
    @ViewBuilder private var freshness: some View {
        if refreshing {
            ProgressView().controlSize(.mini)
            Text("Refreshing…").font(.caption).foregroundStyle(.secondary)
        } else if let snapshot = account.snapshot {
            TimelineView(.periodic(from: .now, by: 60)) { _ in
                HStack(spacing: 4) {
                    Image(systemName: snapshot.isStale || error != nil ? "clock" : "checkmark.circle").accessibilityHidden(true)
                    Text(snapshot.isStale || error != nil ? "Last reading" : "Updated")
                    Text(snapshot.fetchedAt, style: .relative).lineLimit(1)
                }.font(.caption).foregroundStyle(.secondary)
                    .help("Last reading: " + snapshot.fetchedAt.formatted(date: .abbreviated, time: .shortened))
                    .accessibilityLabel("Last reading \(snapshot.fetchedAt.formatted(date: .abbreviated, time: .shortened))")
            }
        } else {
            Text("Awaiting reading").font(.caption).foregroundStyle(.secondary)
        }
    }
}
#endif
