import Foundation

public enum ConnectionIssue: String, Sendable {
    case expired, denied, rateLimited, failed, keychainAccess
    public static func classify(_ error: Error) -> Self {
        switch error as? QuotaError {
        case .unauthorized: return .expired
        case .forbidden: return .denied
        case .rateLimited: return .rateLimited
        default: return .failed
        }
    }
    public var title: String {
        switch self {
        case .expired: return "Session expired · reconnect"
        case .denied: return "Access denied · reconnect"
        case .rateLimited: return "Provider cooldown"
        case .failed: return "Refresh failed"
        case .keychainAccess: return "Keychain permission needed"
        }
    }
    public var needsReconnect: Bool { self == .expired || self == .denied }
}
public struct ConnectionHealth: Equatable, Sendable {
    public var title: String
    public var needsAttention: Bool
    public var needsReconnect: Bool
    public var lastSuccess: Date?
    public static func make(snapshot: UsageSnapshot?, issue: ConnectionIssue?, now: Date = Date()) -> Self {
        if let issue { return Self(title: issue.title, needsAttention: true, needsReconnect: issue.needsReconnect, lastSuccess: snapshot?.fetchedAt) }
        guard let snapshot else { return Self(title: "Awaiting first reading", needsAttention: true, needsReconnect: false) }
        let stale = now.timeIntervalSince(snapshot.fetchedAt) > 600
        return Self(title: stale ? "Stale reading" : "Connected", needsAttention: stale, needsReconnect: false, lastSuccess: snapshot.fetchedAt)
    }
}
