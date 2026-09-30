#if os(macOS)
import SwiftUI
import AppKit

@main
struct QuotaBarApp: App {
    @StateObject private var store = AccountStore()
    var body: some Scene {
        Window("QuotaBar", id: "dashboard") {
            DashboardView().environmentObject(store)
                .task { store.start() }
        }.defaultSize(width: 1080, height: 740)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Add Account…") { store.connect() }.keyboardShortcut("n")
                Button("Refresh Accounts") { Task { await store.refreshAll() } }.keyboardShortcut("r")
            }
        }
        MenuBarExtra {
            MenuBarView().environmentObject(store).task { store.start() }
        } label: {
            Image(systemName: "chart.bar.xaxis")
            if !store.refreshing.isEmpty { Text("↻") }
        }.menuBarExtraStyle(.window)
        Settings { PreferencesView().environmentObject(store) }
    }
}
#else
import Foundation
@main
struct UnsupportedPlatform {
    static func main() { print("QuotaBar is a native macOS 14+ app. Open Package.swift in Xcode on your Mac.") }
}
#endif
