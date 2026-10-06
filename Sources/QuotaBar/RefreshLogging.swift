#if os(macOS)
import Foundation
import OSLog
import QuotaCore

enum RefreshLogging {
    private static let logger = Logger(subsystem: "com.quotabar.app", category: "Refresh")
    static func record(_ report: RefreshDiagnostic, id: UUID, provider: Provider) {
        write(report.report(accountID: id, provider: provider).replacingOccurrences(of: "\n", with: " | "))
    }
    static func request(_ request: UsageRequestDiagnostic, id: UUID) {
        write("Account: \(id.uuidString) | Request: \(request.description)")
    }
    static func saved(id: UUID, kind: CredentialKind) {
        write("Account: \(id.uuidString) | Credential: \(kind.rawValue) | Keychain save: succeeded")
    }
    static func saveFailed(id: UUID, kind: CredentialKind, failure: DiagnosticFailure) {
        write("Account: \(id.uuidString) | Credential: \(kind.rawValue) | Keychain save: \(failure.description)")
    }
    private static func write(_ safeMessage: String) {
        logger.notice("\(safeMessage, privacy: .public)")
        FileHandle.standardError.write(Data("QuotaBar refresh: \(safeMessage)\n".utf8))
    }
}
#endif
