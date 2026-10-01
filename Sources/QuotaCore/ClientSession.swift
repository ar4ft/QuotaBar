import Foundation

public struct ClientSession: Equatable, Sendable {
    public let provider: Provider
    public var authentication: Data
    public var settings: Data?
    public init(provider: Provider, authentication: Data, settings: Data? = nil) throws {
        self.provider = provider; self.authentication = authentication; self.settings = settings
        _ = try CredentialParser.parse(authentication, provider: provider)
        if provider == .openAI {
            let root = try Self.object(authentication)
            guard let tokens = root["tokens"] as? [String: Any],
                  let id = tokens["id_token"] as? String, !id.isEmpty,
                  let refresh = tokens["refresh_token"] as? String, !refresh.isEmpty,
                  root["OPENAI_API_KEY"] as? String == nil else { throw ClientSwitchError.incompleteSession }
        } else {
            guard let oauth = (try Self.object(authentication))["claudeAiOauth"] as? [String: Any],
                  let scopes = oauth["scopes"] as? [String], scopes.contains("user:inference") else {
                throw ClientSwitchError.incompleteSession
            }
        }
        if let settings { _ = try Self.object(settings) }
    }
    public init(credential: Credential) throws {
        guard credential.kind != .claudeWeb, let data = credential.nativeSession else {
            throw ClientSwitchError.incompleteSession
        }
        try self.init(provider: credential.kind == .codex ? .openAI : .claude,
                      authentication: data, settings: credential.clientSettings)
    }
    public func credential() throws -> Credential {
        var result = try CredentialParser.parse(authentication, provider: provider)
        result.clientSettings = settings; result.externallyManaged = true
        if provider == .claude, let settings,
           let account = try Self.object(settings)["oauthAccount"] as? [String: Any] {
            result.accountID = account["accountUuid"] as? String
            result.email = account["emailAddress"] as? String
        }
        return result
    }
    public func belongs(to credential: Credential) throws -> Bool {
        let live = try self.credential()
        guard live.kind == credential.kind else { return false }
        if let id = live.accountID, let saved = credential.accountID { return id == saved }
        return live.secret == credential.secret
    }
    // Preserve machine/project preferences; only replace account identity on a Claude switch.
    public func mergingSettings(from current: ClientSession?) throws -> ClientSession {
        guard provider == .claude else { return self }
        var root = try current?.settings.map(Self.object) ?? [:]
        if let settings, let account = try Self.object(settings)["oauthAccount"] {
            root["oauthAccount"] = account
        } else {
            root.removeValue(forKey: "oauthAccount")
        }
        root.removeValue(forKey: "cachedGrowthBookFeatures")
        var result = self
        result.settings = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        return result
    }
    public static func updatingCodex(_ credential: Credential, response: [String: Any], now: Date = Date()) throws -> Credential {
        var result = credential
        guard let token = response["access_token"] as? String, !token.isEmpty else { throw QuotaError.malformedResponse }
        result.secret = token; result.refreshToken = response["refresh_token"] as? String ?? credential.refreshToken
        if let data = credential.nativeSession {
            var root = try object(data)
            var tokens = root["tokens"] as? [String: Any] ?? [:]
            tokens["access_token"] = token
            if let refresh = result.refreshToken { tokens["refresh_token"] = refresh }
            if let id = response["id_token"] as? String { tokens["id_token"] = id }
            root["tokens"] = tokens
            root["last_refresh"] = ISO8601DateFormatter().string(from: now)
            result.nativeSession = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        }
        return result
    }
    private static func object(_ data: Data) throws -> [String: Any] {
        guard data.count <= 1_048_576, let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw QuotaError.invalidCredentials
        }
        return root
    }
}

public enum ClientSwitchError: LocalizedError {
    case incompleteSession, clientRunning, storageMode, changedDuringSwitch, rollbackFailed
    public var errorDescription: String? {
        switch self {
        case .incompleteSession: return "This account has monitoring credentials only. Save its current CLI sign-in, import a complete client session, or reconnect OpenAI to enable switching. Claude web sessions cannot sign in to Claude Code."
        case .clientRunning: return "Quit this provider’s CLI, desktop app, and editor sessions before switching. Start a new session afterward to use the selected subscription."
        case .storageMode: return "This Codex home uses Keychain or automatic credential storage. Choose a file-backed home, or set cli_auth_credentials_store = \"file\" in its config.toml before switching."
        case .changedDuringSwitch: return "The client sign-in changed during switching. Nothing was replaced. Close the client and try again."
        case .rollbackFailed: return "The switch failed and the previous sign-in could not be fully restored. Its encrypted backup was retained; restore it from QuotaBar before starting the client."
        }
    }
}

public protocol ClientSessionStorage {
    func read() throws -> ClientSession?
    func write(_ session: ClientSession) throws
    func restore(_ session: ClientSession?) throws
}

public enum ClientSessionSwitch {
    // The callback must persist the displaced session before any client credential is replaced.
    public static func perform(_ replacement: ClientSession, storage: any ClientSessionStorage,
                               savePrevious: (ClientSession?) throws -> Void) throws {
        let previous = try storage.read()
        let next = try replacement.mergingSettings(from: previous)
        try savePrevious(previous)
        guard try storage.read() == previous else { throw ClientSwitchError.changedDuringSwitch }
        do { try storage.write(next) }
        catch ClientSwitchError.changedDuringSwitch { throw ClientSwitchError.changedDuringSwitch }
        catch {
            do { try storage.restore(previous) }
            catch { throw ClientSwitchError.rollbackFailed }
            throw error
        }
    }
}
