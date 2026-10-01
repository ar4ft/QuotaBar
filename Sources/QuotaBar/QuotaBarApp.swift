#if os(macOS)
import SwiftUI
import AppKit

@main
struct QuotaBarApp: App {
    @StateObject private var store = AccountStore()
    @StateObject private var shortcut = GlobalShortcut()
    @StateObject private var updater = AppUpdater()
    init() {
        if CommandLine.arguments.contains("--verify-client-switching") {
            do { try ClientSwitchChecks.run(); exit(0) }
            catch { fputs("Native client-switch checks failed: \(error.localizedDescription)\n", stderr); exit(1) }
        }
        if let index = CommandLine.arguments.firstIndex(of: "--render-previews") {
            let path = CommandLine.arguments.indices.contains(index + 1) ? CommandLine.arguments[index + 1] : "dist/previews"
            do { try PolishPreviews.render(to: URL(fileURLWithPath: path, isDirectory: true)); exit(0) }
            catch { fputs("Could not render previews: \(error.localizedDescription)\n", stderr); exit(1) }
        }
    }
    var body: some Scene {
        Window("QuotaBar", id: "dashboard") {
            DashboardView().environmentObject(store)
                .task { store.start(); updater.start() }
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
            MenuBarView().environmentObject(store).environmentObject(updater).task { store.start(); updater.start() }
        } label: {
            MenuBarLabel().environmentObject(store).task { store.start(); updater.start() }
                .background(ShortcutBridge().environmentObject(store).environmentObject(shortcut))
        }.menuBarExtraStyle(.window)
        Settings { PreferencesView().environmentObject(store).environmentObject(shortcut).environmentObject(updater) }
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
