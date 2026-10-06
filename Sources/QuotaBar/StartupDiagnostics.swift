#if os(macOS)
import Foundation
import AppKit
import OSLog

enum StartupDiagnostics {
    private static let logger = Logger(subsystem: "com.quotabar.app", category: "Startup")

    // Call sites supply fixed milestone strings, never account details or credentials.
    static func record(_ milestone: String) {
        logger.notice("\(milestone, privacy: .public)")
        FileHandle.standardError.write(Data("QuotaBar startup: \(milestone)\n".utf8))
    }

    @MainActor private static var checking = false
    private enum VerificationFailure: Error { case missingWindow, closeFailed, backgroundClockStopped, reopenFailed }
    @MainActor static func verifyResponsivenessIfRequested(
        reopenDashboard: @escaping @MainActor () -> Void,
        clock: @escaping @MainActor () -> Date
    ) {
        guard !checking,
              let index = CommandLine.arguments.firstIndex(of: "--verify-startup"),
              CommandLine.arguments.indices.contains(index + 1) else { return }
        checking = true
        // An unstructured task survives the dashboard's view task being cancelled on close.
        Task { @MainActor in
            do {
                for _ in 0..<20 { try await Task.sleep(for: .seconds(1)) }
                record("Main-thread responsiveness verified")
                if CommandLine.arguments.contains("--verify-window-lifecycle") {
                    guard let window = DashboardWindowController.window, window.isVisible else {
                        throw VerificationFailure.missingWindow
                    }
                    let lastClock = clock()
                    DashboardWindowController.keepRunningInMenuBar()
                    try await Task.sleep(for: .seconds(1))
                    guard !window.isVisible, NSApplication.shared.activationPolicy() == .accessory else {
                        throw VerificationFailure.closeFailed
                    }
                    record("Dashboard closed; running in menu bar")
                    // The shared monitoring clock must advance even without the dashboard.
                    try await Task.sleep(for: .seconds(16))
                    guard NSApplication.shared.isRunning, clock() > lastClock else {
                        throw VerificationFailure.backgroundClockStopped
                    }
                    record("Background monitoring clock verified")
                    reopenDashboard()
                    try await Task.sleep(for: .seconds(1))
                    guard DashboardWindowController.window?.isVisible == true,
                          NSApplication.shared.activationPolicy() == .regular else {
                        throw VerificationFailure.reopenFailed
                    }
                    record("Dashboard reopened; window lifecycle verified")
                }
                let marker = URL(fileURLWithPath: CommandLine.arguments[index + 1])
                try Data("ready\n".utf8).write(to: marker, options: .atomic)
            } catch {
                record("Startup or window lifecycle check failed")
            }
        }
    }
}
#endif
