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
                    dark: false, contrast: false, size: NSSize(width: 380, height: 360), directory: directory)
        try capture(MenuBarView().environmentObject(store).environmentObject(updater), name: "menu-dark",
                    dark: true, contrast: false, size: NSSize(width: 380, height: 360), directory: directory)
        for tab in SettingsTab.allCases {
            for dark in [false, true] {
                try capture(PreferencesView(initialTab: tab).environmentObject(store).environmentObject(updater).environment(shortcut),
                            name: "settings-" + tab.rawValue + (dark ? "-dark" : "-light"), dark: dark, contrast: false,
                            size: NSSize(width: 740, height: 640), directory: directory)
            }
        }
        try capture(PreferencesView().environmentObject(store).environmentObject(updater).environment(shortcut),
                    name: "settings-compact", dark: false, contrast: false, size: NSSize(width: 680, height: 520), directory: directory)
        try capture(ClientSwitchView(account: personal).environmentObject(store), name: "switch-codex",
                    dark: false, contrast: false, size: NSSize(width: 660, height: 780), directory: directory)
        try capture(ClientSwitchView(account: work).environmentObject(store), name: "switch-claude",
                    dark: true, contrast: false, size: NSSize(width: 660, height: 780), directory: directory)
        defaults.set(true, forKey: "listLayout")
        try capture(DashboardView().environmentObject(store).defaultAppStorage(defaults), name: "dashboard-list",
                    dark: false, contrast: false, size: NSSize(width: 1120, height: 1000), directory: directory)
        defaults.set(false, forKey: "listLayout")
        store.activeCodexAccount = personal.id.uuidString
        try capture(DashboardView().environmentObject(store).defaultAppStorage(defaults), name: "dashboard-selected",
                    dark: false, contrast: false, size: NSSize(width: 1120, height: 900), directory: directory)
        var crowded = [personal, work]
        for index in 1...6 {
            var account = Account(provider: index.isMultiple(of: 2) ? .openAI : .claude,
                                  name: index == 1 ? "Research · a longer account label" : "Workspace \(index)",
                                  detail: "workspace\(index)@example.invalid")
            let primary = account.provider == .openAI ? "main-primary_window" : "five_hour"
            let weekly = account.provider == .openAI ? "main-secondary_window" : "seven_day"
            account.snapshot = UsageSnapshot(windows: [
                UsageWindow(id: primary, title: "5-hour session", usedPercent: index == 2 ? 100 : Double(index * 12),
                            resetsAt: now.addingTimeInterval(index == 3 ? -60 : 7200)),
                UsageWindow(id: weekly, title: "Weekly", usedPercent: Double(index * 10), resetsAt: now.addingTimeInterval(172800))
            ], fetchedAt: index == 4 ? now.addingTimeInterval(-1200) : now)
            crowded.append(account)
        }
        let crowdedStore = AccountStore(previewAccounts: crowded, previewDefaults: defaults)
        crowdedStore.activeCodexAccount = personal.id.uuidString
        crowdedStore.pinnedAccountID = personal.id.uuidString
        try capture(MenuBarView().environmentObject(crowdedStore).environmentObject(updater), name: "menu-many-accounts",
                    dark: false, contrast: false, size: NSSize(width: 380, height: 600), directory: directory)
        try capture(DashboardView().environmentObject(crowdedStore).defaultAppStorage(defaults), name: "dashboard-reading-states",
                    dark: true, contrast: false, size: NSSize(width: 1120, height: 1000), directory: directory)
        defaults.set(true, forKey: "listLayout")
        for (name, dark, width) in [("dashboard-list-many", true, 1120.0), ("dashboard-list-compact", false, 800.0)] {
            try capture(DashboardView().environmentObject(crowdedStore).defaultAppStorage(defaults), name: name,
                        dark: dark, contrast: false, size: NSSize(width: width, height: 1000), directory: directory)
        }
        store.presentationMode = true
        try capture(MenuBarView().environmentObject(store).environmentObject(updater), name: "menu-private",
                    dark: false, contrast: false, size: NSSize(width: 380, height: 340), directory: directory)
        try capture(DashboardView().environmentObject(store).defaultAppStorage(defaults), name: "presentation-mode",
                    dark: false, contrast: false, size: NSSize(width: 1120, height: 760), directory: directory)
    }
    private static func capture<V: View>(_ view: V, name: String, dark: Bool, contrast: Bool,
                                        size: NSSize, directory: URL) throws {
        let appearance: NSAppearance.Name = contrast ? .accessibilityHighContrastDarkAqua : dark ? .darkAqua : .aqua
        // Native controls use AppKit appearance, not just SwiftUI's colorScheme.
        NSApplication.shared.appearance = NSAppearance(named: appearance)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: view.environment(\.colorScheme, dark ? .dark : .light)
            .background(Color(nsColor: .windowBackgroundColor)))
        hosting.frame = NSRect(origin: .zero, size: size)
        window.contentView = hosting
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.75))
        hosting.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { throw CocoaError(.fileWriteUnknown) }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        guard let png = bitmap.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: directory.appendingPathComponent(name + ".png"))
        let metadata: [String: Any] = [
            "appearance": appearance.rawValue,
            "requestedHighContrastAppearance": contrast,
            "systemIncreaseContrast": NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast,
            "note": "Native appearance preview; a false systemIncreaseContrast does not exercise the full system accessibility setting."
        ]
        let data = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: directory.appendingPathComponent(name + ".json"))
        window.close()
    }
}
#endif
