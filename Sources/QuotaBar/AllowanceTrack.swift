#if os(macOS)
import SwiftUI

/// The three notches calibrate a single provider window, not a pooled balance.
struct AllowanceTrack: View {
    let percent: Double
    let tint: Color
    var body: some View {
        GeometryReader { geometry in
            let fraction = percent.isFinite ? min(1, max(0, percent / 100)) : 0
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(Color(nsColor: .separatorColor))
                RoundedRectangle(cornerRadius: 2).fill(tint)
                    .frame(width: geometry.size.width * fraction)
                ForEach(1..<4) { quarter in
                    Rectangle().fill(Color(nsColor: .controlBackgroundColor))
                        .frame(width: 2).offset(x: geometry.size.width * Double(quarter) / 4 - 1)
                }
            }
        }.frame(height: 5)
    }
}
#endif
