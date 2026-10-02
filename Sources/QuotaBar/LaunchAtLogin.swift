#if os(macOS)
import SwiftUI
import Observation
import ServiceManagement

@MainActor
@Observable
final class LaunchAtLogin {
    private(set) var enabled = false
    private(set) var requiresApproval = false
    private(set) var updating = false
    var error: String?
    var bundled: Bool { Bundle.main.bundleURL.pathExtension == "app" }
    func refresh() {
        guard bundled else { enabled = false; requiresApproval = false; return }
        let status = SMAppService.mainApp.status
        enabled = status == .enabled || status == .requiresApproval
        requiresApproval = status == .requiresApproval
    }
    func setEnabled(_ value: Bool) async {
        guard !updating else { return }
        error = nil
        guard bundled else { error = "Open the packaged QuotaBar.app to enable launch at login."; return }
        updating = true
        defer { updating = false; refresh() }
        do {
            if value { try SMAppService.mainApp.register() }
            else { try await SMAppService.mainApp.unregister() }
        } catch { self.error = error.localizedDescription }
    }
    func openLoginItems() { SMAppService.openSystemSettingsLoginItems() }
}
#endif
