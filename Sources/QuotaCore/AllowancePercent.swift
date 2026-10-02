import Foundation

public enum AllowancePercent {
    public static func display(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        if value > 0 && value < 1 { return "<1%" }
        if value > 99 && value < 100 { return ">99%" }
        return min(100, max(0, value)).formatted(.number.precision(.fractionLength(0))) + "%"
    }
    public static func spoken(_ value: Double) -> String {
        guard value.isFinite else { return "Unknown percentage" }
        if value > 0 && value < 1 { return "Less than 1 percent" }
        if value > 99 && value < 100 { return "More than 99 percent" }
        return min(100, max(0, value)).formatted(.number.precision(.fractionLength(0))) + " percent"
    }
}
