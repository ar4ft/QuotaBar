#if os(macOS)
import SwiftUI
import QuotaCore

struct AlertSettings: View {
    @EnvironmentObject private var store: AccountStore
    @State private var alertAccountID = ""
    private var alertAccount: Account? { store.accounts.first { $0.id.uuidString == alertAccountID } }
    var body: some View {
        Form {
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
                if !store.accounts.isEmpty && !store.presentationMode {
                    Picker("Configure account", selection: $alertAccountID) {
                        ForEach(store.accounts) { Text(store.presentationMode ? $0.provider.title + " account" : "\($0.name) · \($0.provider.title)").tag($0.id.uuidString) }
                    }
                    if let account = alertAccount {
                        Toggle("Alerts for this account", isOn: preference(account, \.enabled))
                        Group {
                            Toggle("Use a custom consumption threshold", isOn: Binding(get: {
                                account.effectiveAlertPreferences.customThresholds != nil
                            }, set: { enabled in
                                store.updateAlertPreferences(account.id) { $0.customThresholds = enabled ? [90] : nil }
                            }))
                            if let threshold = account.effectiveAlertPreferences.customThresholds?.first {
                                Stepper("Warn at \(threshold)% consumed", value: Binding(get: { threshold }, set: { value in
                                    store.updateAlertPreferences(account.id) { $0.customThresholds = [value] }
                                }), in: 1...99)
                            } else {
                                Toggle("Warn at 80% consumed", isOn: preference(account, \.warnAt80))
                                Toggle("Warn at 95% consumed", isOn: preference(account, \.warnAt95))
                            }
                            if account.provider == .openAI {
                                Toggle("Warn when credits are low", isOn: Binding(get: {
                                    account.effectiveAlertPreferences.lowCreditThreshold != nil
                                }, set: { enabled in
                                    store.updateAlertPreferences(account.id) { $0.lowCreditThreshold = enabled ? 100 : nil }
                                }))
                                if let threshold = account.effectiveAlertPreferences.lowCreditThreshold {
                                    Stepper("Low-credit threshold: \(Int(threshold))", value: Binding(get: { threshold }, set: { value in
                                        store.updateAlertPreferences(account.id) { $0.lowCreditThreshold = value }
                                    }), in: 0...100_000, step: 10)
                                }
                                Text("Credit alerts require a numeric provider balance; unknown or unlimited balances never trigger them.").font(.caption).foregroundStyle(.secondary)
                            }
                            Toggle("Notify when allowance is available again", isOn: preference(account, \.notifyWhenAvailable))
                        }.disabled(!account.effectiveAlertPreferences.enabled)
                    }
                }
                Text("One threshold alert per window and reset cycle. Recovery alerts require a fresh provider reading, after exhaustion or a confirmed reset from at least 80% usage. macOS Focus settings can silence notifications.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
        .task { await store.refreshNotificationAuthorization(); selectAlertAccount() }
        .onChange(of: store.accounts.map(\.id)) { _, _ in selectAlertAccount() }
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
