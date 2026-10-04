#if os(macOS)
import SwiftUI
enum AppStyle {
    static let pagePadding = 24.0
    static let cardPadding = 20.0
    static let sectionSpacing = 24.0
    static let cardRadius = 12.0
    static let rowSpacing = 12.0
    // A live instrument signal; provider identity is carried by labels.
    static let signal = Color(nsColor: .systemBlue)
}
#endif
