#if os(macOS)
import SwiftUI
import QuotaCore

extension Provider {
    var tint: Color { AppStyle.signal }
    var symbol: String { self == .openAI ? "sparkle" : "sun.max" }
}

#endif
