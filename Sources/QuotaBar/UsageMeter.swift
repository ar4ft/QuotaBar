#if os(macOS)
import SwiftUI
import QuotaCore

struct UsageMeter: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let window: UsageWindow
    let tint: Color
    let showRemaining: Bool
    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            let awaitingReset = window.resetsAt.map { $0 <= context.date } ?? false
            let percent = showRemaining ? window.remainingPercent : window.usedPercent
            VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.title).font(.callout.weight(.medium))
                Spacer()
                Text(awaitingReset ? "—" : AllowancePercent.display(showRemaining ? window.remainingPercent : window.usedPercent))
                    .font(.title.bold()).monospacedDigit().tracking(-0.5)
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: percent)
                Text(showRemaining ? "left" : "used").font(.caption).foregroundStyle(.secondary)
            }
            AllowanceTrack(percent: awaitingReset ? 0 : percent,
                           tint: window.usedPercent >= 80 ? .orange : tint)
                .accessibilityHidden(true).help("Quarter marks indicate 25%, 50%, and 75%")
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
