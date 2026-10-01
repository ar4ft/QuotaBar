import XCTest
@testable import QuotaCore

final class ClientSwitchTests: XCTestCase {
    private func codex(_ access: String, account: String = "one") throws -> ClientSession {
        try ClientSession(provider: .openAI, authentication: Data("{\"tokens\":{\"access_token\":\"\(access)\",\"id_token\":\"id\",\"refresh_token\":\"refresh-\(access)\",\"account_id\":\"\(account)\"},\"unknown\":true}".utf8))
    }
    func testCompletePayloadRetainedWithoutGrantingImportedRefreshOwnership() throws {
        let session = try codex("token")
        let credential = try CredentialParser.parse(session.authentication, provider: .openAI)
        XCTAssertNil(credential.refreshToken)
        XCTAssertEqual(credential.nativeSession, session.authentication)
        XCTAssertEqual(try ClientSession(credential: credential), session)
        XCTAssertTrue(try session.credential().externallyManaged == true)
    }
    func testMonitoringAndWebTokensCannotBecomeCodexSessions() throws {
        XCTAssertThrowsError(try ClientSession(provider: .openAI, authentication: Data(#"{"tokens":{"access_token":"access"}}"#.utf8)))
        XCTAssertThrowsError(try ClientSession(credential: Credential(kind: .claudeWeb, secret: "sessionKey")))
        XCTAssertThrowsError(try ClientSession(credential: Credential(kind: .codex, secret: "access")))
    }
    func testClaudeUsageOnlyScopesCannotAuthenticateCode() {
        XCTAssertThrowsError(try ClientSession(provider: .claude, authentication:
            Data(#"{"claudeAiOauth":{"accessToken":"monitoring-token","scopes":["user:profile"]}}"#.utf8)))
    }
    func testCodexRefreshUpdatesExportedTokensAndPreservesUnknownFields() throws {
        var credential = try CredentialParser.parse(codex("old").authentication, provider: .openAI, ownsLogin: true)
        credential = try ClientSession.updatingCodex(credential, response: ["access_token": "new", "refresh_token": "rotated", "id_token": "new-id"])
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(credential.nativeSession)) as? [String: Any])
        let tokens = try XCTUnwrap(root["tokens"] as? [String: Any])
        XCTAssertEqual(tokens["refresh_token"] as? String, "rotated")
        XCTAssertEqual(tokens["id_token"] as? String, "new-id")
        XCTAssertEqual(tokens["access_token"] as? String, credential.secret)
        XCTAssertEqual(root["unknown"] as? Bool, true)
        XCTAssertNotNil(root["last_refresh"])
    }
    func testIdentityMatchesRefreshedTokenButNotAnotherWorkspace() throws {
        let saved = try codex("old").credential()
        XCTAssertTrue(try codex("new").belongs(to: saved))
        XCTAssertFalse(try codex("old", account: "another-workspace").belongs(to: saved))
    }
    func testClaudeChangesAccountWithoutReplacingProjectPreferences() throws {
        let auth = Data(#"{"claudeAiOauth":{"accessToken":"claude","refreshToken":"renew","scopes":["user:inference"]},"futureKey":7}"#.utf8)
        let current = try ClientSession(provider: .claude, authentication: auth, settings: Data(#"{"oauthAccount":{"accountUuid":"old","emailAddress":"old@example.invalid"},"projects":{"/work":{"trusted":true}},"theme":"dark","cachedGrowthBookFeatures":{"old":true}}"#.utf8))
        let next = try ClientSession(provider: .claude, authentication: auth, settings: Data(#"{"oauthAccount":{"accountUuid":"new","emailAddress":"new@example.invalid"},"theme":"light"}"#.utf8))
        let merged = try next.mergingSettings(from: current)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(merged.settings)) as? [String: Any])
        XCTAssertEqual(root["theme"] as? String, "dark")
        XCTAssertNotNil(root["projects"])
        XCTAssertNil(root["cachedGrowthBookFeatures"])
        XCTAssertEqual(try merged.credential().accountID, "new")
        XCTAssertEqual(try merged.credential().email, "new@example.invalid")
        XCTAssertFalse(try merged.belongs(to: current.credential()))
        XCTAssertEqual(merged.authentication, auth)
    }
    func testMissingClaudeIdentityNeverInheritsPreviousAccount() throws {
        let auth = Data(#"{"claudeAiOauth":{"accessToken":"token","scopes":["user:inference"]}}"#.utf8)
        let current = try ClientSession(provider: .claude, authentication: auth, settings: Data(#"{"oauthAccount":{"accountUuid":"old"},"theme":"dark"}"#.utf8))
        let next = try ClientSession(provider: .claude, authentication: auth)
        let merged = try next.mergingSettings(from: current)
        XCTAssertNil(try merged.credential().accountID)
    }
    func testSaveOutgoingRotatedSessionBeforeWritingReplacement() throws {
        let old = try codex("rotated")
        let storage = MemoryClientStorage(old)
        var saved: ClientSession?
        try ClientSessionSwitch.perform(codex("replacement", account: "two"), storage: storage) { value in
            XCTAssertEqual(storage.writes, 0)
            saved = value
        }
        XCTAssertEqual(saved, old)
        XCTAssertEqual(storage.value, try codex("replacement", account: "two"))
    }
    func testBackupFailureLeavesLiveSignInUntouched() throws {
        let old = try codex("old"), storage = MemoryClientStorage(old)
        XCTAssertThrowsError(try ClientSessionSwitch.perform(codex("next"), storage: storage) { _ in throw TestFailure.injected })
        XCTAssertEqual(storage.value, old)
        XCTAssertEqual(storage.writes, 0)
    }
    func testPartialWriteFailureRestoresExactPreviousBytes() throws {
        let old = try codex("old"), storage = MemoryClientStorage(old)
        storage.failWrite = true
        XCTAssertThrowsError(try ClientSessionSwitch.perform(codex("next"), storage: storage) { _ in })
        XCTAssertEqual(storage.value, old)
        XCTAssertEqual(storage.restores, 1)
    }
    func testRollbackFailureIsReported() throws {
        let storage = MemoryClientStorage(try codex("old"))
        storage.failWrite = true; storage.failRestore = true
        XCTAssertThrowsError(try ClientSessionSwitch.perform(codex("next"), storage: storage) { _ in }) { error in
            guard case ClientSwitchError.rollbackFailed = error else { return XCTFail("Expected recovery error") }
        }
    }
    func testConcurrentCredentialChangeIsNeverOverwritten() throws {
        let old = try codex("old"), changed = try codex("changed"), storage = MemoryClientStorage(old)
        XCTAssertThrowsError(try ClientSessionSwitch.perform(codex("next"), storage: storage) { _ in storage.value = changed })
        XCTAssertEqual(storage.value, changed)
        XCTAssertEqual(storage.writes, 0)
        XCTAssertEqual(storage.restores, 0)
    }
    func testStorageDetectingRaceDoesNotRestoreStaleCredentials() throws {
        let storage = MemoryClientStorage(try codex("old"))
        storage.raceOnWrite = true
        XCTAssertThrowsError(try ClientSessionSwitch.perform(codex("next"), storage: storage) { _ in })
        XCTAssertEqual(storage.restores, 0)
    }
    func testPreviouslyAbsentCredentialsAreRemovedOnFailedSwitch() throws {
        let storage = MemoryClientStorage(nil); storage.failWrite = true
        XCTAssertThrowsError(try ClientSessionSwitch.perform(codex("next"), storage: storage) { XCTAssertNil($0) })
        XCTAssertNil(storage.value)
    }
    func testSecureFilePermissionsAndSymlinkRejection() throws {
        // macOS presents its temp directory through /var, a system symlink; this test deliberately rejects links.
        let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".quotabar-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { if FileManager.default.fileExists(atPath: folder.path) { try? FileManager.default.removeItem(at: folder) } }
        var stage = "writing a private credential file"
        do {
        let path = folder.appendingPathComponent("profile/auth.json")
        let data = try codex("private").authentication
        try SecureClientFile.write(data, to: path)
        stage = "reading the private credential file"
        XCTAssertEqual(try SecureClientFile.read(path), data)
        let attributes = try FileManager.default.attributesOfItem(atPath: path.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        let link = folder.appendingPathComponent("linked")
        stage = "creating a directory symlink"
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: path.deletingLastPathComponent())
        XCTAssertThrowsError(try SecureClientFile.write(Data("different".utf8), to: link.appendingPathComponent("auth.json")))
        XCTAssertEqual(try SecureClientFile.read(path), data)
        stage = "removing the credential file"
        try SecureClientFile.write(nil, to: path)
        XCTAssertNil(try SecureClientFile.read(path))
        } catch { XCTFail("Failed while \(stage): \(error)") }
    }
}

private enum TestFailure: Error { case injected }
private final class MemoryClientStorage: ClientSessionStorage {
    var value: ClientSession?
    var failWrite = false, failRestore = false, raceOnWrite = false
    var writes = 0, restores = 0
    init(_ value: ClientSession?) { self.value = value }
    func read() throws -> ClientSession? { value }
    func write(_ session: ClientSession) throws {
        if raceOnWrite { throw ClientSwitchError.changedDuringSwitch }
        writes += 1; value = session
        if failWrite { throw TestFailure.injected }
    }
    func restore(_ session: ClientSession?) throws {
        restores += 1
        if failRestore { throw TestFailure.injected }
        value = session
    }
}
