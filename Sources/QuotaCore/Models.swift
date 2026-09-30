import Foundation

public enum Provider: String, Codable, CaseIterable, Identifiable, Sendable {
    case openAI, claude
    public var id: String { rawValue }
    public var title: String { self == .openAI ? "OpenAI" : "Claude" }
    public var subtitle: String { self == .openAI ? "Codex subscription" : "Claude subscription" }
}

public struct UsageWindow: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var usedPercent: Double
    public var resetsAt: Date?
    public var remainingPercent: Double { max(0, 100 - usedPercent) }
    public func resetDescription(now: Date = Date()) -> String {
        guard let resetsAt else { return "Reset time unavailable" }
        let seconds = resetsAt.timeIntervalSince(now)
        guard seconds > 0 else { return "Reset reached · refresh to confirm" }
        let minutes = max(1, Int(ceil(seconds / 60)))
        if minutes < 60 { return "Resets in \(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "Resets in \(hours)h \(minutes % 60)m" }
        return "Resets in \(hours / 24)d \(hours % 24)h"
    }
    public init(id: String, title: String, usedPercent: Double, resetsAt: Date?) {
        self.id = id; self.title = title
        self.usedPercent = min(100, max(0, usedPercent)); self.resetsAt = resetsAt
    }
}

public struct UsageSnapshot: Codable, Equatable, Sendable {
    public var windows: [UsageWindow]
    public var plan: String?
    public var fetchedAt: Date
    public init(windows: [UsageWindow], plan: String? = nil, fetchedAt: Date = Date()) {
        self.windows = windows; self.plan = plan; self.fetchedAt = fetchedAt
    }
    public var isStale: Bool { Date().timeIntervalSince(fetchedAt) > 600 }
}

public struct Account: Codable, Identifiable, Sendable {
    public var id: UUID
    public var provider: Provider
    public var name: String
    public var detail: String?
    public var snapshot: UsageSnapshot?
    public var addedAt: Date
    public var alertPreferences: AlertPreferences?
    public var alertState: [String: WindowAlertState]?
    public var effectiveAlertPreferences: AlertPreferences { alertPreferences ?? AlertPreferences() }
    public init(id: UUID = UUID(), provider: Provider, name: String, detail: String? = nil) {
        self.id = id; self.provider = provider; self.name = name; self.detail = detail
        self.addedAt = Date()
    }
}

public struct Organization: Identifiable, Sendable {
    public var id: String
    public var name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}

public enum CredentialKind: String, Codable, Sendable { case codex, claudeOAuth, claudeWeb }
public struct Credential: Codable, Sendable {
    public var kind: CredentialKind
    public var secret: String
    public var accountID: String?
    public var email: String?
    public var refreshToken: String?
    public init(kind: CredentialKind, secret: String, accountID: String? = nil, email: String? = nil, refreshToken: String? = nil) {
        self.kind = kind; self.secret = secret; self.accountID = accountID; self.email = email
        self.refreshToken = refreshToken
    }
}

public enum QuotaError: LocalizedError, Equatable {
    case invalidCredentials, malformedResponse, unauthorized, forbidden
    case rateLimited(Date), http(Int), ambiguousOrganizations, noOrganizations
    public var errorDescription: String? {
        switch self {
        case .invalidCredentials: return "No subscription credentials found. API keys cannot report subscription usage."
        case .malformedResponse: return "The provider returned an unrecognized usage response."
        case .unauthorized: return "Your session expired. Reconnect this account."
        case .forbidden: return "The provider denied access. Try reconnecting or importing OAuth credentials."
        case .rateLimited(let date): return "Too many requests. Try again after \(date.formatted(date: .omitted, time: .shortened))."
        case .http(let status): return "The provider returned HTTP \(status). Try again later."
        case .ambiguousOrganizations: return "This Claude account has multiple organizations. Enter the organization UUID when connecting."
        case .noOrganizations: return "No Claude organization was found for this session."
        }
    }
}
