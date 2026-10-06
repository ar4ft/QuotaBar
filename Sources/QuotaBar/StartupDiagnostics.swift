#if os(macOS)
import Foundation
import OSLog

enum StartupDiagnostics {
    private static let logger = Logger(subsystem: "com.quotabar.app", category: "Startup")

    // Call sites supply fixed milestone strings, never account details or credentials.
    static func record(_ milestone: String) {
        logger.notice("\(milestone, privacy: .public)")
        FileHandle.standardError.write(Data("QuotaBar startup: \(milestone)\n".utf8))
    }

    @MainActor private static var checking = false
    @MainActor static func verifyResponsivenessIfRequested() async {
        guard !checking,
              let index = CommandLine.arguments.firstIndex(of: "--verify-startup"),
              CommandLine.arguments.indices.contains(index + 1) else { return }
        checking = true
        // Several main-actor resumptions prove that the UI can service work,
        // rather than merely leaving an unresponsive process alive.
        do {
            for _ in 0..<20 { try await Task.sleep(for: .seconds(1)) }
            let marker = URL(fileURLWithPath: CommandLine.arguments[index + 1])
            try Data("ready\n".utf8).write(to: marker, options: .atomic)
            record("Main-thread responsiveness verified")
        } catch {
            record("Startup responsiveness check failed")
        }
    }
}
#endif
