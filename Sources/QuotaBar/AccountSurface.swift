#if os(macOS)
import SwiftUI

struct AccountSurface: ViewModifier {
    var selected = false
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        content.background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: AppStyle.cardRadius))
            .overlay {
                RoundedRectangle(cornerRadius: AppStyle.cardRadius)
                    .strokeBorder(selected ? AppStyle.signal : Color(nsColor: .separatorColor),
                                  lineWidth: contrast == .increased || selected ? 2 : 1)
            }
    }
}
#endif
