import Foundation

public struct ResetRefreshAttempt: Equatable, Sendable {
    public var boundary: Date
    public var count: Int
    public var retryAt: Date
}
public enum ResetRefreshPolicy {
    public static func expiredBoundary(_ snapshot: UsageSnapshot?, now: Date) -> Date? {
        snapshot?.windows.compactMap(\.resetsAt).filter { $0 <= now }.min()
    }
    public static func isDue(_ snapshot: UsageSnapshot?, attempt: ResetRefreshAttempt?, cooldown: Date? = nil,
                             now: Date) -> Bool {
        if let cooldown, cooldown > now { return false }
        guard let boundary = expiredBoundary(snapshot, now: now) else { return false }
        guard let attempt, attempt.boundary == boundary else { return true }
        return attempt.retryAt <= now
    }
    public static func record(boundary: Date, previous: ResetRefreshAttempt?, now: Date) -> ResetRefreshAttempt {
        let count = previous?.boundary == boundary ? min(6, (previous?.count ?? 0) + 1) : 1
        return ResetRefreshAttempt(boundary: boundary, count: count,
                                   retryAt: now.addingTimeInterval(min(900, 30 * pow(2, Double(count - 1)))))
    }
}
