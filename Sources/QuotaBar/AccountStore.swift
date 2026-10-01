#if os(macOS)
import SwiftUI
import QuotaCore
import UserNotifications

@MainActor
final class AccountStore: ObservableObject {
    @Published private(set) var accounts: [Account] = []
    @Published private(set) var refreshing: Set<UUID> = []
    @Published private(set) var errors: [UUID: String] = [:]
    @Published var globalError: String?
    @Published var showConnectionHealth = false
    @Published var presentedConnection: ConnectionRequest?
    @Published var presentedSwitch: Account?
    @Published var switchMessage: String?
    @AppStorage("codexSwitchHome") var codexSwitchHome = ProcessInfo.processInfo.environment["CODEX_HOME"] ?? NSHomeDirectory() + "/.codex"
    @AppStorage("activeCodexAccount") var activeCodexAccount = "" { willSet { objectWillChange.send() } }
    @AppStorage("activeClaudeAccount") var activeClaudeAccount = "" { willSet { objectWillChange.send() } }
    @AppStorage("refreshMinutes") var refreshMinutes = 5 { willSet { objectWillChange.send() } }
    @AppStorage("presentationMode") var presentationMode = false {
        willSet { objectWillChange.send() }
        didSet { if presentationMode { presentedConnection = nil; presentedSwitch = nil; switchMessage = nil; Task { await notifications.clearAll() } } }
    }
    @AppStorage("showRemaining") var showRemaining = false { willSet { objectWillChange.send() } }
    @AppStorage("notificationsEnabled") var notificationsEnabled = false { willSet { objectWillChange.send() } }
    @AppStorage("pinnedAccountID") var pinnedAccountID = "" { willSet { objectWillChange.send() } }
    @AppStorage("menuBarDisplay") var menuBarDisplayRaw = MenuBarDisplay.allowance.rawValue { willSet { objectWillChange.send() } }
    @AppStorage("shortcutEnabled") var shortcutEnabled = true { willSet { objectWillChange.send() } }
    @AppStorage("shortcutLetter") var shortcutLetter = "Q" { willSet { objectWillChange.send() } }
    @AppStorage("shortcutModifiers") var shortcutModifiersRaw = ShortcutModifiers.controlOption.rawValue { willSet { objectWillChange.send() } }
    @Published private(set) var connectionIssues: [UUID: ConnectionIssue] = [:]
    @AppStorage("pinnedWindowID") var pinnedWindowID = "" { willSet { objectWillChange.send() } }
    @Published private(set) var notificationAuthorization: UNAuthorizationStatus = .notDetermined
    @Published private(set) var requestingNotificationPermission = false
    @Published var notificationError: String?
    private let notifications = UsageNotifications()
    var pinnedAccount: Account? { accounts.first { $0.id.uuidString == pinnedAccountID } }
    var notificationsAuthorized: Bool { notificationAuthorization == .authorized || notificationAuthorization == .provisional }
    @AppStorage("accountSort") var accountSortRaw = AccountSort.allowance.rawValue { willSet { objectWillChange.send() } }
    @Published private(set) var clock = Date()
    @Published private(set) var histories: [UUID: [UsageSnapshot]] = [:]
    @Published private(set) var historyErrors: [UUID: String] = [:]
    private var resetAttempts: [UUID: ResetRefreshAttempt] = [:]
    private let historyRepository: UsageHistoryRepository
    var orderedAccounts: [Account] {
        if presentationMode { return AccountSort.added.sort(accounts, errorIDs: [], now: clock) }
        return (AccountSort(rawValue: accountSortRaw) ?? .allowance).sort(accounts, errorIDs: Set(errors.keys), now: clock)
    }
    func availability(_ account: Account) -> AccountAvailability {
        AccountAvailability.make(account, hasError: errors[account.id] != nil, now: clock)
    }
    func health(_ account: Account) -> ConnectionHealth {
        ConnectionHealth.make(snapshot: account.snapshot, issue: connectionIssues[account.id], now: clock)
    }
    func forecast(_ account: Account) -> UsageForecast? {
        guard errors[account.id] == nil,
              let window = AccountAvailability.mainWindows(account).max(by: { $0.usedPercent < $1.usedPercent }) else { return nil }
        return UsageForecast.estimate(histories[account.id] ?? [], windowID: window.id, now: clock)
    }
    var attentionCount: Int { accounts.filter { health($0).needsAttention }.count }
    func retryDate(_ id: UUID) -> Date? { cooldowns[id] }
    let root: URL
    private let vault = KeychainVault()
    private let client = UsageClient()
    private var cooldowns: [UUID: Date] = [:]
    private var resetCreditCooldowns: [UUID: Date] = [:]
    private var timerTask: Task<Void, Never>?
    private var scheduledRefreshTask: Task<Void, Never>?
    private var writable = true
    private let isPreview: Bool
    private var epoch: [UUID: UUID] = [:]
    var metadataURL: URL { root.appendingPathComponent("accounts.json") }

