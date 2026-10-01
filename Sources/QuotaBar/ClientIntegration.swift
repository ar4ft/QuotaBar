#if os(macOS)
import Foundation
import AppKit
import Security
import QuotaCore

struct ClientBackup: Codable, Equatable {
    var authentication: Data?
    var settings: Data?
}

// Uses Security APIs, so secret values never appear in command-line arguments or logs.
protocol ClientSecretStorage {
    func read() throws -> Data?
    func write(_ data: Data?) throws
}

struct ClientSecrets: ClientSecretStorage {
    let service: String
    let account: String
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
    func read() throws -> Data? {
        var request = query
        request[kSecReturnData as String] = true; request[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let data = value as? Data else { throw QuotaError.invalidCredentials }
        return data
    }
    func write(_ data: Data?) throws {
        guard let data else {
            let status = SecItemDelete(query as CFDictionary)
            if status != errSecItemNotFound { try check(status) }
            return
        }
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var entry = query; entry[kSecValueData as String] = data
            entry[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            try check(SecItemAdd(entry as CFDictionary, nil))
        } else { try check(status) }
    }
    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey:
                SecCopyErrorMessageString(status, nil) as String? ?? "Keychain access failed"])
        }
    }
}

final class NativeClientStorage: ClientSessionStorage {
    let provider: Provider
    let authURL: URL
    let settingsURL: URL?
    let usesClaudeFile: Bool
    private let claudeKeychain: any ClientSecretStorage
    private let initial: ClientBackup
    var backupKey: String { provider.rawValue + "|" + authURL.deletingLastPathComponent().path }
    init(provider: Provider, codexHome: String,
         home: URL = FileManager.default.homeDirectoryForCurrentUser,
         claudeKeychain: any ClientSecretStorage = ClientSecrets(service: "Claude Code-credentials", account: NSUserName())) throws {
        self.provider = provider
        self.claudeKeychain = claudeKeychain
        if provider == .openAI {
            let directory = URL(fileURLWithPath: NSString(string: codexHome).expandingTildeInPath, isDirectory: true)
            guard directory.path.hasPrefix("/"), directory.path != "/" else { throw CocoaError(.fileReadInvalidFileName) }
            authURL = directory.appendingPathComponent("auth.json"); settingsURL = nil; usesClaudeFile = false
            let configURL = directory.appendingPathComponent("config.toml")
            if let config = try SecureClientFile.read(configURL), let text = String(data: config, encoding: .utf8) {
                let pattern = #"(?m)^\s*(?:cli_auth_credentials_store|"cli_auth_credentials_store"|'cli_auth_credentials_store')\s*=\s*["']([^"']+)["']"#
                let regex = try NSRegularExpression(pattern: pattern)
                let range = NSRange(text.startIndex..., in: text)
                for match in regex.matches(in: text, range: range) {
                    if let value = Range(match.range(at: 1), in: text), text[value] != "file" { throw ClientSwitchError.storageMode }
                }
            }
            initial = ClientBackup(authentication: try SecureClientFile.read(authURL), settings: nil)
        } else {
            // Custom Claude config directories have distinct Keychain services: don't touch them implicitly.
            if let configured = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"],
               URL(fileURLWithPath: NSString(string: configured).expandingTildeInPath).standardizedFileURL != home.appendingPathComponent(".claude").standardizedFileURL {
                throw NSError(domain: "QuotaBar", code: 1, userInfo: [NSLocalizedDescriptionKey:
                    "This version switches the default Claude Code profile. A custom CLAUDE_CONFIG_DIR has its own Keychain entry and must be switched in that profile."])
            }
            authURL = home.appendingPathComponent(".claude/.credentials.json")
            let nested = home.appendingPathComponent(".claude/.claude.json")
            settingsURL = FileManager.default.fileExists(atPath: nested.path) ? nested : home.appendingPathComponent(".claude.json")
            let file = try SecureClientFile.read(authURL)
            let keychain = try claudeKeychain.read()
            // When both exist, updating just one could leave the client on the other account.
            if file != nil && keychain != nil {
                throw NSError(domain: "QuotaBar", code: 2, userInfo: [NSLocalizedDescriptionKey:
                    "Claude Code has both file and Keychain credentials. Resolve the duplicate with Claude Code before switching; QuotaBar preserved both."])
            }
            usesClaudeFile = file != nil
            initial = ClientBackup(authentication: file ?? keychain, settings: try settingsURL.flatMap(SecureClientFile.read))
        }
    }
    func rawSnapshot() throws -> ClientBackup {
        ClientBackup(authentication: try authentication(), settings: try settingsURL.flatMap(SecureClientFile.read))
    }
    func authentication() throws -> Data? {
        provider == .openAI || usesClaudeFile ? try SecureClientFile.read(authURL) : try claudeKeychain.read()
    }
    func read() throws -> ClientSession? {
        let current = try rawSnapshot()
        guard current == initial else { throw ClientSwitchError.changedDuringSwitch }
        guard let data = current.authentication else { return nil }
        return try ClientSession(provider: provider, authentication: data, settings: current.settings)
    }
    func write(_ session: ClientSession) throws {
        guard session.provider == provider else { throw QuotaError.invalidCredentials }
        guard try rawSnapshot() == initial else { throw ClientSwitchError.changedDuringSwitch }
        // Preserve preferences even when no current credentials were present.
        var replacement = session
        if provider == .claude, initial.authentication == nil, let settings = initial.settings {
            let baseline = try ClientSession(provider: provider, authentication: session.authentication, settings: settings)
            replacement = try session.mergingSettings(from: baseline)
        }
        try writeAuthentication(replacement.authentication)
        if let settingsURL, let settings = replacement.settings { try SecureClientFile.write(settings, to: settingsURL) }
    }
    func restore(_ session: ClientSession?) throws {
        // Exact bytes, including an absent sign-in, rather than a reconstruction.
        try restoreRaw(initial)
    }
    func restoreRaw(_ backup: ClientBackup) throws {
        try writeAuthentication(backup.authentication)
        if let settingsURL { try SecureClientFile.write(backup.settings, to: settingsURL) }
    }
    private func writeAuthentication(_ data: Data?) throws {
        if provider == .openAI || usesClaudeFile { try SecureClientFile.write(data, to: authURL) }
        else { try claudeKeychain.write(data) }
    }
    static func ensureStopped(_ provider: Provider) throws {
        let process = Process(); let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "comm=,args="]
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw ClientSwitchError.clientRunning }
        let names = String(decoding: data, as: UTF8.self).lowercased().split(separator: "\n")
        let patterns = provider == .openAI ? ["/codex", "codex app-server", "codex.app/", "chatgpt.app/", "@openai/codex"] :
            ["/claude", "claude.app/", "@anthropic-ai/claude-code"]
        if names.contains(where: { line in patterns.contains(where: { line.contains($0) }) }) {
            throw ClientSwitchError.clientRunning
        }
    }
}

#endif
