#if os(macOS)
import SwiftUI

struct LaunchAtLoginToggle: View {
    let login: LaunchAtLogin
    @State private var enabled = false
    var body: some View {
        Toggle("Launch QuotaBar at login", isOn: $enabled)
            .disabled(login.updating)
            .onAppear { enabled = login.enabled }
            .onChange(of: login.enabled) { _, value in enabled = value }
            .onChange(of: enabled) { _, value in
                guard value != login.enabled else { return }
                Task { await login.setEnabled(value); enabled = login.enabled }
            }
    }
}
#endif
