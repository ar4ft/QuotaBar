#if os(macOS)
import SwiftUI
enum AppStyle {
    static let pagePadding = 24.0
    static let cardPadding = 20.0
    static let sectionSpacing = 24.0
    static let cardRadius = 12.0
    static let rowSpacing = 12.0
    // Follow the user's macOS accent; status colors retain their meaning.
    static let signal = Color.accentColor
}
#endif
