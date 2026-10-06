#if os(macOS)
import SwiftUI

struct AccountSurface: ViewModifier {
    var selected = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var hovered = false
    func body(content: Content) -> some View {
        content.background(Color(nsColor: scheme == .dark ? .controlColor : .controlBackgroundColor),
                           in: RoundedRectangle(cornerRadius: AppStyle.cardRadius))
            .overlay {
                RoundedRectangle(cornerRadius: AppStyle.cardRadius)
                    .strokeBorder(selected ? AppStyle.signal.opacity(contrast == .increased ? 1 : 0.7) : Color(nsColor: .separatorColor).opacity(contrast == .increased ? 1 : 0.5),
                                  lineWidth: contrast == .increased ? 2 : selected ? 1 : 0.5)
            }
            .shadow(color: .black.opacity(contrast == .increased ? 0 : scheme == .dark ? 0.16 : 0.04),
                    radius: hovered ? 6 : 3, x: 0, y: 2)
            .onHover { hovered = $0 }
    }
}
#endif
