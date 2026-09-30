import XCTest
@testable import QuotaCore

final class UsageAlertsTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 10_000)
    private func snapshot(_ percent: Double, at offset: Double = 0, reset: Double? = 100) -> UsageSnapshot {
        UsageSnapshot(windows: [UsageWindow(id: "session", title: "Session", usedPercent: percent,
                                           resetsAt: reset.map { start.addingTimeInterval($0) })],
                      fetchedAt: start.addingTimeInterval(offset))
    }
    func testInitialHighReadingSendsOnlyHigherThreshold() {
        let result = UsageAlerts.evaluate(snapshot: snapshot(97), state: [:], preferences: AlertPreferences())
        XCTAssertEqual(result.alerts.count, 1)
        XCTAssertEqual(result.alerts.first?.kind, .threshold(95))
        XCTAssertEqual(result.state["session"]?.notifiedThresholds, [80, 95])
    }
    func testThresholdCrossingsAndDeduplicationSurvivePersistence() throws {
        var state = UsageAlerts.evaluate(snapshot: snapshot(70), state: [:], preferences: AlertPreferences()).state
        let warning = UsageAlerts.evaluate(snapshot: snapshot(81, at: 1), state: state, preferences: AlertPreferences())
        XCTAssertEqual(warning.alerts.first?.kind, .threshold(80))
        state = try JSONDecoder().decode([String: WindowAlertState].self, from: JSONEncoder().encode(warning.state))
        let repeated = UsageAlerts.evaluate(snapshot: snapshot(89, at: 2), state: state, preferences: AlertPreferences())
        XCTAssertTrue(repeated.alerts.isEmpty)
        let critical = UsageAlerts.evaluate(snapshot: snapshot(96, at: 3), state: repeated.state, preferences: AlertPreferences())
        XCTAssertEqual(critical.alerts.first?.kind, .threshold(95))
        XCTAssertTrue(UsageAlerts.evaluate(snapshot: snapshot(100, at: 4), state: critical.state, preferences: AlertPreferences()).alerts.isEmpty)
    }
    func testElapsedClockAndUnchangedUsageDoNotAnnounceRecovery() {
        let state = UsageAlerts.evaluate(snapshot: snapshot(100), state: [:], preferences: AlertPreferences()).state
        let result = UsageAlerts.evaluate(snapshot: snapshot(100, at: 110), state: state, preferences: AlertPreferences())
        XCTAssertTrue(result.alerts.isEmpty)
    }
    func testConfirmedResetAnnouncesRecoveryAndRearmsThresholds() {
        let state = UsageAlerts.evaluate(snapshot: snapshot(97), state: [:], preferences: AlertPreferences()).state
        let reset = UsageAlerts.evaluate(snapshot: snapshot(2, at: 110, reset: 200), state: state, preferences: AlertPreferences())
        XCTAssertEqual(reset.alerts.first?.kind, .availableAgain)
        XCTAssertEqual(reset.state["session"]?.notifiedThresholds, [])
        let next = UsageAlerts.evaluate(snapshot: snapshot(81, at: 120, reset: 200), state: reset.state, preferences: AlertPreferences())
        XCTAssertEqual(next.alerts.first?.kind, .threshold(80))
    }
    func testTimestampCorrectionBeforeResetDoesNotRearmThresholdsOrAnnounceRecovery() {
        let state = UsageAlerts.evaluate(snapshot: snapshot(96), state: [:], preferences: AlertPreferences()).state
        let corrected = UsageAlerts.evaluate(snapshot: snapshot(10, at: 1, reset: 120), state: state, preferences: AlertPreferences())
        XCTAssertTrue(corrected.alerts.isEmpty)
        XCTAssertEqual(corrected.state["session"]?.notifiedThresholds, [80, 95])
    }
    func testRecoveryWithoutResetTimestampDoesNotRepeatOrRearmThresholds() {
        let state = UsageAlerts.evaluate(snapshot: snapshot(100, reset: nil), state: [:], preferences: AlertPreferences()).state
        let recovered = UsageAlerts.evaluate(snapshot: snapshot(90, at: 1, reset: nil), state: state, preferences: AlertPreferences())
        XCTAssertEqual(recovered.alerts.map(\.kind), [.availableAgain])
        let full = UsageAlerts.evaluate(snapshot: snapshot(100, at: 2, reset: nil), state: recovered.state, preferences: AlertPreferences())
        XCTAssertTrue(full.alerts.isEmpty)
        let secondDrop = UsageAlerts.evaluate(snapshot: snapshot(90, at: 3, reset: nil), state: full.state, preferences: AlertPreferences())
        XCTAssertTrue(secondDrop.alerts.isEmpty)
    }
    func testOutOfOrderReadingsAreIgnored() {
        let state = UsageAlerts.evaluate(snapshot: snapshot(97, at: 10), state: [:], preferences: AlertPreferences()).state
        let result = UsageAlerts.evaluate(snapshot: snapshot(0, at: 5), state: state, preferences: AlertPreferences())
        XCTAssertTrue(result.alerts.isEmpty)
        XCTAssertEqual(result.state, state)
    }
    func testAccountAndThresholdPreferencesSuppressAlerts() {
        var preferences = AlertPreferences(); preferences.enabled = false
        let disabled = UsageAlerts.evaluate(snapshot: snapshot(97), state: [:], preferences: preferences)
        XCTAssertTrue(disabled.alerts.isEmpty)
        preferences.enabled = true; preferences.warnAt80 = false
        let enabled = UsageAlerts.evaluate(snapshot: snapshot(97, at: 1), state: disabled.state, preferences: preferences)
        XCTAssertEqual(enabled.alerts.map(\.kind), [.threshold(95)])
    }
    func testRecoveryPreferenceIsRespected() {
        var preferences = AlertPreferences(); preferences.notifyWhenAvailable = false
        let state = UsageAlerts.evaluate(snapshot: snapshot(100), state: [:], preferences: preferences).state
        XCTAssertTrue(UsageAlerts.evaluate(snapshot: snapshot(0, at: 110, reset: 200), state: state, preferences: preferences).alerts.isEmpty)
    }
    func testWindowsHaveIndependentReceipts() {
        let state = UsageAlerts.evaluate(snapshot: snapshot(85), state: [:], preferences: AlertPreferences()).state
        var next = snapshot(85, at: 1)
        next.windows.append(UsageWindow(id: "weekly", title: "Weekly", usedPercent: 97, resetsAt: nil))
        let result = UsageAlerts.evaluate(snapshot: next, state: state, preferences: AlertPreferences())
        XCTAssertEqual(result.alerts.count, 1)
        XCTAssertEqual(result.alerts[0].windowID, "weekly")
    }
    func testOldAccountMetadataRemainsReadable() throws {
        let original = Account(provider: .openAI, name: "Existing account")
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as! [String: Any]
        json.removeValue(forKey: "alertPreferences"); json.removeValue(forKey: "alertState")
        let account = try JSONDecoder().decode(Account.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(account.effectiveAlertPreferences.enabled)
        XCTAssertNil(account.alertState)
    }
}

