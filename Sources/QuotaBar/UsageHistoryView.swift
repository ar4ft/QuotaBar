#if os(macOS)
import SwiftUI
import Charts
import UniformTypeIdentifiers
import QuotaCore

private enum HistoryRange: Int, CaseIterable, Identifiable {
    case day = 1, week = 7, month = 30
    var id: Int { rawValue }
    var title: String { self == .day ? "24 hours" : self == .week ? "7 days" : "30 days" }
}
private struct HistoryWindow: Identifiable { var id: String; var title: String }
struct UsageHistoryView: View {
    @EnvironmentObject private var store: AccountStore
    @Environment(\.dismiss) private var dismiss
    let account: Account
    @State private var range: HistoryRange = .week
    @State private var selectedWindow = ""
    @State private var exporting = false
    @State private var csv = ""
    @State private var exportError: String?
    @State private var clearing = false
    @State private var loading = true
    private var samples: [UsageSnapshot] {
        (store.histories[account.id] ?? []).filter { $0.fetchedAt >= store.clock.addingTimeInterval(-Double(range.rawValue) * 86400) }
    }
    private var windows: [HistoryWindow] {
        var titles: [String: String] = [:]
        for sample in store.histories[account.id] ?? [] { for window in sample.windows { titles[window.id] = window.title } }
        for window in store.accounts.first(where: { $0.id == account.id })?.snapshot?.windows ?? [] { titles[window.id] = window.title }
        return titles.map { HistoryWindow(id: $0.key, title: $0.value) }.sorted { $0.title < $1.title }
    }
    private var points: [HistoryPoint] { HistoryPoint.make(samples, windowID: selectedWindow) }
    var body: some View {
        Group {
            if store.presentationMode {
                VStack(spacing: 20) {
                    ContentUnavailableView("History hidden", systemImage: "eye.slash", description: Text("Turn off presentation mode to view or export balances."))
                    Button("Done") { dismiss() }
                }.frame(minWidth: 560, idealWidth: 760, minHeight: 440, idealHeight: 660)
            } else { content }
        }
    }
    private var content: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(account.name) · usage history").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                    Text("Sampled provider readings stored on this Mac.").foregroundStyle(.secondary)
                }
                Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            HStack {
                Picker("Window", selection: $selectedWindow) {
                    ForEach(windows) { Text($0.title).tag($0.id) }
                }.frame(maxWidth: 280)
                Spacer()
                Picker("Time range", selection: $range) {
                    ForEach(HistoryRange.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).frame(width: 250)
            }
            if loading { ProgressView("Loading history…").frame(maxWidth: .infinity, minHeight: 280) }
            else if points.isEmpty {
                ContentUnavailableView("History starts with your next reading", systemImage: "chart.xyaxis.line",
                                       description: Text("QuotaBar records successful refreshes. There are no recorded samples for this window and time range yet."))
                    .frame(maxWidth: .infinity, minHeight: 280)
            } else {
                if store.errors[account.id] == nil, let forecast = UsageForecast.estimate(samples, windowID: selectedWindow, now: store.clock) {
                    ForecastSummary(forecast: forecast)
                }
                Chart(points) { point in
                    LineMark(x: .value("Time", point.observedAt), y: .value("Used", point.usedPercent),
                             series: .value("Continuous observations", point.segment))
                        .interpolationMethod(.stepStart).foregroundStyle(account.provider.tint)
                    PointMark(x: .value("Time", point.observedAt), y: .value("Used", point.usedPercent))
                        .foregroundStyle(account.provider.tint).symbolSize(12)
                }
                .chartYScale(domain: 0.0...100.0)
                .chartYAxis { AxisMarks(values: [0.0, 25.0, 50.0, 75.0, 100.0]) { value in
                    AxisGridLine(); AxisValueLabel { if let percent = value.as(Double.self) { Text("\(Int(percent))%") } }
                } }
                .frame(height: 220)
                .accessibilityLabel("\(account.provider.title) consumption history for \(windows.first(where: { $0.id == selectedWindow })?.title ?? "selected window")")
                HStack {
                    Text("\(points.count) recorded readings").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if let latest = points.last { Text("Last: \(latest.observedAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
                }
                ScrollView {
                    VStack(spacing: 8) {
                        HStack {
                            Text("Recent readings"); Spacer(); Text("Used")
                        }.font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(points.suffix(20).reversed()) { point in
                            HStack {
                                Text(point.observedAt.formatted(date: .abbreviated, time: .shortened))
                                Spacer(); Text("\(point.usedPercent.formatted(.number.precision(.fractionLength(0...1))))%")
                            }.font(.callout).monospacedDigit()
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(point.observedAt.formatted(date: .abbreviated, time: .shortened))
                                .accessibilityValue("\(Int(point.usedPercent.rounded())) percent used")
                        }
                    }
                }.frame(height: 100)
            }
            Text("Up to 30 days / 4,096 samples per account. Lines stop at resets and gaps longer than an hour. History is not a token or billing ledger.")
                .font(.caption).foregroundStyle(.secondary)
            if let error = store.historyErrors[account.id] ?? exportError {
                Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
            }
            HStack {
                Button("Clear account history", role: .destructive) { clearing = true }
                    .disabled(loading || store.refreshing.contains(account.id) || (store.histories[account.id]?.isEmpty ?? true))
                Spacer()
                Button("Export CSV · all windows") { csv = UsageHistory.csv(samples); exporting = true }
                    .disabled(samples.isEmpty).buttonStyle(.borderedProminent)
            }
        }.padding(24).frame(minWidth: 640, idealWidth: 760, maxWidth: .infinity, minHeight: 560, idealHeight: 660, maxHeight: .infinity)
            .task { await store.loadHistory(account.id); selectWindow(); loading = false }
            .onChange(of: windows.map(\.id)) { _, _ in selectWindow() }
            .fileExporter(isPresented: $exporting, document: HistoryCSVDocument(text: csv), contentType: .commaSeparatedText,
                          defaultFilename: "QuotaBar-\(account.id.uuidString.prefix(8))") { result in
                if case .failure(let error) = result { exportError = error.localizedDescription }
            }
            .alert("Clear this account's recorded history?", isPresented: $clearing) {
                Button("Cancel", role: .cancel) {}
                Button("Clear history", role: .destructive) { Task { await store.clearHistory(account.id) } }
            } message: { Text("Future refreshes will start a new history. Account credentials and alerts are kept.") }
    }
    private func selectWindow() {
        if !windows.contains(where: { $0.id == selectedWindow }) { selectedWindow = windows.first?.id ?? "" }
    }
}
private struct HistoryCSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data(text.utf8)) }
}
#endif
