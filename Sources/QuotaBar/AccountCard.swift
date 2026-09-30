#if os(macOS)
import SwiftUI
import QuotaCore

struct AccountCard: View {
    let account: Account
    let error: String?
    let refreshing: Bool
    let showRemaining: Bool
    let availability: AccountAvailability
    let history: () -> Void
    let refresh: () -> Void
    let reconnect: () -> Void
    let rename: () -> Void
    let remove: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: account.provider.symbol).font(.title3)
                    .foregroundStyle(account.provider.tint).frame(width: 42, height: 42)
                    .background(account.provider.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text(account.name).font(.headline).lineLimit(1)
                    Text(account.detail ?? account.provider.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Menu {
                    Button("Refresh", action: refresh)
                    Button("Reconnect…", action: reconnect)
                    Button("Rename…", action: rename)
                    Button("History & export…", action: history)
                    Divider(); Button("Remove account", role: .destructive, action: remove).disabled(refreshing)
                } label: { Image(systemName: "ellipsis").frame(width: 20, height: 20) }
                    .menuStyle(.borderlessButton).fixedSize()
            }
            Text(availability.status.title).font(.caption.weight(.medium))
                .foregroundStyle(availability.status.isAvailable ? account.provider.tint : .secondary)
            if let snapshot = account.snapshot {
                ForEach(snapshot.windows) { window in
                    UsageMeter(window: window, tint: account.provider.tint, showRemaining: showRemaining)
                }
            } else {
                Text(refreshing ? "Reading subscription usage…" : "No usage reading yet")
                    .font(.callout).foregroundStyle(.secondary).padding(.vertical, 14)
            }
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
                            Circle().fill(snapshot.isStale || error != nil ? Color.orange : account.provider.tint).frame(width: 5, height: 5)
                            Text(snapshot.isStale || error != nil ? "Last reading" : "Updated")
                            Text(snapshot.fetchedAt, style: .relative)
                        }.font(.caption).foregroundStyle(.secondary)
                    }
                } else { Text("Awaiting first reading").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button("History", action: history).buttonStyle(.plain).font(.caption).foregroundStyle(account.provider.tint)
                if let plan = account.snapshot?.plan { Text(plan.capitalized).font(.caption.weight(.medium)).foregroundStyle(.secondary) }
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
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
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(tint.opacity(0.12))
                    Capsule().fill(window.usedPercent >= 90 ? Color.orange : tint)
                        .frame(width: max(0, proxy.size.width * (awaitingReset ? 0 : showRemaining ? window.remainingPercent : window.usedPercent) / 100))
                }
            }.frame(height: 6).accessibilityLabel(window.title)
                .accessibilityValue(awaitingReset ? "Awaiting reset confirmation" : "\(Int(window.usedPercent)) percent used")
                Text(window.resetDescription(now: context.date)).font(.caption).foregroundStyle(.secondary)
                    .help(window.resetsAt.map { $0.formatted(date: .complete, time: .shortened) } ?? "Provider did not report a reset")
            }
        }
    }
}
#endif
