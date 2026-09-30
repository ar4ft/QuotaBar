#if os(macOS)
import SwiftUI
import AppKit

@main
struct QuotaBarApp: App {
    @StateObject private var store = AccountStore()
    @StateObject private var shortcut = GlobalShortcut()
    @StateObject private var updater = AppUpdater()
    var body: some Scene {
        Window("QuotaBar", id: "dashboard") {
            DashboardView().environmentObject(store)
                .task { store.start(); updater.start() }
        }.defaultSize(width: 1080, height: 740)
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
    }
}
#else
import Foundation
@main
struct UnsupportedPlatform {
    static func main() { print("QuotaBar is a native macOS 14+ app. Open Package.swift in Xcode on your Mac.") }
}
#endif
