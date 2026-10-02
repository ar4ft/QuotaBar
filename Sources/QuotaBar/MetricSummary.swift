#if os(macOS)
struct MetricSummary: Identifiable {
    let title: String
    let value: String
    let detail: String
    let symbol: String
    var id: String { title }
}
#endif
