import Foundation
import CoreFoundation

public enum UsageParser {
    public static func parse(_ data: Data, provider: Provider, now: Date = Date()) throws -> UsageSnapshot {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw QuotaError.malformedResponse
        }
        var windows: [UsageWindow] = []
        switch provider {
        case .openAI:
            func add(_ value: Any?, prefix: String, title: String?) throws {
                guard let limits = value as? [String: Any] else { return }
                for (key, fallback) in [("primary_window", "Session"), ("secondary_window", "Weekly")] {
                    guard let raw = limits[key], !(raw is NSNull) else { continue }
                    guard let window = raw as? [String: Any], let percent = number(window["used_percent"]) else {
                        throw QuotaError.malformedResponse
                    }
                    let duration = number(window["limit_window_seconds"])
                    let label = duration.map { durationLabel($0) } ?? fallback
                    let reset = number(window["reset_at"]).map { Date(timeIntervalSince1970: $0) }
                        ?? number(window["reset_after_seconds"]).map { now.addingTimeInterval($0) }
                    windows.append(UsageWindow(id: prefix + key, title: title.map { "\($0) · \(label)" } ?? label,
                                               usedPercent: percent, resetsAt: reset))
                }
            }
            try add(json["rate_limit"], prefix: "main-", title: nil)
            try add(json["code_review_rate_limit"], prefix: "review-", title: "Code review")
            for (index, extra) in ((json["additional_rate_limits"] as? [[String: Any]]) ?? []).enumerated() {
                try add(extra["rate_limit"], prefix: "extra-\(index)-", title: extra["limit_name"] as? String ?? "Additional limit")
            }
        case .claude:
            let labels = ["five_hour": "5-hour session", "seven_day": "Weekly", "seven_day_sonnet": "Sonnet weekly",
                          "seven_day_opus": "Opus weekly", "seven_day_oauth_apps": "OAuth apps weekly"]
            for key in labels.keys.sorted() {
                guard let raw = json[key], !(raw is NSNull) else { continue }
                guard let window = raw as? [String: Any], let percent = number(window["utilization"]) else {
                    throw QuotaError.malformedResponse
                }
                let reset = (window["resets_at"] as? String).flatMap(parseDate)
                windows.append(UsageWindow(id: key, title: labels[key]!, usedPercent: percent, resetsAt: reset))
            }
        }
        // An absent quota is unknown, never a synthetic zero.
        guard !windows.isEmpty else { throw QuotaError.malformedResponse }
        return UsageSnapshot(windows: windows, plan: json["plan_type"] as? String, fetchedAt: now)
    }
    private static func number(_ value: Any?) -> Double? {
        let result: Double?
        if let value = value as? NSNumber {
            guard CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
            result = value.doubleValue
        }
        else if let value = value as? String { result = Double(value) }
        else { result = nil }
        return result.flatMap { $0.isFinite ? $0 : nil }
    }
    private static func durationLabel(_ seconds: Double) -> String {
        if seconds >= 604800 { return "Weekly" }
        if seconds >= 86400 { return "\(Int(seconds / 86400))-day limit" }
        if seconds >= 3600 { return "\(Int(seconds / 3600))-hour session" }
        return "Session"
    }
    private static func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
