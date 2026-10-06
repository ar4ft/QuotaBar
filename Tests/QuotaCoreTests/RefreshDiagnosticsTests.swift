import XCTest
@testable import QuotaCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private actor DiagnosticRecorder {
    private var events: [UsageRequestDiagnostic] = []
    func record(_ event: UsageRequestDiagnostic) { events.append(event) }
    func recorded() -> [UsageRequestDiagnostic] { events }
}

final class RefreshDiagnosticsTests: XCTestCase {
    private func jwt(_ payload: String) -> String {
        let part = Data(payload.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return "header.\(part).signature"
    }
    func testReportUsesAccessTokenExpiryAndExcludesCredentialData() throws {
        let access = jwt(#"{"exp":100,"email":"private@example.invalid","secret":"never-log"}"#)
        let data = try JSONSerialization.data(withJSONObject: ["tokens": [
            "access_token": access, "id_token": jwt(#"{"exp":2000000000}"#),
            "account_id": "provider-private-id", "refresh_token": "private-refresh"
        ]])
        let credential = try CredentialParser.parse(data, provider: .openAI)
        var diagnostic = RefreshDiagnostic(startedAt: Date(timeIntervalSince1970: 200))
        diagnostic.credential = CredentialDiagnostics(credential)
        diagnostic.stage = .usage; diagnostic.failure = .http(401); diagnostic.finished = true
        diagnostic.lastRequest = UsageRequestDiagnostic(endpoint: .codexUsage, result: .http(401))
        XCTAssertEqual(diagnostic.credential?.reportedExpiry, Date(timeIntervalSince1970: 100))
        XCTAssertEqual(diagnostic.credential?.renewal, .readOnly)
        let report = diagnostic.report(accountID: UUID(), provider: .openAI)
        XCTAssertTrue(report.contains("elapsed")); XCTAssertTrue(report.contains("HTTP 401"))
        for privateValue in [access, "private@example.invalid", "provider-private-id", "private-refresh", "never-log", "signature"] {
            XCTAssertFalse(report.contains(privateValue), privateValue)
        }
    }
    func testExpiryMetadataRejectsMalformedBooleanStringAndOversizedTokens() {
        for token in ["opaque-token", jwt(#"{"exp":true}"#), jwt(#"{"exp":"100"}"#),
                      jwt(#"{"exp":-1}"#), jwt(#"{"exp":1e300}"#), jwt("{invalid}"),
                      jwt(#"{"exp":100}"#) + String(repeating: "x", count: 16_384)] {
            XCTAssertNil(CredentialDiagnostics(Credential(kind: .codex, secret: token)).reportedExpiry)
        }
    }
    func testClientHandoffNeverClaimsAutomaticRenewal() {
        var credential = Credential(kind: .codex, secret: "opaque", refreshToken: "owned-refresh")
        XCTAssertEqual(CredentialDiagnostics(credential).renewal, .appOwned)
        credential.externallyManaged = true
        XCTAssertEqual(CredentialDiagnostics(credential).renewal, .clientManaged)
        XCTAssertNil(CredentialDiagnostics(credential).reportedExpiry)
    }
    func testUntrustedErrorMessagesAndDomainsCannotEnterDiagnostics() {
        let error = NSError(domain: "secret-domain", code: 123, userInfo: [NSLocalizedDescriptionKey: "Bearer secret-token"])
        XCTAssertEqual(DiagnosticFailure(error), .unknown)
        XCTAssertEqual(DiagnosticFailure(URLError(.timedOut)), .network(URLError.timedOut.rawValue))
        XCTAssertEqual(DiagnosticFailure(NSError(domain: NSOSStatusErrorDomain, code: -25308)), .keychain(-25308))
    }
    func testRejectedImportRecordsEndpointAndStatusWithoutBody() async throws {
        let recorder = DiagnosticRecorder()
        let client = UsageClient(transport: MockTransport([(401, "secret-response-body", [:])]),
                                 diagnostics: { await recorder.record($0) })
        do {
            _ = try await client.fetch(Credential(kind: .codex, secret: "private-access", accountID: "private-account"))
            XCTFail("Expected rejection")
        } catch { XCTAssertEqual(error as? QuotaError, .unauthorized) }
        let events = await recorder.recorded()
        XCTAssertEqual(events, [UsageRequestDiagnostic(endpoint: .codexUsage, result: .http(401))])
        XCTAssertFalse(events[0].description.contains("secret"))
        XCTAssertFalse(QuotaError.unauthorized.localizedDescription.contains("expired"))
    }
    func testRenewalFailureIdentifiesTokenEndpoint() async throws {
        let recorder = DiagnosticRecorder()
        let client = UsageClient(transport: MockTransport([(400, "private-refresh-error", [:])]),
                                 diagnostics: { await recorder.record($0) })
        do {
            _ = try await client.refreshOwnedCodex(Credential(kind: .codex, secret: "access", refreshToken: "refresh"))
            XCTFail("Expected renewal rejection")
        } catch { XCTAssertEqual(error as? QuotaError, .http(400)) }
        let events = await recorder.recorded()
        XCTAssertEqual(events, [UsageRequestDiagnostic(endpoint: .codexTokenRenewal, result: .http(400))])
    }
    func testTransportFailureRecordsOnlyAllowlistedNetworkCode() async {
        struct FailingTransport: HTTPTransport {
            func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
                throw NSError(domain: NSURLErrorDomain, code: -1001,
                              userInfo: [NSLocalizedDescriptionKey: "private-token in request"])
            }
        }
        let recorder = DiagnosticRecorder()
        let client = UsageClient(transport: FailingTransport(), diagnostics: { await recorder.record($0) })
        do { _ = try await client.fetch(Credential(kind: .codex, secret: "private-token")); XCTFail("Expected timeout") }
        catch {}
        let events = await recorder.recorded()
        XCTAssertEqual(events, [UsageRequestDiagnostic(endpoint: .codexUsage, result: .network(-1001))])
    }
}
