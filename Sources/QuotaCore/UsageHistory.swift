import Foundation

public enum UsageHistory {
    public static func record(_ snapshot: UsageSnapshot, in existing: [UsageSnapshot], maxSamples: Int = 4096) -> [UsageSnapshot] {
        let cutoff = snapshot.fetchedAt.addingTimeInterval(-30 * 86400)
        var samples = existing.filter { $0.fetchedAt >= cutoff }.sorted { $0.fetchedAt < $1.fetchedAt }
        if let last = samples.last {
            guard snapshot.fetchedAt > last.fetchedAt else { return Array(samples.suffix(max(0, maxSamples))) }
            let rolledOver = snapshot.windows.contains { window in
                guard let previous = last.windows.first(where: { $0.id == window.id }),
                      let oldReset = previous.resetsAt, let newReset = window.resetsAt else { return false }
                return oldReset <= snapshot.fetchedAt && newReset > snapshot.fetchedAt && newReset > oldReset
            }
            let sameBucket = floor(last.fetchedAt.timeIntervalSince1970 / 300) == floor(snapshot.fetchedAt.timeIntervalSince1970 / 300)
            if sameBucket && !rolledOver { samples.removeLast() }
        }
        samples.append(snapshot)
        return Array(samples.suffix(max(0, maxSamples)))
    }
    public static func csv(_ samples: [UsageSnapshot]) -> String {
        let formatter = ISO8601DateFormatter()
        var rows = ["observed_at,window_id,window_title,used_percent,remaining_percent,resets_at,plan,reading_status"]
        for sample in samples.sorted(by: { $0.fetchedAt < $1.fetchedAt }) {
            for window in sample.windows {
                let fields = [formatter.string(from: sample.fetchedAt), window.id, window.title,
                              String(window.usedPercent), String(window.remainingPercent),
                              window.resetsAt.map { formatter.string(from: $0) } ?? "", sample.plan ?? "",
                              (window.resetsAt.map { $0 <= sample.fetchedAt } ?? false) ? "awaiting_reset" : "observed"]
                rows.append(fields.map(csvField).joined(separator: ","))
            }
        }
        return rows.joined(separator: "\r\n") + "\r\n"
    }
    private static func csvField(_ value: String) -> String {
        // Provider labels can be untrusted spreadsheet formulas; make exported cells literal text.
        let dangerous = value.trimmingCharacters(in: .whitespacesAndNewlines).first.map { "=+-@".contains($0) } ?? false
        let value = dangerous ? "'" + value : value
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

public struct HistoryPoint: Identifiable, Sendable {
    public var id: String
    public var observedAt: Date
    public var usedPercent: Double
    public var segment: Int
    public static func make(_ samples: [UsageSnapshot], windowID: String) -> [HistoryPoint] {
        var points: [HistoryPoint] = []
        var segment = 0
        var previousWindow: UsageWindow?
        var previousDate: Date?
        for sample in samples.sorted(by: { $0.fetchedAt < $1.fetchedAt }) {
            guard let window = sample.windows.first(where: { $0.id == windowID }) else { segment += 1; continue }
            if window.resetsAt.map({ $0 <= sample.fetchedAt }) ?? false { segment += 1; continue }
            if let previousDate, let previousWindow {
                let gap = sample.fetchedAt.timeIntervalSince(previousDate) > 3600
                let rolled = previousWindow.resetsAt.map { $0 <= sample.fetchedAt && (window.resetsAt.map { $0 > sample.fetchedAt } ?? false) } ?? false
                let recovered = previousWindow.usedPercent >= 100 && window.usedPercent < 100 && previousWindow.resetsAt == nil
                if gap || rolled || recovered { segment += 1 }
            }
            points.append(HistoryPoint(id: "\(sample.fetchedAt.timeIntervalSince1970)-\(windowID)", observedAt: sample.fetchedAt,
                                       usedPercent: window.usedPercent, segment: segment))
            previousWindow = window; previousDate = sample.fetchedAt
        }
        return points
    }
}

public actor UsageHistoryRepository {
    private let directory: URL
    public init(directory: URL) { self.directory = directory }
    public func load(_ id: UUID) throws -> [UsageSnapshot] {
        let url = file(id)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? Int.max
        guard size <= 32 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
        return try JSONDecoder().decode([UsageSnapshot].self, from: Data(contentsOf: url))
    }
    public func record(_ snapshot: UsageSnapshot, for id: UUID) throws -> [UsageSnapshot] {
        let samples = UsageHistory.record(snapshot, in: try load(id))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try JSONEncoder().encode(samples).write(to: file(id), options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file(id).path)
        return samples
    }
    public func remove(_ id: UUID) throws {
        if FileManager.default.fileExists(atPath: file(id).path) { try FileManager.default.removeItem(at: file(id)) }
    }
    private func file(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + ".json") }
}