    init(previewAccounts: [Account]? = nil, previewDefaults: UserDefaults? = nil) {
        isPreview = previewAccounts != nil
        root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("QuotaBar", isDirectory: true)
        historyRepository = UsageHistoryRepository(directory: root.appendingPathComponent("History", isDirectory: true))
        if let previewAccounts {
            accounts = previewAccounts; writable = false
            if let previewDefaults {
                _presentationMode = AppStorage(wrappedValue: false, "presentationMode", store: previewDefaults)
                _showRemaining = AppStorage(wrappedValue: true, "showRemaining", store: previewDefaults)
                _accountSortRaw = AppStorage(wrappedValue: AccountSort.added.rawValue, "accountSort", store: previewDefaults)
                _pinnedAccountID = AppStorage(wrappedValue: "", "pinnedAccountID", store: previewDefaults)
            }
            return
        }
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
        guard !isPreview, timerTask == nil else { return }
        timerTask = Task { [weak self] in
            await self?.refreshNotificationAuthorization()
            self?.scheduleRefresh(allAccounts: true)
            var lastPeriodicRefresh = Date()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { break }
                let now = Date(); self?.clock = now
                let interval = min(60, max(1, self?.refreshMinutes ?? 5)) * 60
                if now.timeIntervalSince(lastPeriodicRefresh) >= Double(interval) {
                    if self?.scheduleRefresh(allAccounts: true) == true { lastPeriodicRefresh = now }
                } else { self?.scheduleRefresh(allAccounts: false) }
            }
        }
    }
    @discardableResult
    private func scheduleRefresh(allAccounts: Bool) -> Bool {
        guard scheduledRefreshTask == nil else { return false }
        scheduledRefreshTask = Task { [weak self] in
            defer { self?.scheduledRefreshTask = nil }
            if allAccounts { await self?.refreshAll() }
            else { await self?.refreshExpiredWindows() }
        }
        return true
    }
    @discardableResult
    func add(name: String, provider: Provider, credential: Credential, replacing: UUID? = nil) async throws -> UUID {
        guard writable else { throw CocoaError(.fileWriteNoPermission) }
        var account = Account(id: replacing ?? UUID(), provider: provider, name: name, detail: credential.email)
        account.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if account.name.isEmpty { account.name = credential.email ?? provider.title }
        let previous = accounts
        account.alertPreferences = accounts.first(where: { $0.id == account.id })?.alertPreferences
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
        epoch[account.id] = UUID(); cooldowns[account.id] = nil; resetCreditCooldowns[account.id] = nil; errors[account.id] = nil; connectionIssues[account.id] = nil
        // Wait for an older request to finish before refreshing the replacement.
        while refreshing.contains(account.id) { try await Task.sleep(for: .milliseconds(100)) }
        await refresh(account.id)
        return account.id
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
            errors[id] = nil; connectionIssues[id] = nil; cooldowns[id] = nil; resetCreditCooldowns[id] = nil; epoch[id] = nil
            if pinnedAccountID == id.uuidString { pinAccount("") }
            resetAttempts[id] = nil; histories[id] = nil; historyErrors[id] = nil
            Task {
                await notifications.removeNotifications(for: id)
                do { try await historyRepository.remove(id) }
                catch { globalError = "Could not remove usage history: \(error.localizedDescription)" }
            }
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
        guard !isPreview else { return }
        guard !refreshing.contains(id), accounts.contains(where: { $0.id == id }), writable else { return }
        if let until = cooldowns[id], until > Date() { return }
        let generation = epoch[id] ?? UUID(); epoch[id] = generation
        if let boundary = ResetRefreshPolicy.expiredBoundary(accounts.first(where: { $0.id == id })?.snapshot, now: Date()) {
            resetAttempts[id] = ResetRefreshPolicy.record(boundary: boundary, previous: resetAttempts[id], now: Date())
        }
        refreshing.insert(id)
        defer { refreshing.remove(id) }
        do {
            var credential = try vault.load(id: id)
            if credential.externallyManaged == true,
               let account = accounts.first(where: { $0.id == id }),
               activeAccountID(account.provider) == id.uuidString {
                let storage = try NativeClientStorage(provider: account.provider, codexHome: codexSwitchHome)
                if let live = try storage.read(), try live.belongs(to: credential) {
                    credential = try live.credential()
                    try vault.save(credential, id: id)
                }
            }
            var snapshot: UsageSnapshot
            do { snapshot = try await client.fetch(credential) }
            catch QuotaError.unauthorized where credential.refreshToken != nil && credential.externallyManaged != true {
                // Serialize per account, then persist rotated credentials before another usage request.
                credential = try await client.refreshOwnedCodex(credential)
                guard epoch[id] == generation else { return }
                try vault.save(credential, id: id)
                snapshot = try await client.fetch(credential)
            }
            if credential.kind == .codex, snapshot.availableResetCredits == nil,
               (resetCreditCooldowns[id] ?? .distantPast) <= Date() {
                do {
                    snapshot.availableResetCredits = try await client.fetchResetCredits(credential)
                    resetCreditCooldowns[id] = nil
                } catch QuotaError.rateLimited(let until) { resetCreditCooldowns[id] = until }
                catch { resetCreditCooldowns[id] = Date().addingTimeInterval(300) }
            }
            await refreshNotificationAuthorization()
            guard epoch[id] == generation, let index = accounts.firstIndex(where: { $0.id == id }) else { return }
            let previous = accounts[index]
            var preferences = previous.effectiveAlertPreferences
            preferences.enabled = preferences.enabled && notificationsEnabled && notificationsAuthorized
            let evaluation = UsageAlerts.evaluate(snapshot: snapshot, state: previous.alertState ?? [:], preferences: preferences, creditState: previous.creditAlertState)
            accounts[index].snapshot = snapshot
            accounts[index].alertState = evaluation.state
            accounts[index].creditAlertState = evaluation.creditState
            do { try persist() }
            catch { accounts[index] = previous; throw error }
            errors[id] = nil; connectionIssues[id] = nil; cooldowns[id] = nil
            if let boundary = ResetRefreshPolicy.expiredBoundary(snapshot, now: Date()) {
                if resetAttempts[id]?.boundary != boundary {
                    resetAttempts[id] = ResetRefreshPolicy.record(boundary: boundary, previous: nil, now: Date())
                }
            } else { resetAttempts[id] = nil }
            do { if !presentationMode { try await notifications.send(evaluation.alerts, account: accounts[index], maySend: { !self.presentationMode }) } }
            catch { notificationError = "Could not schedule an alert: \(error.localizedDescription)" }
            guard epoch[id] == generation else { return }
            do {
                let samples = try await historyRepository.record(snapshot, for: id)
                guard epoch[id] == generation else { return }
                histories[id] = samples; historyErrors[id] = nil
            } catch { historyErrors[id] = "History could not be saved: \(error.localizedDescription)" }
        } catch {
            guard epoch[id] == generation else { return }
            errors[id] = error.localizedDescription
            connectionIssues[id] = ConnectionIssue.classify(error)
            if case QuotaError.rateLimited(let until) = error { cooldowns[id] = until }
        }
    }
    private func refreshExpiredWindows() async {
        for account in accounts {
            guard !Task.isCancelled else { return }
            if ResetRefreshPolicy.isDue(account.snapshot, attempt: resetAttempts[account.id], cooldown: cooldowns[account.id], now: Date()) {
                await refresh(account.id)
            }
        }
    }
    func loadHistory(_ id: UUID) async {
        guard !isPreview else { return }
        guard accounts.contains(where: { $0.id == id }) else { return }
        do {
            let samples = try await historyRepository.load(id)
            guard accounts.contains(where: { $0.id == id }) else { return }
            if (samples.last?.fetchedAt ?? .distantPast) >= (histories[id]?.last?.fetchedAt ?? .distantPast) { histories[id] = samples }
            historyErrors[id] = nil
        } catch { historyErrors[id] = "History could not be read: \(error.localizedDescription)" }
    }
    func clearHistory(_ id: UUID) async {
        guard !refreshing.contains(id) else { return }
        refreshing.insert(id)
        defer { refreshing.remove(id) }
        do { try await historyRepository.remove(id); histories[id] = []; historyErrors[id] = nil }
        catch { historyErrors[id] = error.localizedDescription }
    }
    func pinAccount(_ id: String) {
        pinnedWindowID = ""; pinnedAccountID = id
    }
    func updateAlertPreferences(_ id: UUID, change: (inout AlertPreferences) -> Void) {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        let previous = accounts
        var preferences = accounts[index].effectiveAlertPreferences
        change(&preferences); accounts[index].alertPreferences = preferences
        do { try persist() } catch { accounts = previous; globalError = error.localizedDescription }
    }
    func refreshNotificationAuthorization() async {
        notificationAuthorization = await notifications.authorization()
    }
    func setNotificationsEnabled(_ enabled: Bool) async {
        guard !requestingNotificationPermission else { return }
        notificationError = nil
        if !enabled { notificationsEnabled = false; return }
        requestingNotificationPermission = true
        defer { requestingNotificationPermission = false }
        do {
            await refreshNotificationAuthorization()
            if notificationAuthorization == .notDetermined {
                let granted = try await notifications.requestAuthorization()
                await refreshNotificationAuthorization()
                notificationsEnabled = granted
            } else { notificationsEnabled = notificationsAuthorized }
            if !notificationsEnabled { notificationError = "Allow QuotaBar notifications in System Settings → Notifications, then enable usage alerts." }
        } catch { notificationError = error.localizedDescription; notificationsEnabled = false }
    }
    func activeAccountID(_ provider: Provider) -> String {
        provider == .openAI ? activeCodexAccount : activeClaudeAccount
    }
    func requestSwitch(_ account: Account) {
        guard !isPreview, !presentationMode else { return }
        switchMessage = nil; presentedSwitch = account
    }
    func saveCurrentClient(provider: Provider, name: String, replacing: UUID? = nil) async throws {
        guard !isPreview, !presentationMode, writable else { throw CocoaError(.fileWriteNoPermission) }
        try NativeClientStorage.ensureStopped(provider)
        let storage = try NativeClientStorage(provider: provider, codexHome: codexSwitchHome)
        guard let session = try storage.read() else { throw ClientSwitchError.incompleteSession }
        let credential = try session.credential()
        if let replacing, let previous = try? vault.load(id: replacing), previous.kind == credential.kind,
           let id = previous.accountID, let currentID = credential.accountID, id != currentID {
            throw NSError(domain: "QuotaBar", code: 3, userInfo: [NSLocalizedDescriptionKey:
                "The current CLI sign-in belongs to a different account. Add it as a new account instead."])
        }
        let known = try matchingAccount(session)
        let target = replacing ?? known?.id
        let id = try await add(name: name, provider: provider, credential: credential, replacing: target)
        setActive(id, provider: provider)
    }
    func switchClient(to account: Account) throws {
        guard !isPreview, !presentationMode, writable else { throw CocoaError(.fileWriteNoPermission) }
        guard !accounts.contains(where: { $0.provider == account.provider && refreshing.contains($0.id) }) else {
            throw NSError(domain: "QuotaBar", code: 4, userInfo: [NSLocalizedDescriptionKey: "Wait for this provider’s usage refresh to finish, then switch."])
        }
        try NativeClientStorage.ensureStopped(account.provider)
        let storage = try NativeClientStorage(provider: account.provider, codexHome: codexSwitchHome)
        let saved = try vault.load(id: account.id)
        var replacement = try ClientSession(credential: saved)
        if let live = try storage.read(), try live.belongs(to: saved) { replacement = live }
        let original = try storage.rawSnapshot()
        try ClientSessionSwitch.perform(replacement, storage: storage) { previous in
            let backup = ClientSecrets(service: "com.quotabar.client-backups", account: storage.backupKey)
            try backup.write(JSONEncoder().encode(original))
            if let previous { try saveDisplaced(previous) }
            // The CLI owns token renewal once this session is handed off, even if the switch later fails.
            var handedOff = try replacement.credential()
            handedOff.externallyManaged = true
            try vault.save(handedOff, id: account.id)
        }
        setActive(account.id, provider: account.provider)
        switchMessage = "\(account.name) is selected for \(account.provider == .openAI ? "Codex" : "Claude Code"). Start a new CLI or editor session and verify its account before working. Desktop sign-in may be separate."
    }
    func restorePreviousClient(_ provider: Provider) throws {
        guard !isPreview, !presentationMode, writable else { throw CocoaError(.fileWriteNoPermission) }
        guard !accounts.contains(where: { $0.provider == provider && refreshing.contains($0.id) }) else {
            throw NSError(domain: "QuotaBar", code: 4, userInfo: [NSLocalizedDescriptionKey: "Wait for usage refresh to finish before restoring."])
        }
        try NativeClientStorage.ensureStopped(provider)
        let storage = try NativeClientStorage(provider: provider, codexHome: codexSwitchHome)
        let vault = ClientSecrets(service: "com.quotabar.client-backups", account: storage.backupKey)
        guard let data = try vault.read() else {
            throw NSError(domain: "QuotaBar", code: 5, userInfo: [NSLocalizedDescriptionKey: "No previous sign-in backup exists for this client home."])
        }
        let previous = try JSONDecoder().decode(ClientBackup.self, from: data)
        let current = try storage.rawSnapshot()
        do { if let live = try storage.read() { try saveDisplaced(live) } }
        catch QuotaError.invalidCredentials { /* Retain malformed current bytes in place until restoring the backup. */ }
        catch ClientSwitchError.incompleteSession { /* A partial failed switch must still be recoverable. */ }
        do { try storage.restoreRaw(previous) }
        catch {
            do { try storage.restoreRaw(current) }
            catch { throw ClientSwitchError.rollbackFailed }
            throw error
        }
        // Keep the original recovery backup intact; any valid outgoing session was saved above.
        if provider == .openAI { activeCodexAccount = "" } else { activeClaudeAccount = "" }
        let restoredStorage = try NativeClientStorage(provider: provider, codexHome: codexSwitchHome)
        if let session = try restoredStorage.read(), let known = try matchingAccount(session) { setActive(known.id, provider: provider) }
        switchMessage = "Previous \(provider == .openAI ? "Codex" : "Claude Code") sign-in restored. Start a new client session."
    }
    private func setActive(_ id: UUID, provider: Provider) {
        if provider == .openAI { activeCodexAccount = id.uuidString } else { activeClaudeAccount = id.uuidString }
    }
    private func matchingAccount(_ session: ClientSession) throws -> Account? {
        for account in accounts where account.provider == session.provider {
            let credential = try vault.load(id: account.id)
            if try session.belongs(to: credential) { return account }
        }
        return nil
    }
    private func saveDisplaced(_ session: ClientSession) throws {
        let credential = try session.credential()
        if let known = try matchingAccount(session) { try vault.save(credential, id: known.id); return }
        var account = Account(provider: session.provider, name: credential.email ?? "Saved CLI sign-in", detail: credential.email)
        account.detail = credential.email ?? session.provider.subtitle
        try vault.save(credential, id: account.id)
        accounts.append(account)
        do { try persist() }
        catch { accounts.removeAll { $0.id == account.id }; try? vault.remove(id: account.id); throw error }
    }
    private func persist() throws {
        guard writable else { throw CocoaError(.fileWriteNoPermission) }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(accounts).write(to: metadataURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: metadataURL.path)
    }
    func connect(_ account: Account? = nil) {
        guard !presentationMode else { return }
        presentedConnection = ConnectionRequest(account: account)
    }
}
struct ConnectionRequest: Identifiable {
    let id = UUID()
    var account: Account?
}
#endif
