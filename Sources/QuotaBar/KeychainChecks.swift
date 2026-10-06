#if os(macOS)
import Foundation
import Security

// A disposable locked Keychain containing synthetic bytes, never the login Keychain.
enum KeychainChecks {
    private enum Failure: Error { case checkFailed }
    static func run() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("quotabar-keychain-checks-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("fixture.keychain-db").path
        let password = Array(UUID().uuidString.utf8)
        var keychain: SecKeychain?
        let created = password.withUnsafeBytes { bytes in
            SecKeychainCreate(path, UInt32(bytes.count), bytes.baseAddress, false, nil, &keychain)
        }
        try require(created == errSecSuccess)
        guard let keychain else { throw Failure.checkFailed }
        defer {
            _ = try? KeychainInteraction.perform(allowUI: false) { SecKeychainDelete(keychain) }
        }
        let service = "QuotaBar test fixture", account = "synthetic", secret = Array("not-a-real-token".utf8)
        let added = service.withCString { serviceBytes in
            account.withCString { accountBytes in
                secret.withUnsafeBytes { secretBytes in
                    guard let secretAddress = secretBytes.baseAddress else { return errSecParam }
                    return SecKeychainAddGenericPassword(keychain, UInt32(service.utf8.count), serviceBytes,
                        UInt32(account.utf8.count), accountBytes, UInt32(secretBytes.count), secretAddress, nil)
                }
            }
        }
        try require(added == errSecSuccess)
        try require(SecKeychainLock(keychain) == errSecSuccess)
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
