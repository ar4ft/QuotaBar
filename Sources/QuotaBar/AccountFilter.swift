#if os(macOS)
import SwiftUI

enum AccountFilter: String, CaseIterable, Identifiable {
    case all, openAI, claude
    var id: String { rawValue }
    var title: String { self == .all ? "All accounts" : self == .openAI ? "OpenAI" : "Claude" }
    var symbol: String { self == .all ? "square.grid.2x2" : self == .openAI ? "sparkle" : "sun.max" }
}
#endif
