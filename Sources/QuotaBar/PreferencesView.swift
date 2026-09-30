#if os(macOS)
import SwiftUI
import AppKit
import QuotaCore

struct PreferencesView: View {
    @EnvironmentObject private var store: AccountStore
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var login = LaunchAtLogin()
    @State private var alertAccountID = ""
    private var alertAccount: Account? { store.accounts.first { $0.id.uuidString == alertAccountID } }
    var body: some View {
        Form {
            Section("General") {
                Picker("Refresh accounts every", selection: $store.refreshMinutes) {
                    Text("1 minute").tag(1); Text("5 minutes").tag(5); Text("15 minutes").tag(15); Text("30 minutes").tag(30)
                }
                Toggle("Show remaining allowance in dashboard", isOn: $store.showRemaining)
                Toggle("Launch QuotaBar at login", isOn: Binding(get: { login.enabled }, set: { value in
                    Task { await login.setEnabled(value) }
                })).disabled(login.updating)
                if login.requiresApproval {
                    Text("Approve QuotaBar in Login Items to finish enabling launch at login.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Open Login Items") { login.openLoginItems() }
                }
                if let error = login.error { Text(error).font(.caption).foregroundStyle(.orange) }
                Text("Move QuotaBar.app to Applications before enabling launch at login.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Menu bar") {
                Picker("Pinned account", selection: Binding(get: { store.pinnedAccountID }, set: { store.pinAccount($0) })) {
                    Text("Icon only").tag("")
                    ForEach(store.accounts) { Text("\($0.name) · \($0.provider.title)").tag($0.id.uuidString) }
                }
                if let account = store.pinnedAccount {
                    Picker("Allowance window", selection: $store.pinnedWindowID) {
                        Text("Most constrained window").tag("")
                        ForEach(account.snapshot?.windows ?? []) { Text($0.title).tag($0.id) }
                        if !store.pinnedWindowID.isEmpty, !(account.snapshot?.windows.contains { $0.id == store.pinnedWindowID } ?? false) {
                            Text("Selected window unavailable").tag(store.pinnedWindowID)
                        }
                    }
                }
                Text("Shows remaining allowance beside the menu bar icon. A ~ marks a stale reading; — means no reading or a reset awaiting confirmation.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Usage alerts") {
                Toggle("Enable usage notifications", isOn: Binding(get: { store.notificationsEnabled }, set: { value in
                    Task { await store.setNotificationsEnabled(value) }
                })).disabled(store.requestingNotificationPermission)
                if store.requestingNotificationPermission { ProgressView().controlSize(.small) }
                if store.notificationsEnabled && !store.notificationsAuthorized {
                    Text("Notifications are blocked by macOS. Allow QuotaBar in System Settings.")
                        .font(.caption).foregroundStyle(.orange)
                }
                if let error = store.notificationError { Text(error).font(.caption).foregroundStyle(.orange) }
                Button("Open Notification Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
                if !store.accounts.isEmpty {
                    Picker("Configure account", selection: $alertAccountID) {
                        ForEach(store.accounts) { Text("\($0.name) · \($0.provider.title)").tag($0.id.uuidString) }
                    }
                    if let account = alertAccount {
                        Toggle("Alerts for this account", isOn: preference(account, \.enabled))
                        Group {
                            Toggle("Warn at 80% consumed", isOn: preference(account, \.warnAt80))
                            Toggle("Warn at 95% consumed", isOn: preference(account, \.warnAt95))
                            Toggle("Notify when allowance is available again", isOn: preference(account, \.notifyWhenAvailable))
                        }.disabled(!account.effectiveAlertPreferences.enabled)
                    }
                }
                Text("One threshold alert per window and reset cycle. Recovery alerts require a fresh provider reading, after exhaustion or a confirmed reset from at least 80% usage. macOS Focus settings can silence notifications.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).padding().frame(width: 540, height: 680)
            .task {
                login.refresh(); await store.refreshNotificationAuthorization()
                selectAlertAccount()
            }
            .onChange(of: store.accounts.map(\.id)) { _, _ in selectAlertAccount() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { login.refresh(); Task { await store.refreshNotificationAuthorization() } }
            }
    }
    private func selectAlertAccount() {
        if !store.accounts.contains(where: { $0.id.uuidString == alertAccountID }) {
            alertAccountID = store.accounts.first?.id.uuidString ?? ""
        }
    }
    private func preference(_ account: Account, _ keyPath: WritableKeyPath<AlertPreferences, Bool>) -> Binding<Bool> {
        Binding(get: {
            store.accounts.first(where: { $0.id == account.id })?.effectiveAlertPreferences[keyPath: keyPath] ?? false
        }, set: { value in
            store.updateAlertPreferences(account.id) { $0[keyPath: keyPath] = value }
        })
    }
}
#endif
