#if os(macOS)
import Foundation
import Security

// The script creates and locks a disposable Keychain containing synthetic bytes.
// This check only reads that fixture; it never searches the login Keychain.
enum KeychainChecks {
    private enum Failure: Error { case checkFailed }
    static func run(path: String) throws {
        try require(path.contains("/quotabar-keychain-checks.") && path.hasSuffix("/fixture.keychain-db"))
        var keychain: SecKeychain?
        let opened = try KeychainInteraction.perform(allowUI: false) { SecKeychainOpen(path, &keychain) }
        try require(opened == errSecSuccess)
        guard let keychain else { throw Failure.checkFailed }
        StartupDiagnostics.record("Locked Keychain fixture opened")
        let service = "QuotaBar test fixture", account = "synthetic"
        var previous: DarwinBoolean = false
        try require(SecKeychainGetUserInteractionAllowed(&previous) == errSecSuccess)
        let started = Date()
        for _ in 0..<3 {
            let result: OSStatus = try KeychainInteraction.perform(allowUI: false) {
                var interaction: DarwinBoolean = true
                try require(SecKeychainGetUserInteractionAllowed(&interaction) == errSecSuccess && !interaction.boolValue)
                return service.withCString { serviceBytes in
                    account.withCString { accountBytes in
                        var length: UInt32 = 0
                        var data: UnsafeMutableRawPointer?
                        let status = SecKeychainFindGenericPassword(keychain, UInt32(service.utf8.count), serviceBytes,
                            UInt32(account.utf8.count), accountBytes, &length, &data, nil)
                        if let data { SecKeychainItemFreeContent(nil, data) }
                        return status
                    }
                }
            }
            try require(result == errSecInteractionNotAllowed || result == errSecAuthFailed)
            try require(KeychainInteraction.requiresPermission(NSError(domain: NSOSStatusErrorDomain, code: Int(result))))
        }
        StartupDiagnostics.record("Legacy locked Keychain reads stayed silent")
        let copyStatus = try KeychainInteraction.perform(allowUI: false) {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service, kSecAttrAccount as String: account,
                kSecMatchSearchList as String: [keychain],
                kSecMatchLimit as String: kSecMatchLimitOne, kSecReturnData as String: true
            ]
            var value: CFTypeRef?
            return SecItemCopyMatching(query as CFDictionary, &value)
        }
        try require(copyStatus == errSecInteractionNotAllowed || copyStatus == errSecAuthFailed)
        StartupDiagnostics.record("SecItem locked Keychain read stayed silent")
        try require(Date().timeIntervalSince(started) < 5)
        do {
            try KeychainInteraction.perform(allowUI: false) { throw Failure.checkFailed }
        } catch Failure.checkFailed { /* Verify restoration after a thrown operation. */ }
        var restored: DarwinBoolean = false
        try require(SecKeychainGetUserInteractionAllowed(&restored) == errSecSuccess && restored.boolValue == previous.boolValue)
        try require(!KeychainInteraction.requiresPermission(NSError(domain: NSOSStatusErrorDomain, code: Int(errSecItemNotFound))))
        try require(!KeychainInteraction.requiresPermission(NSError(domain: "network", code: Int(errSecAuthFailed))))
        print("Noninteractive Keychain checks passed (disposable locked Keychain only).")
    }
    private static func require(_ condition: Bool) throws {
        guard condition else { throw Failure.checkFailed }
    }
}
#endif
