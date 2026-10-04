#if os(macOS)
import SwiftUI
import AppKit
import QuotaCore

struct ClientSwitchView: View {
    let account: Account
    @EnvironmentObject private var store: AccountStore
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    @State private var finished = false
    private var client: String { account.provider == .openAI ? "Codex" : "Claude Code" }
    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: AppStyle.sectionSpacing) {
            HStack {
                Text("Use \(account.name)").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            VStack(alignment: .leading, spacing: 8) {
                Label(finished ? "Selected for \(client)" : "Select this subscription for \(client)",
                      systemImage: finished ? "checkmark.circle.fill" : "person.crop.circle.badge.checkmark")
                    .font(.headline).foregroundStyle(finished ? AppStyle.signal : .primary)
                Text(account.provider.title + " · " + (account.detail ?? account.name))
                    .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Text("Quit \(client), its desktop app, and related editor sessions first. The switch applies to new sessions. The outgoing sign-in is saved in Keychain, including tokens refreshed by the client.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if account.provider == .openAI {
                TextField("Codex home", text: $store.codexSwitchHome).textFieldStyle(.roundedBorder)
                Text("Choose the same home your client uses. File-backed authentication is required; configuration, projects, and history stay in place.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Switches the default Claude Code profile’s Keychain entry or existing credential file, and its account identity. Other machine and project preferences are preserved.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("A Claude web login supports monitoring only. To enable switching, reconnect this account using Save current CLI sign-in after signing in with Claude Code.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Use this account", action: switchAccount)
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(finished)
                Button("Restore previous sign-in", action: restoreAccount)
            }
            if let error { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            if let message = store.switchMessage { Label(message, systemImage: "checkmark.circle").fixedSize(horizontal: false, vertical: true) }
            Divider()
            Text("Desktop apps").font(.headline)
            Text("Claude Desktop and ChatGPT use their own sign-in. Switching the CLI does not switch those apps. For desktop use, open the app and select or sign in to the account there. Legacy Codex desktop builds may share the Codex home; confirm the account after reopening.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(account.provider == .openAI ? "Open OpenAI desktop app" : "Open Claude Desktop") { openDesktop() }
                Link("Authentication guide", destination: URL(string: account.provider == .openAI ?
                    "https://developers.openai.com/codex/auth/" : "https://code.claude.com/docs/en/authentication")!)
            }
        }.padding(AppStyle.pagePadding)
        }.frame(minWidth: 540, idealWidth: 640, minHeight: 440, idealHeight: 600)
        .tint(AppStyle.signal)
        .onChange(of: store.presentationMode) { _, hidden in if hidden { dismiss() } }
    }
    private func switchAccount() {
        do { try store.switchClient(to: account); error = nil; finished = true }
        catch { self.error = error.localizedDescription }
    }
    private func restoreAccount() {
        do { try store.restorePreviousClient(account.provider); error = nil; finished = false }
        catch { self.error = error.localizedDescription }
    }
    private func openDesktop() {
        let names = account.provider == .openAI ? ["Codex", "ChatGPT"] : ["Claude"]
        let roots = ["/Applications", NSHomeDirectory() + "/Applications"]
        for root in roots {
            for name in names {
                let url = URL(fileURLWithPath: root + "/" + name + ".app")
                if FileManager.default.fileExists(atPath: url.path) { NSWorkspace.shared.open(url); return }
            }
        }
        error = "The desktop app was not found in Applications. Open it from Finder and select the account there."
    }
}
#endif
