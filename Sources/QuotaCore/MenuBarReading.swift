import Foundation

public enum MenuBarDisplay: String, CaseIterable, Identifiable, Sendable {
    case allowance, reset, credits, iconOnly
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .allowance: return "Remaining percentage"
        case .reset: return "Reset countdown"
        case .credits: return "Credit balance"
        case .iconOnly: return "Icon only"
        }
    }
}

public struct MenuBarReading: Equatable, Sendable {
    public var text: String?
    public var detail: String
    public static func make(snapshot: UsageSnapshot?, mode: MenuBarDisplay, windowID: String = "",
                            hasError: Bool = false, presentationMode: Bool = false, now: Date = Date()) -> Self {
        if presentationMode { return Self(text: nil, detail: "Presentation mode · details hidden") }
        if mode == .iconOnly { return Self(text: nil, detail: "Subscription usage") }
        guard let snapshot else { return Self(text: "—", detail: "No reading") }
        let stale = hasError || now.timeIntervalSince(snapshot.fetchedAt) > 600
        let prefix = stale ? "~" : ""
        if mode == .credits {
            guard let credits = snapshot.credits else { return Self(text: "— cr", detail: "Credit balance not reported") }
            let amount: String
            if credits.unlimited { amount = "∞" }
            else if let balance = credits.balance, balance.isFinite, balance >= 0 {
                amount = balance.formatted(.number.precision(.fractionLength(0...2)))
            } else { return Self(text: "— cr", detail: "Credit amount not reported") }
            return Self(text: "\(prefix)\(amount) cr", detail: stale ? "Credit balance · last reading; refresh to confirm" : "Credit balance")
        }
        let window = windowID.isEmpty ? snapshot.windows.max(by: { $0.usedPercent < $1.usedPercent })
            : snapshot.windows.first(where: { $0.id == windowID })
        guard let window else { return Self(text: "—", detail: "Selected allowance window unavailable") }
        if mode == .allowance {
            let value = PinnedAllowance.make(snapshot: snapshot, windowID: windowID, hasError: hasError, now: now)
            return Self(text: value.text, detail: window.title + (value.isStale ? " · last reading; refresh to confirm" : ""))
        }
        guard let reset = window.resetsAt else { return Self(text: "—", detail: "Reset time not reported") }
        let seconds = reset.timeIntervalSince(now)
        guard seconds > 0 else { return Self(text: "Due", detail: "Reset reached · refresh to confirm") }
        let minutes = max(1, Int(ceil(seconds / 60)))
        let value = seconds < 60 ? "<1m" : minutes >= 1440 ? "\(minutes / 1440)d \((minutes % 1440) / 60)h"
            : minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
        return Self(text: prefix + value, detail: window.title + " · " + reset.formatted(date: .abbreviated, time: .shortened) + (stale ? " · last reading" : ""))
    }
}

public enum ShortcutModifiers: String, CaseIterable, Identifiable, Sendable {
    case controlOption, commandShift, controlOptionCommand
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .controlOption: return "Control + Option"
        case .commandShift: return "Command + Shift"
        case .controlOptionCommand: return "Control + Option + Command"
        }
    }
}
