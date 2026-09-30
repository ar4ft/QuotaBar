import XCTest
@testable import QuotaCore

final class AccountAvailabilityTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 10_000)
    func account(_ name: String, used: Double, age: Double = 0, resetOffset: Double = 1000) -> Account {
        var account = Account(provider: .openAI, name: name)
        account.snapshot = UsageSnapshot(windows: [UsageWindow(id: "main-primary_window", title: "Session", usedPercent: used,
                                                              resetsAt: now.addingTimeInterval(resetOffset))],
                                         fetchedAt: now.addingTimeInterval(-age))
        return account
    }
    func testFreshAllowanceAndExhaustion() {
        XCTAssertEqual(AccountAvailability.make(account("Ready", used: 20), now: now).status, .ready)
        XCTAssertEqual(AccountAvailability.make(account("Low", used: 90), now: now).status, .limited)
        XCTAssertEqual(AccountAvailability.make(account("Full", used: 100), now: now).status, .exhausted)
    }
    func testUnknownStaleFailedAndExpiredReadingsHaveNoAllowanceScore() {
        let cases = [account("Stale", used: 0, age: 601), account("Reset", used: 0, resetOffset: -1), Account(provider: .claude, name: "Unknown")]
        for account in cases { XCTAssertNil(AccountAvailability.make(account, now: now).remainingPercent) }
        XCTAssertNil(AccountAvailability.make(account("Failure", used: 0), hasError: true, now: now).remainingPercent)
        XCTAssertEqual(AccountAvailability.make(cases[1], now: now).status, .awaitingReset)
    }
    func testCodeReviewExhaustionDoesNotBlockMainCodexAllowance() {
        var account = account("Work", used: 30)
        account.snapshot?.windows.append(UsageWindow(id: "review-primary_window", title: "Code review", usedPercent: 100, resetsAt: now.addingTimeInterval(300)))
        XCTAssertEqual(AccountAvailability.make(account, now: now).remainingPercent, 70)
        XCTAssertEqual(AccountAvailability.make(account, now: now).status, .ready)
    }
    func testModelOnlyReadingsCannotClaimEntireAccountAvailable() {
        var account = Account(provider: .claude, name: "Models only")
        account.snapshot = UsageSnapshot(windows: [UsageWindow(id: "seven_day_opus", title: "Opus", usedPercent: 0, resetsAt: nil)], fetchedAt: now)
        XCTAssertEqual(AccountAvailability.make(account, now: now).status, .unknown)
    }
    func testAllowanceSortPutsFreshUsableAccountsBeforeUnknownData() {
        let accounts = [account("Stale", used: 0, age: 601), account("Limited", used: 90), account("Ready", used: 10), account("Exhausted", used: 100)]
        XCTAssertEqual(AccountSort.allowance.sort(accounts, now: now).map(\.name), ["Ready", "Limited", "Exhausted", "Stale"])
    }
    func testFailureNeverRanksAsUnusedAllowance() {
        let good = account("Good", used: 90), failed = account("Failed", used: 0)
        XCTAssertEqual(AccountSort.allowance.sort([failed, good], errorIDs: [failed.id], now: now).first?.id, good.id)
    }
    func testResetSortAndStableNameTiebreaker() {
        let accounts = [account("Later", used: 10, resetOffset: 500), account("Soon", used: 10, resetOffset: 100)]
        XCTAssertEqual(AccountSort.reset.sort(accounts, now: now).first?.name, "Soon")
        XCTAssertEqual(AccountSort.allowance.sort(accounts, now: now).first?.name, "Later")
    }
}

final class ResetRefreshPolicyTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 10_000)
    var expired: UsageSnapshot { UsageSnapshot(windows: [UsageWindow(id: "session", title: "Session", usedPercent: 100, resetsAt: now)], fetchedAt: now.addingTimeInterval(-60)) }
    func testRefreshBecomesDueExactlyAtReset() {
        XCTAssertFalse(ResetRefreshPolicy.isDue(expired, attempt: nil, now: now.addingTimeInterval(-1)))
        XCTAssertTrue(ResetRefreshPolicy.isDue(expired, attempt: nil, now: now))
    }
    func testRetryBackoffAndNewCycle() {
        let first = ResetRefreshPolicy.record(boundary: now, previous: nil, now: now)
        XCTAssertEqual(first.retryAt, now.addingTimeInterval(30))
        XCTAssertFalse(ResetRefreshPolicy.isDue(expired, attempt: first, now: now.addingTimeInterval(29)))
        XCTAssertTrue(ResetRefreshPolicy.isDue(expired, attempt: first, now: now.addingTimeInterval(30)))
        let second = ResetRefreshPolicy.record(boundary: now, previous: first, now: now)
        XCTAssertEqual(second.retryAt, now.addingTimeInterval(60))
        XCTAssertEqual(ResetRefreshPolicy.record(boundary: now.addingTimeInterval(100), previous: second, now: now).count, 1)
    }
    func testProviderCooldownOverridesResetRefresh() {
        XCTAssertFalse(ResetRefreshPolicy.isDue(expired, attempt: nil, cooldown: now.addingTimeInterval(3600), now: now))
    }
    func testMissingResetDoesNotCauseRequests() {
        let missing = UsageSnapshot(windows: [UsageWindow(id: "session", title: "Session", usedPercent: 100, resetsAt: nil)], fetchedAt: now)
        XCTAssertFalse(ResetRefreshPolicy.isDue(missing, attempt: nil, now: now))
        XCTAssertFalse(ResetRefreshPolicy.isDue(nil, attempt: nil, now: now))
    }
    func testRepeatedUnconfirmedResetsHaveBoundedBackoff() {
        var attempt: ResetRefreshAttempt?
        for _ in 0..<20 { attempt = ResetRefreshPolicy.record(boundary: now, previous: attempt, now: now) }
        XCTAssertEqual(attempt?.retryAt, now.addingTimeInterval(900))
    }
    func testPinnedAllowanceWithExpiredResetIsUnknown() {
        XCTAssertEqual(PinnedAllowance.make(snapshot: expired, now: now).text, "—")
    }
}

