#if os(macOS)
import SwiftUI
import QuotaCore

struct AccountStatusLabel: View {
    let status: AvailabilityStatus
    var compact = false
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
        Label(status.title, systemImage: symbol).font(compact ? .caption : .callout)
            .foregroundStyle(color)
            .accessibilityLabel("Allowance status: " + status.title)
    }
    private var color: Color {
        switch status {
        case .ready: .green
        case .limited, .exhausted, .error: .orange
        default: .secondary
        }
    }
}

#endif
