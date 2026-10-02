#if os(macOS)
import SwiftUI
import QuotaCore

struct GeneralSettings: View {
    @EnvironmentObject private var store: AccountStore
    @Environment(GlobalShortcut.self) private var shortcut
    @Environment(\.scenePhase) private var scenePhase
    @State private var login = LaunchAtLogin()
    var body: some View {
        Form {
            Section("General") {
                Picker("Refresh accounts every", selection: $store.refreshMinutes) {
                    Text("1 minute").tag(1); Text("5 minutes").tag(5); Text("15 minutes").tag(15); Text("30 minutes").tag(30)
                }
                Toggle("Presentation mode", isOn: $store.presentationMode)
                Text("Hides account identities and balances and silences usage alerts. Existing QuotaBar notifications are cleared when enabled.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Show remaining allowance in dashboard", isOn: $store.showRemaining)
                LaunchAtLoginToggle(login: login)
                if login.requiresApproval {
                    Text("Approve QuotaBar in Login Items to finish enabling launch at login.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Open Login Items") { login.openLoginItems() }
                }
                if let error = login.error { Text(error).font(.caption).foregroundStyle(.orange) }
                Text("Move QuotaBar.app to Applications before enabling launch at login.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Keyboard shortcut") {
                Toggle("Open dashboard from any app", isOn: $store.shortcutEnabled)
                HStack {
                    Picker("Modifiers", selection: $store.shortcutModifiersRaw) {
                        ForEach(ShortcutModifiers.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    Picker("Key", selection: $store.shortcutLetter) {
                        ForEach(Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init), id: \.self) { Text($0).tag($0) }
                    }.frame(width: 100)
                }.disabled(!store.shortcutEnabled)
                if let error = shortcut.error { Text(error).font(.caption).foregroundStyle(.orange) }
                Text("Default: Control + Option + Q. No Accessibility permission is needed.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
        .task { login.refresh() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { login.refresh() } }
    }

}
#endif
