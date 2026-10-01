#if os(macOS)
import Foundation
import QuotaCore

// Runs with synthetic credentials in a disposable home and an in-memory Keychain.
// Never reads or modifies a user's CLI sign-in or macOS Keychain.
enum ClientSwitchChecks {
    static func run() throws {
        let home = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("QuotaBar-switch-checks-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let codexHome = home.appendingPathComponent(".codex")
        let codexAuth = codexHome.appendingPathComponent("auth.json")
        let old = try ClientSession(provider: .openAI, authentication: Data(#"{"tokens":{"id_token":"synthetic-id","access_token":"synthetic-old","refresh_token":"synthetic-refresh","account_id":"one"}}"#.utf8))
        let next = try ClientSession(provider: .openAI, authentication: Data(#"{"tokens":{"id_token":"synthetic-id","access_token":"synthetic-next","refresh_token":"synthetic-refresh","account_id":"two"}}"#.utf8))
        try SecureClientFile.write(old.authentication, to: codexAuth)
        let codex = try NativeClientStorage(provider: .openAI, codexHome: codexHome.path, home: home)
        var captured: ClientSession?
        try ClientSessionSwitch.perform(next, storage: codex) { captured = $0 }
        try require(captured == old && SecureClientFile.read(codexAuth) == next.authentication)
        try codex.restore(old)
        try require(SecureClientFile.read(codexAuth) == old.authentication)
        for mode in ["auto", "keyring", "keychain", "ephemeral"] {
            try SecureClientFile.write(Data("cli_auth_credentials_store = \"\(mode)\"".utf8), to: codexHome.appendingPathComponent("config.toml"))
            do {
                _ = try NativeClientStorage(provider: .openAI, codexHome: codexHome.path, home: home)
                throw CheckFailure.failed
            } catch ClientSwitchError.storageMode { }
        }
        let secrets = MemoryClientSecrets()
        let claudeAuth = Data(#"{"claudeAiOauth":{"accessToken":"synthetic-claude-old","refreshToken":"synthetic-refresh","scopes":["user:inference","user:profile"]}}"#.utf8)
        let replacementAuth = Data(#"{"claudeAiOauth":{"accessToken":"synthetic-claude-next","refreshToken":"synthetic-refresh","scopes":["user:inference","user:profile"]}}"#.utf8)
        let settingsURL = home.appendingPathComponent(".claude.json")
        let oldSettings = Data(#"{"oauthAccount":{"accountUuid":"old"},"theme":"dark","projects":{"/work":{"trusted":true}}}"#.utf8)
        let newSettings = Data(#"{"oauthAccount":{"accountUuid":"new"},"theme":"light"}"#.utf8)
        try SecureClientFile.write(oldSettings, to: settingsURL)
        secrets.value = claudeAuth
        let replacement = try ClientSession(provider: .claude, authentication: replacementAuth, settings: newSettings)
        let claude = try NativeClientStorage(provider: .claude, codexHome: codexHome.path, home: home, claudeKeychain: secrets)
        captured = nil
        try ClientSessionSwitch.perform(replacement, storage: claude) { captured = $0 }
        try require(captured?.authentication == claudeAuth && secrets.value == replacementAuth)
        let changed = try JSONSerialization.jsonObject(with: XCTData(settingsURL)) as? [String: Any]
        try require(changed?["theme"] as? String == "dark" && changed?["projects"] != nil)
        try require((changed?["oauthAccount"] as? [String: Any])?["accountUuid"] as? String == "new")
        try claude.restore(captured)
        try require(secrets.value == claudeAuth && SecureClientFile.read(settingsURL) == oldSettings)

        // A Keychain write that fails after modifying its value must recover exact previous bytes.
        let failing = try NativeClientStorage(provider: .claude, codexHome: codexHome.path, home: home, claudeKeychain: secrets)
        secrets.failNextWrite = true
        do { try ClientSessionSwitch.perform(replacement, storage: failing) { _ in }; throw CheckFailure.failed }
        catch CheckFailure.injected { }
        try require(secrets.value == claudeAuth && SecureClientFile.read(settingsURL) == oldSettings)

        // Existing file-backed installations use the file, leaving the Keychain alone.
        secrets.value = nil
        let claudeFile = home.appendingPathComponent(".claude/.credentials.json")
        try SecureClientFile.write(claudeAuth, to: claudeFile)
        let fileBacked = try NativeClientStorage(provider: .claude, codexHome: codexHome.path, home: home, claudeKeychain: secrets)
        try ClientSessionSwitch.perform(replacement, storage: fileBacked) { _ in }
        try require(SecureClientFile.read(claudeFile) == replacementAuth && secrets.value == nil)
        secrets.value = claudeAuth
        do {
            _ = try NativeClientStorage(provider: .claude, codexHome: codexHome.path, home: home, claudeKeychain: secrets)
            throw CheckFailure.failed
        } catch let error as NSError where error.domain == "QuotaBar" && error.code == 2 { }
        print("Native client-switch checks passed (synthetic credentials only).")
    }
    private static func require(_ value: Bool) throws { if !value { throw CheckFailure.failed } }
    private static func XCTData(_ url: URL) throws -> Data {
        guard let data = try SecureClientFile.read(url) else { throw CheckFailure.failed }
        return data
    }
}
private enum CheckFailure: Error { case failed, injected }
private final class MemoryClientSecrets: ClientSecretStorage {
    var value: Data?
    var failNextWrite = false
    func read() throws -> Data? { value }
    func write(_ data: Data?) throws {
        value = data
        if failNextWrite { failNextWrite = false; throw CheckFailure.injected }
    }
}
#endif
