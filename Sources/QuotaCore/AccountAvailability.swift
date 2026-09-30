import Foundation

public enum AvailabilityStatus: String, Sendable {
    case ready, limited, exhausted, awaitingReset, stale, error, unknown
    public var title: String {
        switch self {
        case .ready: return "Available"
        case .limited: return "Running low"
        case .exhausted: return "At limit"
        case .awaitingReset: return "Confirming reset"
        case .stale: return "Stale reading"
        case .error: return "Refresh failed"
        case .unknown: return "No reading"
        }
    }
    public var isAvailable: Bool { self == .ready || self == .limited }
}

public struct AccountAvailability: Equatable, Sendable {
    public var status: AvailabilityStatus
    public var remainingPercent: Double?
    public var nextReset: Date?
    public static func make(_ account: Account, hasError: Bool = false, now: Date = Date()) -> Self {
        let windows = mainWindows(account)
        let reset = windows.compactMap(\.resetsAt).filter { $0 > now }.min()
        if hasError { return Self(status: .error, nextReset: reset) }
        guard let snapshot = account.snapshot, !windows.isEmpty else { return Self(status: .unknown) }
        if windows.contains(where: { ($0.resetsAt.map { $0 <= now }) ?? false }) {
            return Self(status: .awaitingReset, nextReset: reset)
        }
        guard now.timeIntervalSince(snapshot.fetchedAt) <= 600 else { return Self(status: .stale, nextReset: reset) }
        let used = windows.map(\.usedPercent).max()!
        return Self(status: used >= 100 ? .exhausted : used >= 80 ? .limited : .ready,
                    remainingPercent: max(0, 100 - used), nextReset: reset)
    }
    public static func mainWindows(_ account: Account) -> [UsageWindow] {
        let ids: Set<String> = account.provider == .openAI
            ? ["main-primary_window", "main-secondary_window"] : ["five_hour", "seven_day"]
        return account.snapshot?.windows.filter { ids.contains($0.id) } ?? []
    }
    public init(status: AvailabilityStatus, remainingPercent: Double? = nil, nextReset: Date? = nil) {
        self.status = status; self.remainingPercent = remainingPercent; self.nextReset = nextReset
    }
}

public enum AccountSort: String, CaseIterable, Identifiable, Sendable {
    case added, allowance, reset, name
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .added: return "Date added"
        case .allowance: return "Most allowance left"
        case .reset: return "Next reset"
        case .name: return "Account name"
        }
    }
    public func sort(_ accounts: [Account], errorIDs: Set<UUID> = [], now: Date = Date()) -> [Account] {
        accounts.sorted { lhs, rhs in
            let left = AccountAvailability.make(lhs, hasError: errorIDs.contains(lhs.id), now: now)
            let right = AccountAvailability.make(rhs, hasError: errorIDs.contains(rhs.id), now: now)
            switch self {
            case .added:
                if lhs.addedAt != rhs.addedAt { return lhs.addedAt < rhs.addedAt }
            case .allowance:
                // Unknown/error/stale readings have no score, even if their cached quota looks ample.
                let l = left.remainingPercent ?? -1, r = right.remainingPercent ?? -1
                if l != r { return l > r }
            case .reset:
                let l = left.nextReset ?? .distantFuture, r = right.nextReset ?? .distantFuture
                if l != r { return l < r }
            case .name: break
            }
            let comparison = lhs.name.localizedStandardCompare(rhs.name)
            if comparison != .orderedSame { return comparison == .orderedAscending }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
