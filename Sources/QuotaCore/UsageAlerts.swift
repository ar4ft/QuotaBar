import Foundation

public struct AlertPreferences: Codable, Equatable, Sendable {
    public var enabled = true
    public var warnAt80 = true
    public var warnAt95 = true
    public var notifyWhenAvailable = true
    public var customThresholds: [Int]?
    public var lowCreditThreshold: Double?
    public init() {}
    public var thresholds: [Int] { Array(Set((customThresholds ?? ((warnAt80 ? [80] : []) + (warnAt95 ? [95] : []))).filter { (1...99).contains($0) })).sorted() }
}

public struct CreditAlertState: Codable, Equatable, Sendable {
    public var observedAt: Date
    public var threshold: Double
    public var notified: Bool
}

public struct WindowAlertState: Codable, Equatable, Sendable {
    public var usedPercent: Double
    public var resetsAt: Date?
    public var observedAt: Date
    public var notifiedThresholds: Set<Int>
    public var notifiedRecovery: Bool
}

public struct UsageAlert: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case threshold(Int), availableAgain, lowCredits(Double) }
    public var windowID: String
    public var windowTitle: String
    public var usedPercent: Double
    public var kind: Kind
}

public struct AlertEvaluation: Sendable {
    public var state: [String: WindowAlertState]
    public var alerts: [UsageAlert]
    public var creditState: CreditAlertState?
}

public enum UsageAlerts {
    // Evaluate only successful provider readings; a clock reaching a reset is never evidence of refill.
    // Threshold receipts are persisted per window/cycle to avoid repeating alerts after relaunch.
    public static func evaluate(snapshot: UsageSnapshot, state: [String: WindowAlertState],
                                preferences: AlertPreferences, creditState: CreditAlertState? = nil) -> AlertEvaluation {
        var state = state
        var alerts: [UsageAlert] = []
        for window in snapshot.windows {
            let previous = state[window.id]
            if let previous, snapshot.fetchedAt <= previous.observedAt { continue }
            let rolledOver: Bool
            if let oldReset = previous?.resetsAt, let newReset = window.resetsAt {
                rolledOver = oldReset <= snapshot.fetchedAt && newReset > snapshot.fetchedAt && newReset > oldReset
            } else { rolledOver = false }
            // A fresh drop from exhaustion confirms available quota even when a reset timestamp is absent.
            let recovered = previous.map {
                $0.usedPercent >= 100 && window.usedPercent < 100 &&
                ($0.resetsAt == nil || $0.resetsAt! <= snapshot.fetchedAt)
            } ?? false
            var receipts = rolledOver ? Set<Int>() : previous?.notifiedThresholds ?? []
            var notifiedRecovery = rolledOver ? false : previous?.notifiedRecovery ?? false
            if preferences.enabled {
                let available = recovered || (rolledOver && previous!.usedPercent >= 80 && window.usedPercent < previous!.usedPercent && window.usedPercent < 100)
                if preferences.notifyWhenAvailable && available && !notifiedRecovery {
                    notifiedRecovery = true
                    alerts.append(UsageAlert(windowID: window.id, windowTitle: window.title,
                                             usedPercent: window.usedPercent, kind: .availableAgain))
                }
                let reached = preferences.thresholds.filter { window.usedPercent >= Double($0) && !receipts.contains($0) }
                // If one refresh passes both thresholds, send the higher one rather than two banners.
                if let highest = reached.max() {
                    alerts.append(UsageAlert(windowID: window.id, windowTitle: window.title,
                                             usedPercent: window.usedPercent, kind: .threshold(highest)))
                    receipts.formUnion(reached)
                }
            }
            state[window.id] = WindowAlertState(usedPercent: window.usedPercent, resetsAt: window.resetsAt,
                                              observedAt: snapshot.fetchedAt, notifiedThresholds: receipts, notifiedRecovery: notifiedRecovery)
        }
        var nextCreditState = creditState
        if snapshot.credits?.unlimited == true, let old = creditState, snapshot.fetchedAt > old.observedAt {
            nextCreditState = CreditAlertState(observedAt: snapshot.fetchedAt, threshold: old.threshold, notified: false)
        }
        if let threshold = preferences.lowCreditThreshold, threshold.isFinite, threshold >= 0,
           let credits = snapshot.credits, !credits.unlimited, let balance = credits.balance,
           balance.isFinite, balance >= 0, snapshot.fetchedAt > (creditState?.observedAt ?? .distantPast) {
            var notified = creditState?.threshold == threshold ? creditState?.notified ?? false : false
            if balance > threshold { notified = false }
            if preferences.enabled && balance <= threshold && !notified {
                notified = true
                alerts.append(UsageAlert(windowID: "credits", windowTitle: "Credits", usedPercent: 0, kind: .lowCredits(balance)))
            }
            nextCreditState = CreditAlertState(observedAt: snapshot.fetchedAt, threshold: threshold, notified: notified)
        }
        return AlertEvaluation(state: state, alerts: alerts, creditState: nextCreditState)
    }
}
