#if os(macOS)
import SwiftUI
import QuotaCore

struct DashboardMetrics: View {
    let accounts: [Account]
    let presentationMode: Bool
    let errorIDs: Set<UUID>
    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            let available = accounts.count { AccountAvailability.make($0, hasError: errorIDs.contains($0.id), now: context.date).status.isAvailable }
            let next = accounts.flatMap { account in
                (account.snapshot?.windows ?? []).compactMap { window -> ResetSummary? in
                    guard let date = window.resetsAt, date > context.date else { return nil }
                    return ResetSummary(date: date, detail: account.name + " · " + window.title)
                }
            }.min { $0.date < $1.date }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .bottom, spacing: 40) {
                    resetSummary(next, now: context.date)
                    Spacer(minLength: 16)
                    connectionSummary(available: available)
                }
                VStack(alignment: .leading, spacing: 20) {
                    resetSummary(next, now: context.date)
                    connectionSummary(available: available)
                }
            }
        }
    }
    private struct ResetSummary {
        let date: Date
        let detail: String
    }
    private func resetSummary(_ reset: ResetSummary?, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Next reset").font(.callout).foregroundStyle(.secondary)
            Text(presentationMode ? "—" : reset.map { countdown($0.date, now: now) } ?? "—")
                .font(.largeTitle.bold()).monospacedDigit().tracking(-0.8)
            Text(presentationMode ? "Reset details hidden" : reset?.detail ?? "No upcoming reset reported")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.accessibilityElement(children: .combine)
    }
    private func connectionSummary(available: Int) -> some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Connected").font(.callout).foregroundStyle(.secondary)
                Text(accounts.count.formatted()).font(.title3.bold()).monospacedDigit()
                Text("subscription accounts").font(.caption).foregroundStyle(.secondary)
            }.accessibilityElement(children: .combine)
            VStack(alignment: .leading, spacing: 6) {
                Text("With allowance").font(.callout).foregroundStyle(.secondary)
                Text(presentationMode ? "—" : available.formatted()).font(.title3.bold()).monospacedDigit()
                Text("including running low").font(.caption).foregroundStyle(.secondary)
            }.accessibilityElement(children: .combine)
        }.fixedSize(horizontal: true, vertical: false)
    }
    private func countdown(_ date: Date, now: Date) -> String {
        let minutes = max(1, Int(ceil(date.timeIntervalSince(now) / 60)))
        if minutes >= 1440 { return "\(minutes / 1440)d \((minutes % 1440) / 60)h" }
        if minutes >= 60 { return "\(minutes / 60)h \(minutes % 60)m" }
        return "\(minutes)m"
    }
}
#endif
