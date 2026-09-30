import Foundation

public struct PinnedAllowance: Equatable, Sendable {
    public var text: String
    public var windowTitle: String?
    public var isStale: Bool
    public static func make(snapshot: UsageSnapshot?, windowID: String = "", hasError: Bool = false,
                            now: Date = Date()) -> PinnedAllowance {
        guard let snapshot else { return PinnedAllowance(text: "—", windowTitle: nil, isStale: true) }
        let window = windowID.isEmpty
            ? snapshot.windows.max(by: { $0.usedPercent < $1.usedPercent })
            : snapshot.windows.first(where: { $0.id == windowID })
        guard let window else { return PinnedAllowance(text: "—", windowTitle: nil, isStale: true) }
        let isStale = hasError || now.timeIntervalSince(snapshot.fetchedAt) > 600 ||
            (window.resetsAt.map { $0 <= now } ?? false)
        let percent = window.remainingPercent > 0 && window.remainingPercent < 1
            ? "<1" : String(Int(window.remainingPercent.rounded()))
        return PinnedAllowance(text: "\(isStale ? "~" : "")\(percent)% left", windowTitle: window.title, isStale: isStale)
    }
}
