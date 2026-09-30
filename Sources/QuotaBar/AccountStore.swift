#if os(macOS)
import SwiftUI
import QuotaCore

@MainActor
final class AccountStore: ObservableObject {
    @Published private(set) var accounts: [Account] = []
    @Published private(set) var refreshing: Set<UUID> = []
    @Published private(set) var errors: [UUID: String] = [:]
    @Published var globalError: String?
    @Published var presentedConnection: ConnectionRequest?
    @AppStorage("refreshMinutes") var refreshMinutes = 5
    @AppStorage("showRemaining") var showRemaining = false
    let root: URL
    private let vault = KeychainVault()
    private let client = UsageClient()
    private var cooldowns: [UUID: Date] = [:]
    private var timerTask: Task<Void, Never>?
    private var writable = true
    private var epoch: [UUID: UUID] = [:]
    var metadataURL: URL { root.appendingPathComponent("accounts.json") }

    init() {
        root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("QuotaBar", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
            if FileManager.default.fileExists(atPath: metadataURL.path) {
                accounts = try JSONDecoder().decode([Account].self, from: Data(contentsOf: metadataURL))
                guard Set(accounts.map(\.id)).count == accounts.count else { throw QuotaError.malformedResponse }
            }
        } catch {
            writable = false
            globalError = "Account storage could not be opened. Existing files were preserved. \(error.localizedDescription)"
        }
    }
    func start() {
        guard timerTask == nil else { return }
        timerTask = Task { [weak self] in
            await self?.refreshAll()
            while !Task.isCancelled {
                let minutes = min(60, max(1, self?.refreshMinutes ?? 5))
                try? await Task.sleep(for: .seconds(minutes * 60))
                guard !Task.isCancelled else { break }
                await self?.refreshAll()
            }
        }
    }
    func add(name: String, provider: Provider, credential: Credential, replacing: UUID? = nil) async throws {
        guard writable else { throw CocoaError(.fileWriteNoPermission) }
        var account = Account(id: replacing ?? UUID(), provider: provider, name: name, detail: credential.email)
        account.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if account.name.isEmpty { account.name = credential.email ?? provider.title }
        let previous = accounts
        let previousCredential = replacing.flatMap { try? vault.load(id: $0) }
        try vault.save(credential, id: account.id)
        if let index = accounts.firstIndex(where: { $0.id == account.id }) { accounts[index] = account }
        else { accounts.append(account) }
        do { try persist() }
        catch {
            accounts = previous
            if let previousCredential { try? vault.save(previousCredential, id: account.id) }
            else { try? vault.remove(id: account.id) }
            throw error
        }
        epoch[account.id] = UUID(); cooldowns[account.id] = nil; errors[account.id] = nil
        // Wait for an older request to finish before refreshing the replacement.
        while refreshing.contains(account.id) { try await Task.sleep(for: .milliseconds(100)) }
        await refresh(account.id)
    }
    func rename(_ id: UUID, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        let previous = accounts; accounts[index].name = trimmed
        do { try persist() } catch { accounts = previous; globalError = error.localizedDescription }
    }
    func remove(_ id: UUID) {
        guard !refreshing.contains(id) else { return }
        let previous = accounts
        accounts.removeAll { $0.id == id }
        do {
            try persist()
            try vault.remove(id: id)
            errors[id] = nil; cooldowns[id] = nil; epoch[id] = nil
        } catch {
            accounts = previous; try? persist(); globalError = error.localizedDescription
        }
    }
    func refreshAll() async {
        for id in accounts.map(\.id) {
            guard !Task.isCancelled else { return }
            await refresh(id)
        }
    }
    func refresh(_ id: UUID) async {
        guard !refreshing.contains(id), accounts.contains(where: { $0.id == id }), writable else { return }
        if let until = cooldowns[id], until > Date() { return }
        let generation = epoch[id] ?? UUID(); epoch[id] = generation
        refreshing.insert(id)
        defer { refreshing.remove(id) }
        do {
            var credential = try vault.load(id: id)
            let snapshot: UsageSnapshot
            do { snapshot = try await client.fetch(credential) }
            catch QuotaError.unauthorized where credential.refreshToken != nil {
                // Serialize per account, then persist rotated credentials before another usage request.
                credential = try await client.refreshOwnedCodex(credential)
                guard epoch[id] == generation else { return }
                try vault.save(credential, id: id)
                snapshot = try await client.fetch(credential)
            }
            guard epoch[id] == generation, let index = accounts.firstIndex(where: { $0.id == id }) else { return }
            accounts[index].snapshot = snapshot
            errors[id] = nil; cooldowns[id] = nil
            try persist()
        } catch {
            guard epoch[id] == generation else { return }
            errors[id] = error.localizedDescription
            if case QuotaError.rateLimited(let until) = error { cooldowns[id] = until }
        }
    }
    private func persist() throws {
        guard writable else { throw CocoaError(.fileWriteNoPermission) }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(accounts).write(to: metadataURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: metadataURL.path)
    }
    func connect(_ account: Account? = nil) {
        presentedConnection = ConnectionRequest(account: account)
    }
}
struct ConnectionRequest: Identifiable {
    let id = UUID()
    var account: Account?
}
#endif
