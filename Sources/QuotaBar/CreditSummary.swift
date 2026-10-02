#if os(macOS)
import SwiftUI
import QuotaCore

struct CreditSummary: View {
    let snapshot: UsageSnapshot
    let provider: Provider
    var body: some View {
        if provider == .openAI {
            VStack(alignment: .leading, spacing: 4) {
                Label("Credits: " + (snapshot.credits?.display ?? "Not reported"), systemImage: "creditcard")
                Text(snapshot.availableResetCredits.map { "Reset credits available: \($0)" } ?? "Reset credits: Not reported")
            }.font(.caption).foregroundStyle(.secondary)
        }
    }
}
#endif
