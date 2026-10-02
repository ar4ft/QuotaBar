#if os(macOS)
import SwiftUI

struct PreferencesView: View {
    @State private var selection: SettingsTab = .general
    var body: some View {
        Group {
            if #available(macOS 15, *) {
                TabView(selection: $selection) {
                    Tab("General", systemImage: "gearshape", value: .general) { GeneralSettings() }
                    Tab("Menu Bar", systemImage: "menubar.rectangle", value: .menuBar) { MenuBarSettings() }
                    Tab("Alerts", systemImage: "bell", value: .alerts) { AlertSettings() }
                    Tab("Updates", systemImage: "arrow.triangle.2.circlepath", value: .updates) { UpdateSettings() }
                }
            } else {
                TabView(selection: $selection) {
                    GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }.tag(SettingsTab.general)
                    MenuBarSettings().tabItem { Label("Menu Bar", systemImage: "menubar.rectangle") }.tag(SettingsTab.menuBar)
                    AlertSettings().tabItem { Label("Alerts", systemImage: "bell") }.tag(SettingsTab.alerts)
                    UpdateSettings().tabItem { Label("Updates", systemImage: "arrow.triangle.2.circlepath") }.tag(SettingsTab.updates)
                }
            }
        }.padding(AppStyle.rowSpacing)
            .frame(minWidth: 560, idealWidth: 640, minHeight: 500, idealHeight: 580)
    }
}
#endif
