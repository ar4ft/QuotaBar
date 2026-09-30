import XCTest
@testable import QuotaCore

final class CreditTests: XCTestCase {
    private let usage = #"{"rate_limit":{"primary_window":{"used_percent":100}},"credits":{"balance":"123.45","has_credits":true,"unlimited":false},"rate_limit_reset_credits":{"available_count":2}}"#
    func testReportedBalancesAreSeparateFromExhaustedAllowance() throws {
        let snapshot = try UsageParser.parse(Data(usage.utf8), provider: .openAI)
        XCTAssertEqual(snapshot.windows.first?.remainingPercent, 0)
        XCTAssertEqual(snapshot.credits?.balance, 123.45)
        XCTAssertEqual(snapshot.availableResetCredits, 2)
    }
    func testMissingCreditFieldsRemainUnknownAndOldSnapshotsDecode() throws {
        let old = #"{"windows":[],"fetchedAt":0}"#
        let decoded = try JSONDecoder().decode(UsageSnapshot.self, from: Data(old.utf8))
        XCTAssertNil(decoded.credits)
        XCTAssertNil(decoded.availableResetCredits)
        let data = Data(#"{"rate_limit":{"primary_window":{"used_percent":20}}}"#.utf8)
        XCTAssertNil(try UsageParser.parse(data, provider: .openAI).credits)
    }
    func testInvalidCreditsDoNotDiscardValidAllowance() throws {
        for balance in ["true", "-5", "\"NaN\"", "\"infinity\""] {
            let json = "{\"rate_limit\":{\"primary_window\":{\"used_percent\":20}},\"credits\":{\"balance\":\(balance)}}"
            let snapshot = try UsageParser.parse(Data(json.utf8), provider: .openAI)
            XCTAssertNil(snapshot.credits)
            XCTAssertEqual(snapshot.windows.first?.usedPercent, 20)
        }
    }
    func testAvailabilityAndUnlimitedCreditWithoutNumericBalance() throws {
        let json = #"{"rate_limit":{"primary_window":{"used_percent":20}},"credits":{"unlimited":true,"has_credits":true}}"#
        let snapshot = try UsageParser.parse(Data(json.utf8), provider: .openAI)
        XCTAssertNil(snapshot.credits?.balance)
        XCTAssertEqual(snapshot.credits?.display, "Unlimited")
    }
    func testResetInventoryRejectsFractionalBooleanNegativeAndOversizedCounts() throws {
        XCTAssertEqual(try UsageParser.parseResetCredits(Data(#"{"available_count":0}"#.utf8)), 0)
        for value in ["true", "-1", "1.5", "1e100", "null"] {
            XCTAssertThrowsError(try UsageParser.parseResetCredits(Data("{\"available_count\":\(value)}".utf8)))
        }
    }
    func testOlderPreferencesKeepExistingDefaults() throws {
        let old = #"{"enabled":true,"warnAt80":false,"warnAt95":true,"notifyWhenAvailable":true}"#
        let preferences = try JSONDecoder().decode(AlertPreferences.self, from: Data(old.utf8))
        XCTAssertEqual(preferences.thresholds, [95])
        XCTAssertNil(preferences.customThresholds)
        XCTAssertNil(preferences.lowCreditThreshold)
    }
    func testCustomThresholdReplacesPresetsAndDeduplicatesAfterPersistence() throws {
        var prefs = AlertPreferences(); prefs.customThresholds = [90, 90, -1, 100]
        XCTAssertEqual(prefs.thresholds, [90])
        let start = UsageSnapshot(windows: [UsageWindow(id: "main", title: "Session", usedPercent: 91, resetsAt: nil)], fetchedAt: Date(timeIntervalSince1970: 100))
        let first = UsageAlerts.evaluate(snapshot: start, state: [:], preferences: prefs)
        XCTAssertEqual(first.alerts.map(\.kind), [.threshold(90)])
        let saved = try JSONDecoder().decode([String: WindowAlertState].self, from: JSONEncoder().encode(first.state))
        var next = start; next.fetchedAt = next.fetchedAt.addingTimeInterval(1)
        XCTAssertTrue(UsageAlerts.evaluate(snapshot: next, state: saved, preferences: prefs).alerts.isEmpty)
    }
    func testCreditWarningsPersistAndRearmAfterTopUp() throws {
        var prefs = AlertPreferences(); prefs.lowCreditThreshold = 100
        func sample(_ balance: Double, _ time: Double) -> UsageSnapshot {
            UsageSnapshot(windows: [], fetchedAt: Date(timeIntervalSince1970: time), credits: CreditBalance(balance: balance))
        }
        let first = UsageAlerts.evaluate(snapshot: sample(80, 1), state: [:], preferences: prefs)
        XCTAssertEqual(first.alerts.map(\.kind), [.lowCredits(80)])
        let saved = try JSONDecoder().decode(CreditAlertState.self, from: JSONEncoder().encode(first.creditState!))
        let repeated = UsageAlerts.evaluate(snapshot: sample(70, 2), state: [:], preferences: prefs, creditState: saved)
        XCTAssertTrue(repeated.alerts.isEmpty)
        let topUp = UsageAlerts.evaluate(snapshot: sample(200, 3), state: [:], preferences: prefs, creditState: repeated.creditState)
        let low = UsageAlerts.evaluate(snapshot: sample(90, 4), state: [:], preferences: prefs, creditState: topUp.creditState)
        XCTAssertEqual(low.alerts.map(\.kind), [.lowCredits(90)])
    }
    func testUnknownUnlimitedDisabledAndOutOfOrderCreditsDoNotAlert() {
        var prefs = AlertPreferences(); prefs.lowCreditThreshold = 100
        for credits in [nil, CreditBalance(hasCredits: true), CreditBalance(balance: 0, unlimited: true)] {
            let snapshot = UsageSnapshot(windows: [], credits: credits)
            XCTAssertTrue(UsageAlerts.evaluate(snapshot: snapshot, state: [:], preferences: prefs).alerts.isEmpty)
        }
        let snapshot = UsageSnapshot(windows: [], fetchedAt: Date(timeIntervalSince1970: 1), credits: CreditBalance(balance: 0))
        prefs.enabled = false
        XCTAssertTrue(UsageAlerts.evaluate(snapshot: snapshot, state: [:], preferences: prefs).alerts.isEmpty)
        prefs.enabled = true
        let state = CreditAlertState(observedAt: Date(timeIntervalSince1970: 2), threshold: 100, notified: false)
        let result = UsageAlerts.evaluate(snapshot: snapshot, state: [:], preferences: prefs, creditState: state)
        XCTAssertTrue(result.alerts.isEmpty)
        XCTAssertEqual(result.creditState, state)
    }
    func testResetInventoryRequestIsAuthenticatedReadOnly() async throws {
        let transport = MockTransport([(200, #"{"available_count":3}"#, [:])])
        let count = try await UsageClient(transport: transport).fetchResetCredits(Credential(kind: .codex, secret: "test", accountID: "account"))
        XCTAssertEqual(count, 3)
        let request = await transport.recorded().first!
        XCTAssertEqual(request.url?.absoluteString, "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "ChatGPT-Account-Id"), "account")
        XCTAssertNil(request.httpBody)
    }
}
