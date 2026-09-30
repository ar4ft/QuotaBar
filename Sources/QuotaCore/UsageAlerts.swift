import Foundation

public struct AlertPreferences: Codable, Equatable, Sendable {
    public var enabled = true
    public var warnAt80 = true
    public var warnAt95 = true
    public var notifyWhenAvailable = true
    public init() {}
    public var thresholds: [Int] { (warnAt80 ? [80] : []) + (warnAt95 ? [95] : []) }
}

public struct WindowAlertState: Codable, Equatable, Sendable {
    public var usedPercent: Double
    public var resetsAt: Date?
    public var observedAt: Date
    public var notifiedThresholds: Set<Int>
    public var notifiedRecovery: Bool
}

public struct UsageAlert: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case threshold(Int), availableAgain }
    public var windowID: String
    public var windowTitle: String
    public var usedPercent: Double
    public var kind: Kind
}

public struct AlertEvaluation: Sendable {
    public var state: [String: WindowAlertState]
    public var alerts: [UsageAlert]
}

public enum UsageAlerts {
    // Evaluate only successful provider readings; a clock reaching a reset is never evidence of refill.
    // Threshold receipts are persisted per window/cycle to avoid repeating alerts after relaunch.
    public static func evaluate(snapshot: UsageSnapshot, state: [String: WindowAlertState],
                                preferences: AlertPreferences) -> AlertEvaluation {
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
        return AlertEvaluation(state: state, alerts: alerts)
    }
}
