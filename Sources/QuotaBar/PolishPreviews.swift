#if os(macOS)
import SwiftUI
import AppKit
import QuotaCore

// Deterministic synthetic accounts only: previews never read credentials, poll providers, or save metadata.
@MainActor
struct PolishPreviews {
    static func render(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.finishLaunching()
        let domain = "com.quotabar.previews.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let now = Date()
        var personal = Account(provider: .openAI, name: "Personal", detail: "personal@example.invalid")
        personal.snapshot = UsageSnapshot(windows: [
            UsageWindow(id: "main-primary_window", title: "5-hour session", usedPercent: 42, resetsAt: now.addingTimeInterval(7200)),
            UsageWindow(id: "main-secondary_window", title: "Weekly", usedPercent: 76, resetsAt: now.addingTimeInterval(172800))
        ], plan: "plus", fetchedAt: now, credits: CreditBalance(balance: 250), availableResetCredits: 2)
        var work = Account(provider: .claude, name: "Work", detail: "work@example.invalid")
        work.snapshot = UsageSnapshot(windows: [
            UsageWindow(id: "five_hour", title: "5-hour session", usedPercent: 86, resetsAt: now.addingTimeInterval(3660)),
            UsageWindow(id: "seven_day", title: "Weekly", usedPercent: 51, resetsAt: now.addingTimeInterval(259200))
        ], plan: "pro", fetchedAt: now)
        let store = AccountStore(previewAccounts: [personal, work], previewDefaults: defaults)
        let updater = AppUpdater()
        let shortcut = GlobalShortcut()
        for (name, dark, contrast, width) in [("light", false, false, 1120.0), ("dark", true, false, 1120.0),
                                             ("high-contrast", true, true, 1120.0), ("compact", false, false, 800.0)] {
            try capture(DashboardView().environmentObject(store).defaultAppStorage(defaults),
                        name: "dashboard-" + name, dark: dark, contrast: contrast,
                        size: NSSize(width: width, height: 760), directory: directory)
        }
        try capture(MenuBarView().environmentObject(store).environmentObject(updater), name: "menu-light",
                    dark: false, contrast: false, size: NSSize(width: 380, height: 640), directory: directory)
        try capture(MenuBarView().environmentObject(store).environmentObject(updater), name: "menu-dark",
                    dark: true, contrast: false, size: NSSize(width: 380, height: 640), directory: directory)
        try capture(PreferencesView().environmentObject(store).environmentObject(updater).environmentObject(shortcut),
                    name: "settings-light", dark: false, contrast: false, size: NSSize(width: 620, height: 540), directory: directory)
        store.presentationMode = true
        try capture(DashboardView().environmentObject(store).defaultAppStorage(defaults), name: "presentation-mode",
                    dark: false, contrast: false, size: NSSize(width: 1120, height: 760), directory: directory)
    }
    private static func capture<V: View>(_ view: V, name: String, dark: Bool, contrast: Bool,
                                        size: NSSize, directory: URL) throws {
        let appearance: NSAppearance.Name = contrast ? .accessibilityHighContrastDarkAqua : dark ? .darkAqua : .aqua
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: view.environment(\.colorScheme, dark ? .dark : .light))
        hosting.frame = NSRect(origin: .zero, size: size)
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.75))
        hosting.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { throw CocoaError(.fileWriteUnknown) }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        guard let png = bitmap.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: directory.appendingPathComponent(name + ".png"))
        window.close()
    }
}
#endif
