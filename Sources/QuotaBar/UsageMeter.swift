#if os(macOS)
import SwiftUI
import QuotaCore

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
                Text(awaitingReset ? "—" : AllowancePercent.display(showRemaining ? window.remainingPercent : window.usedPercent))
                    .font(.title3.bold()).monospacedDigit()
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
                "\(AllowancePercent.spoken(showRemaining ? window.remainingPercent : window.usedPercent)) \(showRemaining ? "left" : "used"), \(window.resetDescription(now: context.date))")
        }
    }
}
#endif
