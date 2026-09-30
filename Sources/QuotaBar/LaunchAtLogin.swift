#if os(macOS)
import SwiftUI
import ServiceManagement

@MainActor
final class LaunchAtLogin: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var requiresApproval = false
    @Published private(set) var updating = false
    @Published var error: String?
    var bundled: Bool { Bundle.main.bundleURL.pathExtension == "app" }
    init() { refresh() }
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
