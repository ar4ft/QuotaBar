import Foundation

public struct UsageForecast: Equatable, Sendable {
    public var estimatedLimitAt: Date
    public var resetAt: Date
    public var percentPerHour: Double
    public var observationSpan: TimeInterval
    public var sampleCount: Int
    public var resetArrivesFirst: Bool { resetAt <= estimatedLimitAt }
    // A forecast is never a provider reading and never changes availability or triggers usage alerts.
    public static func estimate(_ samples: [UsageSnapshot], windowID: String, now: Date = Date()) -> Self? {
        let ordered = samples.filter { $0.fetchedAt <= now && $0.fetchedAt >= now.addingTimeInterval(-6 * 3600) }
            .sorted { $0.fetchedAt < $1.fetchedAt }
        guard let latest = ordered.last, now.timeIntervalSince(latest.fetchedAt) <= 600,
              let window = latest.windows.first(where: { $0.id == windowID }), window.usedPercent < 100,
              let reset = window.resetsAt, reset > now else { return nil }
        var observations: [(Date, Double)] = []
        for sample in ordered {
            guard let current = sample.windows.first(where: { $0.id == windowID }), current.resetsAt == reset,
                  current.usedPercent.isFinite, current.usedPercent >= 0, current.usedPercent <= 100 else {
                observations = []; continue
            }
            if let previous = observations.last {
                if sample.fetchedAt <= previous.0 { continue }
                if sample.fetchedAt.timeIntervalSince(previous.0) > 3600 || current.usedPercent < previous.1 {
                    observations = []
                }
            }
            observations.append((sample.fetchedAt, current.usedPercent))
        }
        guard observations.count >= 3, let first = observations.first, let last = observations.last,
              last.0.timeIntervalSince(first.0) >= 1800, last.1 - first.1 >= 2 else { return nil }
        let count = Double(observations.count)
        let meanX = observations.reduce(0) { $0 + $1.0.timeIntervalSince(first.0) } / count
        let meanY = observations.reduce(0) { $0 + $1.1 } / count
        let denominator = observations.reduce(0) { $0 + pow($1.0.timeIntervalSince(first.0) - meanX, 2) }
        guard denominator > 0 else { return nil }
        let slope = observations.reduce(0) { $0 + ($1.0.timeIntervalSince(first.0) - meanX) * ($1.1 - meanY) } / denominator
        guard slope.isFinite, slope > 0 else { return nil }
        let seconds = (100 - last.1) / slope
        guard seconds.isFinite, seconds > 0, seconds <= 30 * 86400 else { return nil }
        let estimate = last.0.addingTimeInterval(seconds)
        guard estimate > now else { return nil }
        return Self(estimatedLimitAt: estimate, resetAt: reset, percentPerHour: slope * 3600,
                    observationSpan: last.0.timeIntervalSince(first.0), sampleCount: observations.count)
    }
}
