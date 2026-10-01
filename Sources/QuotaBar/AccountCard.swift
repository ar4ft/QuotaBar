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
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: account.provider.symbol).accessibilityHidden(true).font(.title3)
                    .foregroundStyle(account.provider.tint).frame(width: 42, height: 42)
                    .background(account.provider.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text(account.name).font(.headline).lineLimit(2).textSelection(.enabled)
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
                } label: { Image(systemName: "ellipsis").frame(width: 20, height: 20) }
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
                Button("History…", action: history).controlSize(.small).accessibilityLabel("Usage history for " + account.name)
                if let plan = account.snapshot?.plan { Text(plan.capitalized).font(.caption.weight(.medium)).foregroundStyle(.secondary) }
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .modifier(AccountSurface())
            .accessibilityElement(children: .contain)
    }
}

struct CreditSummary: View {
    let snapshot: UsageSnapshot
    let provider: Provider
    var body: some View {
        if provider == .openAI {
            VStack(alignment: .leading, spacing: 4) {
                Label("Credits: " + (snapshot.credits?.display ?? "Not reported"), systemImage: "creditcard")
                Text(snapshot.availableResetCredits.map { "Reset credits available: \($0)" } ?? "Reset credits: Not reported")
            }.font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct UsageMeter: View {
    let window: UsageWindow
    let tint: Color
    let showRemaining: Bool
    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            let awaitingReset = window.resetsAt.map { $0 <= context.date } ?? false
            VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.title).font(.callout.weight(.medium))
                Spacer()
                Text(awaitingReset ? "—" : "\(Int((showRemaining ? window.remainingPercent : window.usedPercent).rounded()))%")
                    .font(.system(.callout, design: .rounded).weight(.semibold)).monospacedDigit()
                Text(showRemaining ? "left" : "used").font(.caption).foregroundStyle(.secondary)
            }
            ProgressView(value: awaitingReset ? 0 : showRemaining ? window.remainingPercent : window.usedPercent, total: 100)
                .progressViewStyle(.linear).tint(window.usedPercent >= 90 ? .orange : tint)
                .accessibilityHidden(true)
                Text(window.resetDescription(now: context.date)).font(.caption).foregroundStyle(.secondary)
                    .help(window.resetsAt.map { $0.formatted(date: .complete, time: .shortened) } ?? "Provider did not report a reset")
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(window.title)
            .accessibilityValue(awaitingReset ? "Reset reached; refresh to confirm allowance" :
                "\(Int(window.usedPercent.rounded())) percent used, \(window.resetDescription(now: context.date))")
        }
    }
}
#endif
