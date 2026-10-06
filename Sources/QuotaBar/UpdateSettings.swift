#if os(macOS)
import SwiftUI
import QuotaCore

struct UpdateSettings: View {
    @EnvironmentObject private var updater: AppUpdater
    var body: some View {
        Form {
            Section("Updates") {
                if updater.configured {
                    Toggle("Automatically check for updates", isOn: Binding(get: { updater.automaticChecks }, set: { updater.setAutomaticChecks($0) }))
                    Toggle("Automatically download updates", isOn: Binding(get: { updater.automaticDownloads }, set: { updater.setAutomaticDownloads($0) }))
                        .disabled(!updater.automaticChecks)
                    Button("Check for Updates…", action: updater.check).disabled(!updater.canCheck)
                    Text("Updates use a signed feed and signed downloads. Installation is handled by Sparkle.").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Automatic updates are available in release builds. You can download development builds from GitHub.")
                        .font(.caption).foregroundStyle(.secondary)
                    Link("Open QuotaBar downloads", destination: URL(string: "https://github.com/ar4ft/QuotaBar/actions")!)
                }
            }
        }.formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 8, for: .scrollContent)
        .softScrollEdges()
    }

}
#endif