final class UsageHistoryTests: XCTestCase {
    func snapshot(_ time: Double, used: Double = 20, reset: Double? = nil) -> UsageSnapshot {
        UsageSnapshot(windows: [UsageWindow(id: "session", title: "Session", usedPercent: used,
                                           resetsAt: reset.map { Date(timeIntervalSince1970: $0) })], fetchedAt: Date(timeIntervalSince1970: time))
    }
    func testFiveMinuteBucketsContinueAcrossFrequentRefreshes() {
        var samples: [UsageSnapshot] = []
        for time in stride(from: 3600.0, through: 3960.0, by: 60) { samples = UsageHistory.record(snapshot(time), in: samples) }
        XCTAssertEqual(samples.count, 2)
        XCTAssertEqual(samples.map { $0.fetchedAt.timeIntervalSince1970 }, [3840, 3960])
    }
    func testResetInsideBucketIsPreserved() {
        let before = snapshot(1000, used: 100, reset: 1005)
        let after = snapshot(1010, used: 2, reset: 2000)
        XCTAssertEqual(UsageHistory.record(after, in: [before]).count, 2)
    }
    func testOutOfOrderSamplesCannotReplaceLatestReading() {
        let samples = [snapshot(1000)]
        XCTAssertEqual(UsageHistory.record(snapshot(900), in: samples), samples)
    }
    func testRetentionAndHardLimit() {
        let recent = snapshot(31 * 86400)
        XCTAssertEqual(UsageHistory.record(recent, in: [snapshot(0)]).count, 1)
        let records = [snapshot(1000), snapshot(2000), snapshot(3000)]
        XCTAssertEqual(UsageHistory.record(snapshot(4000), in: records, maxSamples: 2).map { $0.fetchedAt.timeIntervalSince1970 }, [3000, 4000])
    }
    func testChartSeparatesResetsAndMissingObservationGaps() {
        let points = HistoryPoint.make([snapshot(1000, used: 100, reset: 1005), snapshot(1010, used: 0, reset: 2000), snapshot(8000, reset: 9000)], windowID: "session")
        XCTAssertEqual(points.map(\.segment), [0, 1, 2])
    }
    func testExpiredProviderWindowsAreNotPlottedAsCurrentQuota() {
        let samples = [snapshot(1000, used: 100, reset: 1005), snapshot(1010, used: 100, reset: 1005)]
        XCTAssertEqual(HistoryPoint.make(samples, windowID: "session").count, 1)
        XCTAssertTrue(UsageHistory.csv(samples).contains("awaiting_reset"))
    }
    func testCSVPreservesQuotedLabelsAndMakesFormulaCellsLiteral() {
        var sample = snapshot(1000)
        sample.windows[0].title = "=SUM(1,2)"
        sample.plan = "A \"quoted\", plan"
        let csv = UsageHistory.csv([sample])
        XCTAssertTrue(csv.hasPrefix("observed_at,window_id,window_title,used_percent,remaining_percent,resets_at,plan,reading_status\r\n"))
        XCTAssertTrue(csv.contains("\"'=SUM(1,2)\""))
        XCTAssertTrue(csv.contains("\"A \"\"quoted\"\", plan\""))
    }
    func testHistoryRepositoryPersistsPrivatelyAndRemovesOneAccount() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = UsageHistoryRepository(directory: directory)
        let id = UUID(), other = UUID()
        _ = try await repository.record(snapshot(1000), for: id)
        _ = try await repository.record(snapshot(1000), for: other)
        let reloaded = try await UsageHistoryRepository(directory: directory).load(id)
        XCTAssertEqual(reloaded.count, 1)
        let permissions = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent(id.uuidString + ".json").path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
        try await repository.remove(id)
        let removed = try await repository.load(id), retained = try await repository.load(other)
        XCTAssertTrue(removed.isEmpty)
        XCTAssertEqual(retained.count, 1)
    }
    func testCorruptHistoryIsPreservedInsteadOfOverwritten() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = UsageHistoryRepository(directory: directory), id = UUID()
        _ = try await repository.record(snapshot(1000), for: id)
        let file = directory.appendingPathComponent(id.uuidString + ".json")
        let invalid = Data("{invalid".utf8); try invalid.write(to: file)
        do { _ = try await repository.record(snapshot(2000), for: id); XCTFail("Should preserve corrupt history") }
        catch { XCTAssertEqual(try Data(contentsOf: file), invalid) }
    }
}
