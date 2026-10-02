#if os(macOS)
import SwiftUI
import QuotaCore

struct MetricTile: View {
    let title: String
    let value: String
    let detail: String
    let symbol: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.callout).foregroundStyle(.secondary)
                Spacer(); Image(systemName: symbol).foregroundStyle(.secondary).accessibilityHidden(true)
            }
            Text(value).font(.title.weight(.semibold)).monospacedDigit()
            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2, reservesSpace: true)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .modifier(AccountSurface())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title).accessibilityValue(value + ", " + detail)
    }
}
#endif
