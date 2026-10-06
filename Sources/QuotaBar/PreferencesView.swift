#if os(macOS)
import SwiftUI

struct PreferencesView: View {
    @State private var history: [SettingsTab]
    @State private var historyIndex = 0

    init(initialTab: SettingsTab = .general) {
        _history = State(initialValue: [initialTab])
    }

    private var activeTab: SettingsTab { history[historyIndex] }
    private var selection: Binding<SettingsTab?> {
        Binding(get: { activeTab }, set: { tab in
            guard let tab, tab != activeTab else { return }
            history = Array(history.prefix(historyIndex + 1)) + [tab]
            historyIndex = history.count - 1
        })
    }

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(SettingsTab.allCases, selection: selection) { tab in
                Label(tab.title, systemImage: tab.symbol).tag(tab)
            }
            .listStyle(.sidebar)
            .softScrollEdges()
            .navigationTitle("Settings")
            .navigationSplitViewColumnWidth(min: 170, ideal: 180, max: 220)
            .toolbar(removing: .sidebarToggle)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("QuotaBar").font(.caption.weight(.semibold))
                    if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                        Text("Version " + version).font(.caption)
                    }
                }.foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(16)
            }
        } detail: {
            Group {
                switch activeTab {
                case .general: GeneralSettings()
                case .menuBar: MenuBarSettings()
                case .alerts: AlertSettings()
                case .updates: UpdateSettings()
                }
            }
            .navigationTitle(activeTab.title)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 680, minHeight: 520)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { historyIndex -= 1 } label: { Image(systemName: "chevron.left") }
                    .disabled(historyIndex == 0).help("Previous settings category")
                    .accessibilityLabel("Previous settings category")
                Button { historyIndex += 1 } label: { Image(systemName: "chevron.right") }
                    .disabled(historyIndex == history.count - 1).help("Next settings category")
                    .accessibilityLabel("Next settings category")
            }
        }
    }
}

extension View {
    @ViewBuilder func softScrollEdges() -> some View {
        if #available(macOS 26.0, *) { scrollEdgeEffectStyle(.soft, for: .all) }
        else { self }
    }
}
#endif
