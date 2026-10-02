#if os(macOS)
import SwiftUI
import Observation
import AppKit
import Carbon
import QuotaCore

@MainActor
@Observable
final class GlobalShortcut {
    private(set) var error: String?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var action: (() -> Void)?
    private var configuration = ""
    private let signature: OSType = 0x51425452 // QBTR

    func configure(enabled: Bool, letter: String, modifiers: ShortcutModifiers, action: @escaping () -> Void) {
        self.action = action
        let newConfiguration = "\(enabled)-\(letter)-\(modifiers.rawValue)"
        guard configuration != newConfiguration else { return }
        configuration = newConfiguration
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        error = nil
        guard enabled else { return }
        let keys: [String: Int] = ["A": kVK_ANSI_A, "B": kVK_ANSI_B, "C": kVK_ANSI_C, "D": kVK_ANSI_D,
            "E": kVK_ANSI_E, "F": kVK_ANSI_F, "G": kVK_ANSI_G, "H": kVK_ANSI_H, "I": kVK_ANSI_I,
            "J": kVK_ANSI_J, "K": kVK_ANSI_K, "L": kVK_ANSI_L, "M": kVK_ANSI_M, "N": kVK_ANSI_N,
            "O": kVK_ANSI_O, "P": kVK_ANSI_P, "Q": kVK_ANSI_Q, "R": kVK_ANSI_R, "S": kVK_ANSI_S,
            "T": kVK_ANSI_T, "U": kVK_ANSI_U, "V": kVK_ANSI_V, "W": kVK_ANSI_W, "X": kVK_ANSI_X,
            "Y": kVK_ANSI_Y, "Z": kVK_ANSI_Z]
        guard let key = keys[letter] else { error = "Choose a letter from A–Z."; return }
        if handler == nil {
            var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                var id = EventHotKeyID()
                let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                               numericCast(MemoryLayout<EventHotKeyID>.size), nil, &id)
                guard result == noErr, id.signature == 0x51425452, id.id == 1 else { return OSStatus(eventNotHandledErr) }
                let controller = Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue()
                Task { @MainActor in controller.action?() }
                return noErr
            }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
            guard status == noErr else { error = "Could not register the shortcut handler (\(status))."; return }
        }
        let flags: Int
        switch modifiers {
        case .controlOption: flags = controlKey | optionKey
        case .commandShift: flags = cmdKey | shiftKey
        case .controlOptionCommand: flags = controlKey | optionKey | cmdKey
        }
        let status = RegisterEventHotKey(UInt32(key), UInt32(flags), EventHotKeyID(signature: signature, id: 1),
                                         GetApplicationEventTarget(), 0, &hotKey)
        if status != noErr { error = "This shortcut is unavailable or used by another app. Choose another combination (\(status))." }
    }
    isolated deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}

struct ShortcutBridge: View {
    @EnvironmentObject private var store: AccountStore
    @Environment(GlobalShortcut.self) private var shortcut
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .onAppear(perform: configure)
            .onChange(of: store.shortcutEnabled) { _, _ in configure() }
            .onChange(of: store.shortcutLetter) { _, _ in configure() }
            .onChange(of: store.shortcutModifiersRaw) { _, _ in configure() }
    }
    private func configure() {
        shortcut.configure(enabled: store.shortcutEnabled, letter: store.shortcutLetter,
                           modifiers: ShortcutModifiers(rawValue: store.shortcutModifiersRaw) ?? .controlOption) {
            openWindow(id: "dashboard")
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
}
#endif
