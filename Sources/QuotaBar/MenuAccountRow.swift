#if os(macOS)
import SwiftUI
import QuotaCore

struct MenuAccountRow: View {
    @EnvironmentObject private var store: AccountStore
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var hovered = false
    let account: Account
    let useAccount: () -> Void
    let reconnect: () -> Void
    private var selected: Bool { store.activeAccountID(account.provider) == account.id.uuidString }
    private var pinned: Bool { store.pinnedAccountID == account.id.uuidString }
    private var availability: AccountAvailability { store.availability(account) }
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: account.provider.symbol).font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary).frame(width: 28, height: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(store.presentationMode ? account.provider.title + " account" : account.name)
                        .font(.callout.weight(.semibold)).lineLimit(1)
                    if !store.presentationMode && selected {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(AppStyle.signal)
                            .help("Selected for CLI").accessibilityLabel("Selected for CLI")
                    }
                    if !store.presentationMode && pinned {
                        Image(systemName: "pin.fill").foregroundStyle(.secondary)
                            .help("Pinned in menu bar").accessibilityLabel("Pinned in menu bar")
                    }
                }
                if store.presentationMode {
                    Text("Details hidden").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(account.detail ?? account.provider.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    AccountStatusLabel(status: availability.status, compact: true)
                        .help(store.errors[account.id] ?? availability.status.title)
                }
            }
            Spacer(minLength: 0)
            if !store.presentationMode {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(availability.remainingPercent.map(AllowancePercent.display) ?? "—")
                        .font(.system(size: 18, weight: .semibold)).monospacedDigit()
                    Text("left").font(.caption2).foregroundStyle(.secondary)
                }.frame(minWidth: 42, alignment: .trailing)
                    .help("Lowest remaining allowance across the main usage windows; a dash means there is no confirmed reading.")
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Main allowance remaining")
                    .accessibilityValue(availability.remainingPercent.map(AllowancePercent.spoken) ?? "No confirmed reading")
            }
            Button(action: useAccount) {
                Image(systemName: "arrow.left.arrow.right").frame(width: 24, height: 28)
            }.buttonStyle(.borderless).disabled(store.presentationMode || store.refreshing.contains(account.id))
                .help(selected ? "Reapply this account in the CLI" : "Use this account in the CLI")
                .accessibilityLabel(store.presentationMode ? "Use account" : "Use \(account.name) in the CLI")
            Menu {
                Button(pinned ? "Unpin from Menu Bar" : "Pin in Menu Bar") {
                    store.pinAccount(pinned ? "" : account.id.uuidString)
                }.disabled(store.presentationMode)
                Button("Refresh") { Task { await store.refresh(account.id) } }.disabled(store.refreshing.contains(account.id))
                Button("Reconnect…", action: reconnect).disabled(store.presentationMode)
            } label: { Image(systemName: "ellipsis").frame(width: 18, height: 28) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel(store.presentationMode ? "Account actions" : "Actions for " + account.name)
        }.padding(.horizontal, 10).padding(.vertical, 10)
            .background(hovered ? Color(nsColor: .controlBackgroundColor) : selected && !store.presentationMode ? AppStyle.signal.opacity(0.06) : .clear,
                        in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                if contrast == .increased && selected && !store.presentationMode {
                    RoundedRectangle(cornerRadius: 8).strokeBorder(AppStyle.signal, lineWidth: 1)
                }
            }
            .onHover { hovered = $0 }
            .accessibilityElement(children: .contain)
    }
}
#endif
