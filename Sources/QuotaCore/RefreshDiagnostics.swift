import Foundation
import CoreFoundation

// Only allowlisted metadata enters diagnostics. Never retain tokens, provider account IDs,
// emails, file paths, response bodies, or localized error descriptions here.
public struct CredentialDiagnostics: Equatable, Sendable {
    public enum Renewal: String, Sendable {
        case appOwned, clientManaged, readOnly, webSession
        public var title: String {
            switch self {
            case .appOwned: return "QuotaBar sign-in · automatic renewal"
            case .clientManaged: return "CLI-managed sign-in · renewal belongs to the client"
            case .readOnly: return "Imported sign-in · read-only token copy"
            case .webSession: return "Browser sign-in"
            }
        }
    }
    public let kind: CredentialKind
    public let renewal: Renewal
    public let reportedExpiry: Date?
    public init(_ credential: Credential) {
        kind = credential.kind
        renewal = credential.kind == .claudeWeb ? .webSession : credential.externallyManaged == true ? .clientManaged :
            credential.kind == .codex && credential.refreshToken != nil ? .appOwned : .readOnly
        // Decode only the access token's exp claim. It is reported metadata, not proof
        // of validity. ID-token expiry says nothing about the access token being sent.
        guard credential.kind == .codex, credential.secret.utf8.count <= 16_384 else {
            reportedExpiry = nil; return
        }
        let parts = credential.secret.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { reportedExpiry = nil; return }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let number = object["exp"] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, (0...253_402_300_799).contains(number.doubleValue) else {
            reportedExpiry = nil; return
        }
        reportedExpiry = Date(timeIntervalSince1970: number.doubleValue)
    }
}

public enum DiagnosticFailure: Equatable, Sendable {
    case http(Int), keychain(Int), network(Int), storage(Int)
    case invalidCredentials, malformedResponse, unknown
    public init(_ error: Error) {
        switch error as? QuotaError {
        case .unauthorized: self = .http(401)
        case .forbidden: self = .http(403)
        case .rateLimited: self = .http(429)
        case .http(let code): self = .http(code)
        case .invalidCredentials: self = .invalidCredentials
        case .malformedResponse, .ambiguousOrganizations, .noOrganizations: self = .malformedResponse
        default:
            let error = error as NSError
            switch error.domain {
            case NSOSStatusErrorDomain: self = .keychain(error.code)
            case NSURLErrorDomain: self = .network(error.code)
            case NSCocoaErrorDomain: self = .storage(error.code)
            default: self = .unknown
            }
        }
    }
    public var description: String {
        switch self {
        case .http(let code): return "HTTP \(code)"
        case .keychain(let code): return "Keychain OSStatus \(code)"
        case .network(let code): return "Network code \(code)"
        case .storage(let code): return "Storage code \(code)"
        case .invalidCredentials: return "Invalid subscription credentials"
        case .malformedResponse: return "Unrecognized provider response"
        case .unknown: return "Unclassified failure"
        }
    }
}

public struct UsageRequestDiagnostic: Equatable, Sendable {
    public enum Endpoint: String, Sendable {
        case codexUsage, codexResetCredits, codexTokenRenewal
        case claudeOAuthUsage, claudeWebUsage, claudeOrganizations
    }
    public let endpoint: Endpoint
    public let result: DiagnosticFailure
    public init(endpoint: Endpoint, result: DiagnosticFailure) { self.endpoint = endpoint; self.result = result }
    public var description: String { "\(endpoint.rawValue): \(result.description)" }
}

public struct RefreshDiagnostic: Sendable {
    public enum Stage: String, Sendable {
        case keychainRead, clientSessionRead, clientSessionSave, usage
        case renewalPreflight, tokenRenewal, renewedTokenSave, accountSave, complete
    }
    public let startedAt: Date
    public var stage: Stage = .keychainRead
    public var credential: CredentialDiagnostics?
    public var lastRequest: UsageRequestDiagnostic?
    public var failure: DiagnosticFailure?
    public var finished = false
    public init(startedAt: Date = Date()) { self.startedAt = startedAt }
    public func report(accountID: UUID, provider: Provider) -> String {
        var lines = ["Account: \(accountID.uuidString)", "Provider: \(provider.title)",
                     "Refresh: \(startedAt.ISO8601Format())", "Step: \(stage.rawValue)"]
        if let credential {
            lines += ["Credential: \(credential.kind.rawValue)", "Renewal: \(credential.renewal.title)"]
            if let expiry = credential.reportedExpiry {
                lines.append("Access-token reported expiry: \(expiry.ISO8601Format()) (\(expiry <= startedAt ? "elapsed" : "not elapsed") at refresh; unverified)")
            } else { lines.append("Access-token reported expiry: unavailable") }
        }
        if let lastRequest { lines.append("Last request: \(lastRequest.description)") }
        lines.append("Result: \(failure?.description ?? (finished ? "Success" : "In progress"))")
        return lines.joined(separator: "\n")
    }
}