final class PinnedAllowanceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 10_000)
    private var snapshot: UsageSnapshot {
        UsageSnapshot(windows: [
            UsageWindow(id: "session", title: "Session", usedPercent: 25, resetsAt: now.addingTimeInterval(100)),
            UsageWindow(id: "weekly", title: "Weekly", usedPercent: 81, resetsAt: now.addingTimeInterval(200))
        ], fetchedAt: now)
    }
    func testMostConstrainedWindowAndExplicitSelection() {
        let auto = PinnedAllowance.make(snapshot: snapshot, now: now)
        XCTAssertEqual(auto.text, "19% left")
        XCTAssertEqual(auto.windowTitle, "Weekly")
        let selected = PinnedAllowance.make(snapshot: snapshot, windowID: "session", now: now)
        XCTAssertEqual(selected.text, "75% left")
    }
    func testMissingDataAndMissingSelectedWindowRemainUnknown() {
        XCTAssertEqual(PinnedAllowance.make(snapshot: nil, now: now).text, "—")
        XCTAssertEqual(PinnedAllowance.make(snapshot: snapshot, windowID: "missing", now: now).text, "—")
    }
    func testErrorsStaleReadingsAndPassedResetsAreMarked() {
        XCTAssertEqual(PinnedAllowance.make(snapshot: snapshot, hasError: true, now: now).text, "~19% left")
        XCTAssertTrue(PinnedAllowance.make(snapshot: snapshot, now: now.addingTimeInterval(601)).isStale)
        XCTAssertTrue(PinnedAllowance.make(snapshot: snapshot, windowID: "session", now: now.addingTimeInterval(101)).isStale)
    }
    func testSmallAvailableQuotaIsNotRoundedToExhausted() {
        let snapshot = UsageSnapshot(windows: [UsageWindow(id: "session", title: "Session", usedPercent: 99.8, resetsAt: nil)], fetchedAt: now)
        XCTAssertEqual(PinnedAllowance.make(snapshot: snapshot, now: now).text, "<1% left")
    }
}
