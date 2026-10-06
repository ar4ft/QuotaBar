#if os(macOS)
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import QuotaCore

struct ConnectAccountView: View {
    @EnvironmentObject private var store: AccountStore
    @Environment(\.dismiss) private var dismiss
    let request: ConnectionRequest
    @State private var provider: Provider
    @State private var name: String
    @State private var executable = ""
    @State private var authFilePath = ""
    @State private var organization = ""
    @State private var organizations: [Organization] = []
    @State private var pendingCredential: Credential?
    @State private var showBrowser = false
    @State private var importing = false
    @State private var saving = false
    @State private var error: String?
    @State private var login = CodexLogin()
    init(request: ConnectionRequest) {
        self.request = request
        _provider = State(initialValue: request.account?.provider ?? .openAI)
        _name = State(initialValue: request.account?.name ?? "")
    }
    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: AppStyle.sectionSpacing) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(request.account == nil ? "Add an account" : "Reconnect account").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                    Text("Each account has its own credentials.").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(saving)
            }
            Picker("Provider", selection: $provider) {
                ForEach(Provider.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented).disabled(request.account != nil || login.running || importing || saving)
            TextField("Account name", text: $name, prompt: Text("Personal or Work")).textFieldStyle(.roundedBorder)
            if provider == .openAI {
                Text("Sign in with OpenAI").font(.headline)
                Text("Codex opens a device-code login in an isolated folder. Your usual Codex account is unaffected.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                TextField("Codex executable path (optional)", text: $executable).textFieldStyle(.roundedBorder)
                HStack {
                    Button(login.running ? "Restart login" : "Sign in with OpenAI") {
                        login.start(root: store.root, executable: executable) { save($0) }
                    }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(saving)
                    Link("Open verification page", destination: URL(string: "https://auth.openai.com/codex/device")!)
                }
                if !login.output.isEmpty {
                    ScrollView {
                        Text(login.output).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                    }.frame(height: 145).background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                }
                Text("Requires Codex CLI. Enable device-code login in ChatGPT security settings if requested.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Sign in to Claude").font(.headline)
                Text("A separate sign-in window keeps this account independent of Safari and your other accounts.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if !organizations.isEmpty {
                    Picker("Organization", selection: $organization) {
                        ForEach(organizations) { Text($0.name).tag($0.id) }
                    }
                    Button("Connect selected organization") {
                        if let credential = pendingCredential { save(credential) }
                    }.disabled(saving)
                }
                Button("Sign in to Claude") { organization = ""; organizations = []; pendingCredential = nil; showBrowser = true }.buttonStyle(.borderedProminent).disabled(saving)
                Text("If the embedded browser is blocked by your login provider, import Claude Code OAuth credentials below. Imported sessions require reconnecting when they expire.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            Button("Save current CLI sign-in") {
                saving = true; error = nil
                Task {
                    do {
                        try await store.saveCurrentClient(provider: provider, name: name, replacing: request.account?.id)
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                    saving = false
                }
            }.disabled(login.running || saving)
            Text("Sign in with \(provider == .openAI ? "Codex" : "Claude Code"), close its sessions, then save the current sign-in here. This retains the complete client session for account switching; macOS may ask for Keychain access.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if provider == .openAI {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Auth file path").font(.headline)
                    HStack {
                        TextField("Auth file path", text: $authFilePath, prompt: Text("~/.codex/auth.json"))
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { importAuthFilePath() }
                            .disabled(login.running || importing || saving)
                        Button("Import path") { importAuthFilePath() }
                            .disabled(authFilePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || login.running || importing || saving)
                    }
                    Text("Enter the full path to auth.json. Paths starting with ~/ work, including hidden folders such as .codex.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack {
                Button("Import credentials…") { browseCredentials() }.disabled(login.running || importing || saving)
                Text(provider == .openAI ? "Select Codex auth.json" : "Select Claude Code .credentials.json")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("The file picker shows hidden files and folders.")
                .font(.caption).foregroundStyle(.secondary)
            if saving { ProgressView("Saving account…").controlSize(.small) }
            if let message = error ?? login.error {
                Text(message).font(.callout).foregroundStyle(.red).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(AppStyle.pagePadding)
        }.frame(minWidth: 520, idealWidth: 600, minHeight: 480, idealHeight: 640)
        .sheet(isPresented: $showBrowser) {
            VStack(spacing: 0) {
                HStack {
                    Text("Claude · private sign-in session").font(.headline)
                    Spacer(); Button("Cancel") { showBrowser = false }.keyboardShortcut(.cancelAction)
                }.padding()
                ClaudeSignIn { credential in showBrowser = false; save(credential) }
            }.frame(minWidth: 580, idealWidth: 740, maxWidth: .infinity, minHeight: 440, idealHeight: 560, maxHeight: .infinity)
        }
        .onDisappear { login.cancel() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in login.cancel() }
    }
    private func importAuthFilePath() {
        guard provider == .openAI, !login.running, !importing, !saving else { return }
        let path = (authFilePath.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        guard !path.isEmpty else { return }
        guard (path as NSString).isAbsolutePath else {
            error = "Enter a full file path, such as ~/.codex/auth.json or /Users/yourname/.codex/auth.json."
            return
        }
        importCredentials(at: URL(fileURLWithPath: path))
    }
    private func browseCredentials() {
        guard !login.running, !importing, !saving else { return }
        let panel = NSOpenPanel()
        panel.title = "Import credentials"
        panel.prompt = "Import"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json, .data]
        panel.showsHiddenFiles = true
        if provider == .openAI {
            let path = (authFilePath.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
            panel.directoryURL = (path as NSString).isAbsolutePath
                ? URL(fileURLWithPath: path).deletingLastPathComponent()
                : FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
        }
        importing = true
        let completion: @MainActor @Sendable (NSApplication.ModalResponse) -> Void = { response in
            importing = false
            guard response == .OK, let url = panel.url else { return }
            if provider == .openAI { authFilePath = url.path }
            importCredentials(at: url)
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }
    private func importCredentials(at url: URL) {
        guard !login.running, !saving else { return }
        error = nil
        do {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard ((attributes[.size] as? NSNumber)?.intValue ?? Int.max) <= 1_048_576 else { throw QuotaError.invalidCredentials }
            save(try CredentialParser.parse(Data(contentsOf: url), provider: provider))
        } catch { self.error = error.localizedDescription }
    }
    private func save(_ credential: Credential) {
        guard !saving else { return }
        error = nil; saving = true
        Task {
            do {
                var credential = credential
                if credential.kind == .claudeWeb {
                    let id = organization.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !id.isEmpty {
                        guard UUID(uuidString: id) != nil else { throw QuotaError.invalidCredentials }
                        credential.accountID = id
                    } else {
                        let choices = try await UsageClient().organizations(credential)
                        if choices.count > 1 {
                            organizations = choices; organization = choices[0].id
                            pendingCredential = credential; saving = false
                            return
                        }
                        credential.accountID = choices[0].id
                    }
                }
                try await store.add(name: name, provider: provider, credential: credential, replacing: request.account?.id)
                dismiss()
            } catch { self.error = error.localizedDescription; saving = false }
        }
    }
}
#endif
