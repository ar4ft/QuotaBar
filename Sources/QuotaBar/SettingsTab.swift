#if os(macOS)
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, menuBar, alerts, updates
    var id: Self { self }
    var title: String { switch self { case .general: "General"; case .menuBar: "Menu Bar"; case .alerts: "Alerts"; case .updates: "Updates" } }
    var symbol: String { switch self { case .general: "gearshape"; case .menuBar: "menubar.rectangle"; case .alerts: "bell"; case .updates: "arrow.triangle.2.circlepath" } }
}

#endif
