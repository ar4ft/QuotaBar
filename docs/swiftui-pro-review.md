# SwiftUI Pro review and applied changes

Review source: installed `.agents/skills/swiftui-pro/SKILL.md`, Paul Hudson’s swiftui-pro 1.1. Source hash: `skills-lock.json`. Findings below were applied, not just proposed.

## Package.swift:1 and .github/workflows/macos.yml:13

**Use Swift 6.2+ and modern concurrency checks.**

Before: `swift-tools-version: 6.0`, `swiftLanguageModes: [.v5]`.

After: `swift-tools-version: 6.2`, `swiftLanguageModes: [.v6]`; CI explicitly selects Xcode 26.2. Deployment remains macOS 14 because this is an existing Mac application, not a new iOS application. Unsigned automation and manual-only certificate signing remain separate.

## PreferencesView.swift:6

**Extract large view bodies; use typed selection and modern Tab APIs.**

Before: four settings forms in a single body, `.tabItem()` everywhere, fixed `620 × 540` content.

After: `GeneralSettings`, `MenuBarSettings`, `AlertSettings`, and `UpdateSettings` in separate files; `SettingsTab` enum selection; `Tab` on macOS 15+ and a macOS 14 compatibility branch; flexible minimum/ideal dimensions.

## CodexLogin.swift:7, LaunchAtLogin.swift:7, GlobalShortcut.swift:9

**Use main-actor Observation for standalone shared helpers.**

Before: `ObservableObject`, `@Published`, `@StateObject`/`@EnvironmentObject` throughout the helpers.

After: `@MainActor @Observable`, `@State`, and typed `@Environment` where shared. Actor-isolated hot-key teardown uses Swift 6.2 isolated deinitialization. The process login completion is explicitly `@MainActor @Sendable`, so background process callbacks cannot invoke UI state outside its actor. The persistent AccountStore and Sparkle retain their justified AppStorage and Combine integration boundaries.

## DashboardView.swift:20 and DashboardMetrics.swift:9

**Extract computed view sections and update time-sensitive summaries.**

Before: inline metric composition, `Date()` used only when the parent recomputed; repeated account transforms inside collection builders; case-only search.

After: dedicated timeline-driven metrics with adaptive columns, locally derived accounts for the collection, and `localizedStandardContains()` for user search. `MetricTile` and `AccountFilter` each have a separate file.

## AccountCard.swift:4, UsageMeter.swift:9, AccountSurface.swift:5

**Use accessible labels, readable native typography, and consistent surfaces.**

Before: image-only menu trigger, switching hidden in an action menu, small whole-percent readings, multiple view types in one file, legacy overlay overload.

After: labeled menu with icon-only styling, explicit provider name and visible Use account/History controls, larger semantic allowance text, dedicated components, shared surface constants, and `.overlay { ... }`. Statuses combine semantic colors with symbols and words.

**Do not round a nonzero allowance to exhaustion.**

Before: `Int(value.rounded())` could show `0%` while allowance remained or `100%` before exhaustion.

After: tested `AllowancePercent.display()` and `.spoken()` use `<1%` / `>99%` at the edges; VoiceOver follows the chosen remaining/used display mode.

## ClientSwitchView.swift:14 and ConnectAccountView.swift:28

**Allow sheets to fit smaller windows; separate actions from layout.**

Before: fixed widths with eager vertical content; switch/restore business logic inside button closures.

After: scrolling, flexible minimum/ideal sizes and named switch/restore actions. Credential replacement stays serialized with existing backup/rollback behavior; this review does not claim an asynchronous Keychain redesign or live subscription validation.

## MenuBarView.swift:27 and UsageHistoryView.swift:34

**Use lazy account stacks and consistent privacy layouts.**

Before: eager account stack in the menu and a fixed-size privacy history view.

After: lazy account stack and a flexible privacy placeholder. Privacy labels continue to hide account identities from VoiceOver.

## Priority and validation

1. Correctness: Swift 6 concurrency checks, accurate percentage edges, live countdowns.
2. Usability: discoverable switching, explicit providers, flexible sheets and settings.
3. Maintainability: smaller view files, typed settings selection, Observation helpers and shared visual constants.

Portable tests cover core logic; macOS CI verifies native compilation, synthetic credential adapters, universal ZIP/DMG packaging, unsigned-mode guards and appearance previews. Manual VoiceOver, real desktop/account sessions, and release notarization with signing credentials remain separate release checks.
