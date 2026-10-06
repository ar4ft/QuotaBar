import XCTest
@testable import QuotaCore

final class MenuBarReadingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 100_000)
    private func snapshot(reset: Date? = nil, fetchedAt: Date? = nil, credits: CreditBalance? = nil) -> UsageSnapshot {
        UsageSnapshot(windows: [UsageWindow(id: "main", title: "Session", usedPercent: 99.5, resetsAt: reset)],
                      fetchedAt: fetchedAt ?? now, credits: credits)
    }
    func testPercentageKeepsSmallRemainingAllowanceAndUnknownWindow() {
        XCTAssertEqual(MenuBarReading.make(snapshot: snapshot(), mode: .allowance, now: now).text, "<1% left")
        XCTAssertEqual(MenuBarReading.make(snapshot: snapshot(), mode: .allowance, windowID: "missing", now: now).text, "—")
    }
    func testCountdownAndDueNeverClaimRefilledQuota() {
        XCTAssertEqual(MenuBarReading.make(snapshot: snapshot(reset: now.addingTimeInterval(3660)), mode: .reset, now: now).text, "1h 1m")
        XCTAssertEqual(MenuBarReading.make(snapshot: snapshot(reset: now.addingTimeInterval(20)), mode: .reset, now: now).text, "<1m")
        let due = MenuBarReading.make(snapshot: snapshot(reset: now), mode: .reset, now: now)
        XCTAssertEqual(due.text, "Due")
        XCTAssertTrue(due.detail.contains("confirm"))
        XCTAssertEqual(MenuBarReading.make(snapshot: snapshot(), mode: .reset, now: now).text, "—")
    }
    func testCreditsNeverInventMissingBalancesAndMarkStaleReadings() {
        XCTAssertEqual(MenuBarReading.make(snapshot: snapshot(), mode: .credits, now: now).text, "— cr")
        XCTAssertEqual(MenuBarReading.make(snapshot: snapshot(credits: CreditBalance(hasCredits: true)), mode: .credits, now: now).text, "— cr")
        XCTAssertEqual(MenuBarReading.make(snapshot: snapshot(credits: CreditBalance(unlimited: true)), mode: .credits, now: now).text, "∞ cr")
        let stale = snapshot(fetchedAt: now.addingTimeInterval(-601), credits: CreditBalance(balance: 20))
        XCTAssertEqual(MenuBarReading.make(snapshot: stale, mode: .credits, now: now).text, "~20 cr")
    }
    func testPrivacyOverridesEveryModeAndHidesDetails() {
        for mode in MenuBarDisplay.allCases {
            let reading = MenuBarReading.make(snapshot: snapshot(), mode: mode, presentationMode: true, now: now)
            XCTAssertNil(reading.text)
            XCTAssertEqual(reading.detail, "Presentation mode · details hidden")
        }
        XCTAssertNil(MenuBarReading.make(snapshot: snapshot(), mode: .iconOnly, now: now).text)
    }
    func testCountdownMarksProviderErrorsAsLastReading() {
        let reading = MenuBarReading.make(snapshot: snapshot(reset: now.addingTimeInterval(3600)), mode: .reset, hasError: true, now: now)
        XCTAssertEqual(reading.text, "~1h 0m")
        XCTAssertTrue(reading.detail.contains("last reading"))
    }
}

