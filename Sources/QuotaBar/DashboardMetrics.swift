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
            let reset = accounts.flatMap { $0.snapshot?.windows ?? [] }.compactMap(\.resetsAt).filter { $0 > context.date }.min()
            let columns = [GridItem(.adaptive(minimum: 170), spacing: AppStyle.rowSpacing, alignment: .top)]
            LazyVGrid(columns: columns, spacing: AppStyle.rowSpacing) {
                MetricTile(title: "Connected", value: accounts.count.formatted(), detail: "subscription accounts", symbol: "person.2")
                MetricTile(title: "Available", value: presentationMode ? "—" : available.formatted(), detail: "accounts with allowance left", symbol: "checkmark.circle")
                MetricTile(title: "Next reset", value: presentationMode ? "—" : reset.map { countdown($0, now: context.date) } ?? "—", detail: "earliest upcoming window", symbol: "clock.arrow.circlepath")
            }
        }
    }
    private func countdown(_ date: Date, now: Date) -> String {
        let minutes = max(1, Int(ceil(date.timeIntervalSince(now) / 60)))
        if minutes >= 1440 { return "\(minutes / 1440)d \((minutes % 1440) / 60)h" }
        if minutes >= 60 { return "\(minutes / 60)h \(minutes % 60)m" }
        return "\(minutes)m"
    }
}
#endif
