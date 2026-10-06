#if os(macOS)
import Foundation
import Security

// The login Keychain uses process-wide interaction settings. Serialize every
// synchronous access and restore the previous setting, including on failure.
// No lock or interaction override is held across network requests or awaits.
enum KeychainInteraction {
    private static let lock = NSRecursiveLock()
    static let permissionMessage = "Keychain permission is required. Choose Allow Keychain access to resume monitoring. Background refreshes will stay silent."

    static func perform<T>(allowUI: Bool, _ operation: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        guard !allowUI else { return try operation() }
        var previous: DarwinBoolean = false
        try check(SecKeychainGetUserInteractionAllowed(&previous))
        try check(SecKeychainSetUserInteractionAllowed(false))
        defer { SecKeychainSetUserInteractionAllowed(previous.boolValue) }
        return try operation()
    }

    static func requiresPermission(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == NSOSStatusErrorDomain &&
            [errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled].contains(OSStatus(error.code))
    }

    private static func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: SecCopyErrorMessageString(status, nil) as String? ?? "Keychain access failed"
            ])
        }
    }
}
#endif
