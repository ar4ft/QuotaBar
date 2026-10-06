#if os(macOS)
import SwiftUI
import AppKit

@main
struct QuotaBarApp: App {
    @StateObject private var store = AccountStore()
    @State private var shortcut = GlobalShortcut()
    @StateObject private var updater = AppUpdater()
    init() {
        StartupDiagnostics.record("App initializer started")
        if CommandLine.arguments.contains("--verify-client-switching") {
            do { try ClientSwitchChecks.run(); exit(0) }
            catch { fputs("Native client-switch checks failed: \(error.localizedDescription)\n", stderr); exit(1) }
        }
        if let index = CommandLine.arguments.firstIndex(of: "--render-previews") {
            let path = CommandLine.arguments.indices.contains(index + 1) ? CommandLine.arguments[index + 1] : "dist/previews"
            do { try PolishPreviews.render(to: URL(fileURLWithPath: path, isDirectory: true)); exit(0) }
            catch { fputs("Could not render previews: \(error.localizedDescription)\n", stderr); exit(1) }
        }
        StartupDiagnostics.record("App initializer finished")
    }
    var body: some Scene {
        Window("QuotaBar", id: "dashboard") {
            DashboardView().environmentObject(store)
                .background(ShortcutBridge().environmentObject(store).environment(shortcut))
                .task {
                    StartupDiagnostics.record("Dashboard appeared")
                    store.start(); updater.start()
                    await StartupDiagnostics.verifyResponsivenessIfRequested()
                }
        }.defaultSize(width: 1080, height: 740)
        .windowStyle(.automatic)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { updater.check() }.disabled(!updater.canCheck)
            }
            CommandGroup(after: .newItem) {
                Button("Add Account…") { store.connect() }.keyboardShortcut("n")
                Button("Refresh Accounts") { Task { await store.refreshAll() } }.keyboardShortcut("r")
            }
        }
        MenuBarExtra {
            MenuBarView().environmentObject(store).environmentObject(updater)
                .background(ShortcutBridge().environmentObject(store).environment(shortcut)).task { store.start(); updater.start() }
        } label: {
            // Keep the status-item label free of task/onAppear/background side effects.
            MenuBarLabel().environmentObject(store)
        }.menuBarExtraStyle(.window)
        Settings {
            PreferencesView().environmentObject(store).environment(shortcut).environmentObject(updater)
                .background(ShortcutBridge().environmentObject(store).environment(shortcut))
        }
            .windowResizability(.contentSize)
    }
}
#else
import Foundation
@main
struct UnsupportedPlatform {
    static func main() { print("QuotaBar is a native macOS 14+ app. Open Package.swift in Xcode on your Mac.") }
}
#endif
