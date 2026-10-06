#if os(macOS)
import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private static var shared: SettingsWindowController?
    static var settingsWindow: NSWindow? { shared?.window }

    static func show(store: AccountStore, shortcut: GlobalShortcut, updater: AppUpdater) {
        if shared == nil {
            shared = SettingsWindowController(store: store, shortcut: shortcut, updater: updater)
        }
        shared?.showWindow(nil)
    }

    private init(store: AccountStore, shortcut: GlobalShortcut, updater: AppUpdater) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 740, height: 640),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "QuotaBar Settings"
        window.identifier = NSUserInterfaceItemIdentifier("quotabar.settings")
        window.toolbarStyle = .automatic
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 680, height: 540)
        window.center()
        window.setFrameAutosaveName("QuotaBarSettings")
        window.delegate = self
        window.contentViewController = NSHostingController(rootView:
            PreferencesView().environmentObject(store).environmentObject(updater).environment(shortcut))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func showWindow(_ sender: Any?) {
        NSApplication.shared.setActivationPolicy(.regular)
        super.showWindow(sender)
        window?.deminiaturize(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        AppWindowActivation.update(excluding: window)
        // Retain the controller so reopening preserves the selected category and history.
    }
}

@MainActor
enum AppWindowActivation {
    static func update(excluding closingWindow: NSWindow? = nil) {
        let windows = [DashboardWindowController.window, SettingsWindowController.settingsWindow].compactMap { $0 }
        let hasWindow = windows.contains { $0 !== closingWindow && ($0.isVisible || $0.isMiniaturized) }
        NSApplication.shared.setActivationPolicy(hasWindow ? .regular : .accessory)
    }
}
#endif
