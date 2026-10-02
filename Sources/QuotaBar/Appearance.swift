#if os(macOS)
import SwiftUI
import QuotaCore

extension Provider {
    var tint: Color { self == .openAI ? Color(nsColor: .systemGreen) : Color(nsColor: .systemOrange) }
    var symbol: String { self == .openAI ? "sparkle" : "sun.max" }
}

#endif
