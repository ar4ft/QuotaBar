#if os(macOS)
import SwiftUI
import AppKit

@MainActor
final class QuotaBarDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@MainActor
enum DashboardWindowController {
    static weak var window: NSWindow?

    static func showDashboard(_ open: () -> Void) {
        NSApplication.shared.setActivationPolicy(.regular)
        open()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    static func keepRunningInMenuBar() {
        window?.performClose(nil)
        // A presented sheet may prevent closing; preserve the Dock in that case.
        if window?.isVisible != true { NSApplication.shared.setActivationPolicy(.accessory) }
    }
}

struct DashboardWindowBridge: NSViewRepresentable {
    func makeNSView(context: Context) -> DashboardWindowObserver { DashboardWindowObserver() }
    func updateNSView(_ nsView: DashboardWindowObserver, context: Context) {}
}

final class DashboardWindowObserver: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        DashboardWindowController.window = window
        window.identifier = NSUserInterfaceItemIdentifier("quotabar.dashboard")
    }
}
#endif
