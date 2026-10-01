import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

// Refuse redirects so credentials can never be forwarded to another host.
private final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
public final class EphemeralTransport: HTTPTransport, @unchecked Sendable {
    private let session: URLSession
    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false; config.httpCookieStorage = nil
        config.urlCache = nil; config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
    }
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw QuotaError.malformedResponse }
        return (data, response)
    }
}

public struct UsageClient: Sendable {
    private let transport: any HTTPTransport
    public init(transport: any HTTPTransport = EphemeralTransport()) { self.transport = transport }

    public func fetch(_ credential: Credential) async throws -> UsageSnapshot {
        var credential = credential
        if credential.kind == .claudeWeb, credential.accountID == nil {
            credential.accountID = try await organizationID(credential)
        }
        let url: URL
        switch credential.kind {
        case .codex: url = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
        case .claudeOAuth: url = URL(string: "https://api.anthropic.com/api/oauth/usage")!
        case .claudeWeb:
            guard let id = credential.accountID, UUID(uuidString: id) != nil else { throw QuotaError.invalidCredentials }
            url = URL(string: "https://claude.ai/api/organizations/\(id)/usage")!
        }
        let data = try await checked(request(url, credential: credential))
        return try UsageParser.parse(data, provider: credential.kind == .codex ? .openAI : .claude)
    }

    // Read inventory only. QuotaBar never redeems reset credits.
    public func fetchResetCredits(_ credential: Credential) async throws -> Int {
        guard credential.kind == .codex else { throw QuotaError.invalidCredentials }
        var request = request(URL(string: "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits")!, credential: credential)
        request.timeoutInterval = 5
        return try UsageParser.parseResetCredits(await checked(request))
    }

    public func organizations(_ credential: Credential) async throws -> [Organization] {
        let data = try await checked(request(URL(string: "https://claude.ai/api/organizations")!, credential: credential))
        guard let orgs = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw QuotaError.malformedResponse }
        guard !orgs.isEmpty else { throw QuotaError.noOrganizations }
        return try orgs.map { raw in
            guard let id = raw["uuid"] as? String, UUID(uuidString: id) != nil else { throw QuotaError.malformedResponse }
            return Organization(id: id, name: raw["name"] as? String ?? id)
        }
    }
    public func organizationID(_ credential: Credential) async throws -> String {
        let orgs = try await organizations(credential)
        guard orgs.count == 1 else { throw QuotaError.ambiguousOrganizations }
        return orgs[0].id
    }

    // Only credentials created in this app's own Codex home carry a refresh token.
    // Imported tokens are read-only to avoid rotating another app's credentials.
    public func refreshOwnedCodex(_ credential: Credential) async throws -> Credential {
        guard credential.kind == .codex, credential.externallyManaged != true,
              let refreshToken = credential.refreshToken else { throw QuotaError.unauthorized }
        var request = URLRequest(url: URL(string: "https://auth.openai.com/oauth/token")!)
        request.httpMethod = "POST"; request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "client_id": "app_EMoamEEZ73f0CkXaXp7hrann", "grant_type": "refresh_token",
            "refresh_token": refreshToken, "scope": "openid profile email"
        ])
        let data = try await checked(request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String, !token.isEmpty else { throw QuotaError.malformedResponse }
        return try ClientSession.updatingCodex(credential, response: json)
    }

    private func request(_ url: URL, credential: Credential) -> URLRequest {
        var request = URLRequest(url: url); request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("QuotaBar/1.0", forHTTPHeaderField: "User-Agent")
        if credential.kind == .claudeWeb {
            request.setValue("sessionKey=\(credential.secret)", forHTTPHeaderField: "Cookie")
        } else {
            request.setValue("Bearer \(credential.secret)", forHTTPHeaderField: "Authorization")
        }
        if credential.kind == .codex, let id = credential.accountID {
            request.setValue(id, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        if credential.kind == .claudeOAuth {
            request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        }
        return request
    }
    private func checked(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await transport.send(request)
        switch response.statusCode {
        case 200: guard data.count <= 2_097_152 else { throw QuotaError.malformedResponse }; return data
        case 401: throw QuotaError.unauthorized
        case 403: throw QuotaError.forbidden
        case 429:
            let raw = response.value(forHTTPHeaderField: "Retry-After") ?? ""
            let date: Date
            if let seconds = Double(raw), seconds.isFinite {
                date = Date().addingTimeInterval(max(60, seconds))
            } else {
                let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
                date = max(formatter.date(from: raw) ?? Date().addingTimeInterval(300), Date().addingTimeInterval(60))
            }
            throw QuotaError.rateLimited(date)
        default: throw QuotaError.http(response.statusCode)
        }
    }
}
