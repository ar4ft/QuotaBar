#if os(macOS)
import SwiftUI

struct AccountSurface: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        content.background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: AppStyle.cardRadius))
            .overlay {
                RoundedRectangle(cornerRadius: AppStyle.cardRadius)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: contrast == .increased ? 2 : 1)
            }
    }
}
#endif
