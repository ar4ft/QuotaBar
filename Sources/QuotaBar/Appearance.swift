#if os(macOS)
import SwiftUI
import QuotaCore

extension Provider {
    var tint: Color { self == .openAI ? Color(nsColor: .systemGreen) : Color(nsColor: .systemOrange) }
    var symbol: String { self == .openAI ? "sparkle" : "sun.max" }
}

struct AccountStatusLabel: View {
    let status: AvailabilityStatus
    private var symbol: String {
        switch status {
        case .ready: return "checkmark.circle"
        case .limited: return "exclamationmark.circle"
        case .exhausted: return "pause.circle"
        case .awaitingReset: return "clock.arrow.circlepath"
        case .stale: return "clock.badge.exclamationmark"
        case .error: return "exclamationmark.triangle"
        case .unknown: return "questionmark.circle"
        }
    }
    var body: some View {
        Label(status.title, systemImage: symbol).font(.callout)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Allowance status: " + status.title)
    }
}

struct AccountSurface: ViewModifier {
    @Environment(\.accessibilityContrast) private var contrast
    func body(content: Content) -> some View {
        content.background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: contrast == .increased ? 2 : 1))
    }
}
#endif
