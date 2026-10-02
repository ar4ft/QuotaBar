#if os(macOS)
import SwiftUI
import QuotaCore

struct MetricTile: View {
    let summary: MetricSummary
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(summary.title).font(.callout).foregroundStyle(.secondary)
                Spacer(); Image(systemName: summary.symbol).foregroundStyle(.secondary).accessibilityHidden(true)
            }
            Text(summary.value).font(.title.bold()).monospacedDigit()
            Text(summary.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2, reservesSpace: true)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .modifier(AccountSurface())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(summary.title).accessibilityValue(summary.value + ", " + summary.detail)
    }
}
#endif
