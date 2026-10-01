import XCTest
@testable import QuotaCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class UsageParserTests: XCTestCase {
    func testCodexUsesProviderDurationAndReset() throws {
        let data = Data(#"{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":1,"reset_at":2000000000,"limit_window_seconds":18000},"secondary_window":{"used_percent":82,"reset_at":2000500000,"limit_window_seconds":604800}}}"#.utf8)
        let snapshot = try UsageParser.parse(data, provider: .openAI)
        XCTAssertEqual(snapshot.plan, "plus")
        XCTAssertEqual(snapshot.windows.map(\.title), ["5-hour session", "Weekly"])
        XCTAssertEqual(snapshot.windows[0].usedPercent, 1)
        XCTAssertEqual(snapshot.windows[0].resetsAt, Date(timeIntervalSince1970: 2_000_000_000))
    }
    func testNullQuotaIsUnknownRatherThanZero() throws {
        XCTAssertThrowsError(try UsageParser.parse(Data(#"{"rate_limit":null}"#.utf8), provider: .openAI))
        XCTAssertThrowsError(try UsageParser.parse(Data(#"{"five_hour":null,"seven_day":null}"#.utf8), provider: .claude))
    }
    func testClaudeDatesAndModelLimits() throws {
        let data = Data(#"{"five_hour":{"utilization":0,"resets_at":"2026-10-01T10:00:00.123Z"},"seven_day":{"utilization":"62.5","resets_at":"2026-10-06T10:00:00Z"},"seven_day_opus":{"utilization":90,"resets_at":null}}"#.utf8)
        let snapshot = try UsageParser.parse(data, provider: .claude)
        XCTAssertEqual(snapshot.windows.count, 3)
        XCTAssertEqual(snapshot.windows[0].usedPercent, 0)
        XCTAssertNotNil(snapshot.windows[0].resetsAt)
        XCTAssertNotNil(snapshot.windows[1].resetsAt)
        XCTAssertEqual(snapshot.windows[1].remainingPercent, 37.5)
        XCTAssertNil(snapshot.windows[2].resetsAt)
    }
    func testRejectsBooleanAndMalformedQuota() {
        for value in ["true", "\"oops\"", "null"] {
            let data = Data("{\"five_hour\":{\"utilization\":\(value)}}".utf8)
            XCTAssertThrowsError(try UsageParser.parse(data, provider: .claude))
        }
    }
    func testAdditionalCodexLimitsAndRelativeReset() throws {
        let data = Data(#"{"rate_limit":{"primary_window":{"used_percent":150,"reset_after_seconds":60}},"additional_rate_limits":[{"limit_name":"Spark","rate_limit":{"primary_window":{"used_percent":5}}}]}"#.utf8)
        let now = Date(timeIntervalSince1970: 1_000)
        let windows = try UsageParser.parse(data, provider: .openAI, now: now).windows
        XCTAssertEqual(windows.count, 2)
        XCTAssertEqual(windows[0].usedPercent, 100)
        XCTAssertEqual(windows[0].resetsAt, now.addingTimeInterval(60))
        XCTAssertEqual(windows[1].title, "Spark · Session")
    }
    func testReachedResetNeverClaimsQuotaAvailable() {
        let window = UsageWindow(id: "session", title: "Session", usedPercent: 100, resetsAt: Date(timeIntervalSince1970: 1))
        XCTAssertEqual(window.resetDescription(now: Date(timeIntervalSince1970: 2)), "Reset reached · refresh to confirm")
        XCTAssertEqual(window.usedPercent, 100)
    }
}

final class CredentialParserTests: XCTestCase {
    func testAPIKeysAreNotSubscriptionCredentials() {
        XCTAssertThrowsError(try CredentialParser.parse(Data(#"{"OPENAI_API_KEY":"sk-example"}"#.utf8), provider: .openAI))
    }
    func testImportedRefreshTokensRemainReadOnly() throws {
        let data = Data(#"{"tokens":{"access_token":"access","refresh_token":"refresh","account_id":"acct"}}"#.utf8)
        let imported = try CredentialParser.parse(data, provider: .openAI)
        XCTAssertEqual(imported.accountID, "acct")
        XCTAssertNil(imported.refreshToken)
        XCTAssertEqual(try CredentialParser.parse(data, provider: .openAI, ownsLogin: true).refreshToken, "refresh")
    }
    func testClaudeCodeCredentials() throws {
        let data = Data(#"{"claudeAiOauth":{"accessToken":"oauth-token","refreshToken":"not-imported"}}"#.utf8)
        let credential = try CredentialParser.parse(data, provider: .claude)
        XCTAssertEqual(credential.kind, .claudeOAuth)
        XCTAssertNil(credential.refreshToken)
    }
    func testMetadataDoesNotContainCredentials() throws {
        let account = Account(provider: .openAI, name: "Work")
        let string = String(decoding: try JSONEncoder().encode(account), as: UTF8.self)
        XCTAssertFalse(string.contains("secret"))
        XCTAssertFalse(string.contains("refreshToken"))
    }
}

actor MockTransport: HTTPTransport {
    var responses: [(Int, String, [String: String])]
    var requests: [URLRequest] = []
    init(_ responses: [(Int, String, [String: String])]) { self.responses = responses }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !responses.isEmpty else { throw QuotaError.malformedResponse }
        let (status, body, headers) = responses.removeFirst()
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!)
    }
    func recorded() -> [URLRequest] { requests }
}
final class UsageClientTests: XCTestCase {
    private let codexUsage = #"{"rate_limit":{"primary_window":{"used_percent":12}}}"#
    func testCodexSendsAccountIdentity() async throws {
        let mock = MockTransport([(200, codexUsage, [:])])
        _ = try await UsageClient(transport: mock).fetch(Credential(kind: .codex, secret: "test-access", accountID: "test-account"))
        let requests = await mock.recorded()
        XCTAssertEqual(requests[0].url?.absoluteString, "https://chatgpt.com/backend-api/wham/usage")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer test-access")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "ChatGPT-Account-Id"), "test-account")
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "Cookie"))
    }
    func testClaudeOAuthUsesBetaHeader() async throws {
        let mock = MockTransport([(200, #"{"five_hour":{"utilization":20}}"#, [:])])
        _ = try await UsageClient(transport: mock).fetch(Credential(kind: .claudeOAuth, secret: "test-token"))
        let requests = await mock.recorded()
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "anthropic-beta"), "oauth-2025-04-20")
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "ChatGPT-Account-Id"))
    }
    func testClaudeWebOrganizationDiscoveryAndCookie() async throws {
        let id = "00000000-0000-0000-0000-000000000001"
        let mock = MockTransport([(200, "[{\"uuid\":\"\(id)\"}]", [:]), (200, #"{"five_hour":{"utilization":20}}"#, [:])])
        _ = try await UsageClient(transport: mock).fetch(Credential(kind: .claudeWeb, secret: "test-session"))
        let requests = await mock.recorded()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[1].url?.path, "/api/organizations/\(id)/usage")
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Cookie"), "sessionKey=test-session")
        XCTAssertNil(requests[1].value(forHTTPHeaderField: "Authorization"))
    }
    func testMultipleOrganizationsRequireExplicitChoice() async throws {
        let mock = MockTransport([(200, #"[{"uuid":"00000000-0000-0000-0000-000000000001"},{"uuid":"00000000-0000-0000-0000-000000000002"}]"#, [:])])
        do {
            _ = try await UsageClient(transport: mock).fetch(Credential(kind: .claudeWeb, secret: "test"))
            XCTFail("Must not silently pick an organization")
        } catch { XCTAssertEqual(error as? QuotaError, .ambiguousOrganizations) }
    }
    func testUnauthorizedIsActionable() async throws {
        let mock = MockTransport([(401, "do not expose this body", [:])])
        do {
            _ = try await UsageClient(transport: mock).fetch(Credential(kind: .codex, secret: "test"))
            XCTFail("Expected expired session")
        } catch { XCTAssertEqual(error as? QuotaError, .unauthorized) }
    }
    func testRateLimitUsesRetryAfter() async throws {
        let mock = MockTransport([(429, "", ["Retry-After": "3600"])])
        do {
            _ = try await UsageClient(transport: mock).fetch(Credential(kind: .codex, secret: "test"))
            XCTFail("Expected backoff")
        } catch QuotaError.rateLimited(let date) { XCTAssertGreaterThan(date.timeIntervalSinceNow, 3500) }
    }
    func testRefreshRefusesImportedCredential() async throws {
        let mock = MockTransport([])
        do {
            _ = try await UsageClient(transport: mock).refreshOwnedCodex(Credential(kind: .codex, secret: "test"))
            XCTFail("Imported credentials must not be refreshed")
        } catch { XCTAssertEqual(error as? QuotaError, .unauthorized) }
        let requests = await mock.recorded()
        XCTAssertTrue(requests.isEmpty)
    }
    func testOwnedRefreshPreservesRotatedTokenAndIdentity() async throws {
        let mock = MockTransport([(200, #"{"access_token":"new-access","refresh_token":"rotated"}"#, [:])])
        let credential = Credential(kind: .codex, secret: "old", accountID: "acct", refreshToken: "owned-refresh")
        let refreshed = try await UsageClient(transport: mock).refreshOwnedCodex(credential)
        XCTAssertEqual(refreshed.secret, "new-access")
        XCTAssertEqual(refreshed.refreshToken, "rotated")
        XCTAssertEqual(refreshed.accountID, "acct")
    }
    func testHandedOffSessionCannotRotateClientRefreshToken() async throws {
        let mock = MockTransport([])
        var credential = Credential(kind: .codex, secret: "client-access", refreshToken: "client-refresh")
        credential.externallyManaged = true
        do {
            _ = try await UsageClient(transport: mock).refreshOwnedCodex(credential)
            XCTFail("Client-owned refresh tokens must not be used by QuotaBar")
        } catch { XCTAssertEqual(error as? QuotaError, .unauthorized) }
        let requests = await mock.recorded()
        XCTAssertTrue(requests.isEmpty)
    }
}