final class ForecastTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 100_000)
    private func samples(_ values: [Double], spacing: Double = 900, resetOffset: Double = 3600) -> [UsageSnapshot] {
        values.enumerated().map { index, value in
            UsageSnapshot(windows: [UsageWindow(id: "main", title: "Session", usedPercent: value,
                resetsAt: now.addingTimeInterval(resetOffset))], fetchedAt: now.addingTimeInterval(Double(index - values.count + 1) * spacing))
        }
    }
    func testLinearConsumptionEstimateAndResetComparison() throws {
        let forecast = try XCTUnwrap(UsageForecast.estimate(samples([50, 60, 70]), windowID: "main", now: now))
        XCTAssertEqual(forecast.percentPerHour, 40, accuracy: 0.001)
        XCTAssertEqual(forecast.estimatedLimitAt.timeIntervalSince(now), 2700, accuracy: 0.001)
        XCTAssertFalse(forecast.resetArrivesFirst)
        let resetFirst = try XCTUnwrap(UsageForecast.estimate(samples([10, 11, 12]), windowID: "main", now: now))
        XCTAssertTrue(resetFirst.resetArrivesFirst)
    }
    func testSparseFlatAndShortHistoryHaveNoForecast() {
        for series in [samples([10, 20]), samples([20, 20, 20]), samples([10, 20, 30], spacing: 300)] {
            XCTAssertNil(UsageForecast.estimate(series, windowID: "main", now: now))
        }
    }
    func testStaleMissingAndExhaustedLatestReadingHaveNoForecast() {
        XCTAssertNil(UsageForecast.estimate(samples([10, 20, 30]), windowID: "main", now: now.addingTimeInterval(601)))
        XCTAssertNil(UsageForecast.estimate(samples([10, 20, 30]), windowID: "absent", now: now))
        XCTAssertNil(UsageForecast.estimate(samples([80, 90, 100]), windowID: "main", now: now))
    }
    func testUsageDropGapAndChangedCycleBreakForecast() {
        XCTAssertNil(UsageForecast.estimate(samples([60, 70, 5, 10]), windowID: "main", now: now))
        XCTAssertNil(UsageForecast.estimate(samples([10, 20, 30], spacing: 3601), windowID: "main", now: now))
        var changed = samples([10, 20, 30])
        changed[0].windows[0].resetsAt = now.addingTimeInterval(2000)
        XCTAssertNil(UsageForecast.estimate(changed, windowID: "main", now: now))
    }
    func testUnknownOrElapsedResetHasNoForecast() {
        var unknown = samples([10, 20, 30])
        for i in unknown.indices { unknown[i].windows[0].resetsAt = nil }
        XCTAssertNil(UsageForecast.estimate(unknown, windowID: "main", now: now))
        XCTAssertNil(UsageForecast.estimate(samples([10, 20, 30], resetOffset: 0), windowID: "main", now: now))
    }
    func testDuplicateAndFutureSamplesCannotCreateEvidence() {
        let source = samples([10, 20, 30])
        let repeated = [source.last!, source.last!, source.last!]
        XCTAssertNil(UsageForecast.estimate(repeated, windowID: "main", now: now))
        XCTAssertNil(UsageForecast.estimate(source, windowID: "main", now: now.addingTimeInterval(-1800)))
    }
}

final class ConnectionHealthTests: XCTestCase {
    func testExpiredAndDeniedNeedReconnectButRateLimitDoesNot() {
        XCTAssertEqual(ConnectionIssue.classify(QuotaError.unauthorized), .expired)
        XCTAssertEqual(ConnectionIssue.classify(QuotaError.forbidden), .denied)
        XCTAssertTrue(ConnectionHealth.make(snapshot: nil, issue: .expired).needsReconnect)
        XCTAssertFalse(ConnectionHealth.make(snapshot: nil, issue: .rateLimited).needsReconnect)
    }
    func testKeychainPermissionFailureKeepsLastReadingAndDoesNotRequireReconnect() {
        let reading = UsageSnapshot(windows: [], fetchedAt: Date(timeIntervalSince1970: 100))
        let health = ConnectionHealth.make(snapshot: reading, issue: .keychainAccess)
        XCTAssertTrue(health.needsAttention)
        XCTAssertFalse(health.needsReconnect)
        XCTAssertEqual(health.lastSuccess, reading.fetchedAt)
    }
    func testExhaustedAllowanceIsStillAHealthyConnection() {
        let now = Date(timeIntervalSince1970: 100)
        let snapshot = UsageSnapshot(windows: [UsageWindow(id: "main", title: "Session", usedPercent: 100, resetsAt: nil)], fetchedAt: now)
        XCTAssertFalse(ConnectionHealth.make(snapshot: snapshot, issue: nil, now: now).needsAttention)
        XCTAssertTrue(ConnectionHealth.make(snapshot: snapshot, issue: nil, now: now.addingTimeInterval(601)).needsAttention)
    }
    func testFailedRefreshKeepsLastSuccessfulTimestamp() {
        let snapshot = UsageSnapshot(windows: [], fetchedAt: Date(timeIntervalSince1970: 100))
        let health = ConnectionHealth.make(snapshot: snapshot, issue: .failed)
        XCTAssertEqual(health.lastSuccess, snapshot.fetchedAt)
        XCTAssertTrue(health.needsAttention)
        XCTAssertTrue(ConnectionHealth.make(snapshot: nil, issue: nil).needsAttention)
    }
}
