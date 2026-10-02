# QuotaBar

A native macOS app for keeping multiple OpenAI and Claude subscription accounts in view. Written in Swift, with a SwiftUI dashboard and menu bar popover. macOS 14+, Xcode 26.2+ (Swift 6.2+). The app uses the pinned Sparkle 2.9.6 framework for signed automatic updates; the core has no external dependencies.

## What it does

- Add, label, rename, reconnect, and remove multiple accounts for either provider.
- Browse a card dashboard or list; filter by provider and search by label/email.
- See each provider's reported usage percentage and reset countdown, including model-specific windows when available.
- Check all accounts in the macOS menu bar, even after closing the dashboard window.
- Refresh manually or periodically; choose usage consumed or allowance remaining in Settings.
- Get per-account 80% and 95% consumption warnings and confirmed allowance recovery notifications.
- Pin an account's remaining allowance in the menu bar, choosing a specific window or the most constrained window.
- Launch automatically when you sign in to macOS, using the system's Login Items registration.
- Preserve the last reading when a request fails and identify stale readings. Respect `Retry-After` on rate limits.
- Automatically refresh elapsed quota windows with bounded retries and rate-limit backoff.
- Rank accounts by remaining main allowance or next reset, with an “Available only” filter.
- Keep local sampled usage history, view native charts, and export CSV.
- Distribute one universal app for Apple Silicon and Intel, as ZIP and drag-to-Applications DMG.
- Store credentials in macOS Keychain. Account metadata contains labels, usage snapshots, and timestamps only.

## Build and run on your Mac

```sh
cd QuotaBar
./scripts/build-app.sh
open dist/QuotaBar.app
```

Use Xcode 26.2 or newer (Swift 6.2+). The app still supports macOS 14 and newer.

You can also open `Package.swift` in Xcode and run the `QuotaBar` executable scheme. The script defaults to `--unsigned` and builds a universal development `.app` bundle (Apple Silicon + Intel) without certificate/bundle signing, creates `dist/QuotaBar-macOS.zip` preserving executable permissions, and builds `dist/QuotaBar-macOS.dmg` with an Applications shortcut. Push/PR builds and the normal development action use `--unsigned`, skip all packaging-time signing and notarization, and have no update feed configured. The compiler still emits the minimal ad-hoc executable signature required by Apple Silicon; the embedded Sparkle framework retains its upstream signature. The optional signed-release workflow uses your Developer ID certificate and Apple notarization credentials. Development builds may prompt for Keychain access again when their executable changes.

To test:

```sh
swift test
```

The included GitHub Actions workflow compiles the macOS app, runs tests, and packages the app when used in a repository. The first repository workflow run passed macOS compilation, all 18 tests, and app packaging.

## Alerts, pinned allowance, and launch at login

Open **Settings** from the menu bar gear menu.

- **Usage alerts:** enable notifications and accept the macOS notification permission prompt. Configure each account's 80%/95% warnings or a custom consumed-percentage threshold, allowance recovery alert, and optional low-credit warning separately. Alerts are disabled globally until you enable them; per-account defaults enable all three once global notifications are on. macOS Focus and notification settings still control whether a banner is shown.
- **Pinned allowance:** choose an account and a usage window, or use “Most constrained window.” You can also pin/unpin an account directly in the menu bar popover. The icon shows remaining allowance; `~` marks a stale/error reading, and `—` means the chosen window has no reading or has crossed a reset that needs confirmation. The dashboard's consumed/remaining preference does not change the pin's meaning.
- **Launch at login:** move the packaged `QuotaBar.app` into `/Applications`, then enable the toggle. If macOS requires approval, open Login Items from the provided button. The displayed toggle reflects system registration, including changes made in System Settings. A raw Swift package executable cannot register for these OS features.

Warning receipts are saved with account metadata, separately for each window and reset cycle. If a reading jumps past both warning thresholds, only the higher warning is sent. A refresh confirming exhaustion has ended can send a recovery alert; a confirmed new cycle with usage falling from at least 80% can also send one. A countdown alone never sends a recovery alert. Without a reported reset timestamp, threshold/recovery alerts stay deduplicated until a confirmed cycle change or account reconnection. Multiple alerts from one account reading are grouped in one notification. Reconnecting preserves the account's alert preferences; removing the account clears its pin and delivered notifications.

## Availability and usage history

The dashboard and menu bar default to sorting by **Most allowance left**. The score is the minimum remaining allowance across reported main session/weekly windows. Code-review and model-specific windows are shown individually and are not used to claim the whole account is unavailable. Failed, stale, missing, and expired-reset readings have no allowance score. A missing main quota remains unknown. **Available only** includes accounts with a fresh main quota reading and some allowance left. Percentages across different subscriptions are not interchangeable token balances.

Click **History** on an account card to see sampled consumption for a chosen window over 24 hours, 7 days, or 30 days. **Export CSV · all windows** exports the selected date range for every reported window, including observation/reset timestamps and a reading-status column. Expired-window readings are marked `awaiting_reset` in CSV and excluded from the chart. Graph lines break across observed resets, missing windows, and gaps longer than one hour.

History is separate from credentials, under `~/Library/Application Support/QuotaBar/History`, with owner-only permissions. Readings are coalesced into five-minute buckets, preserving observed cycle changes, retained for up to 30 days, and capped at 4,096 snapshots per account. Under heavy use, the cap may retain fewer than 30 days. Nothing is backfilled while the app is closed. Corrupt history is preserved with an error instead of silently overwritten. History can be cleared independently; removing an account also removes its history.

A background clock checks for elapsed resets every 15 seconds while the app is running, in addition to scheduled polling. Unconfirmed reset retries back off from 30 seconds to 15 minutes, and provider `Retry-After` takes precedence. Passed-reset bars and pinned values show a dash until a fresh provider reading confirms the new window. The app keeps monitoring when the dashboard is closed.

## Comparison with Janus

Reviewed [Janus](https://github.com/RamitVishwakarma/Janus/tree/b29c843) at commit `b29c843` on September 30, 2026, using its README and account models. This comparison describes that revision, not every future Janus release.

| Capability | QuotaBar | Janus at the reviewed revision |
| --- | --- | --- |
| Add accounts without displacing your normal CLI sign-in | Isolated Codex device login; isolated Claude web sign-in; explicit file import | Save a session signed in through the CLI; additional accounts are captured after changing CLI login |
| Background provider refresh | Configurable polling for both providers, plus elapsed-reset refresh with bounded retries | Manual refresh; Claude also fetches when a reset is crossed; Codex figures come from manual refresh |
| Consumption notifications | Per-account 80%/95% warnings and confirmed recovery; receipts survive relaunch | Not present in the reviewed source |
| Menu bar information | Pin remaining allowance for an account/window | Shows the live account |
| Usage history and export | Local charts and CSV with observation/reset metadata | Not present in the reviewed source |
| Find accounts with allowance | Ranked main-quota availability, search/filter, card/list views | Account list with main usage bars and manual ordering |
| Start at login | Native system registration and approval status in Settings | README describes adding the app to Login Items manually |
| Apple Silicon and Intel distribution | Universal ZIP and DMG artifacts, validated by CI | Universal app/DMG, GitHub releases and Homebrew cask |

QuotaBar now also switches saved Codex and Claude Code sessions; Janus additionally offers cache cleanup. It also supports renewing saved Claude OAuth credentials, whereas QuotaBar uses Claude web sessions or read-only OAuth imports. QuotaBar does not yet have Janus's Homebrew distribution channel. The compared development builds do not provide Developer ID signing/notarization. QuotaBar's advantage here is independent account observation, alerts, availability and history; this is not a claim of superiority for every task.

## Connect OpenAI

1. Install the official Codex CLI if needed: `npm install -g @openai/codex`.
2. Click **Add account → OpenAI → Sign in with OpenAI**.
3. Use the displayed verification code and the verification page to log in to the desired account. Enable device-code login in your ChatGPT security settings if prompted.
4. Repeat for additional accounts. Use descriptive account labels.

The app invokes the CLI directly, without a shell, with a fresh private `CODEX_HOME` and file credential storage. It searches `/opt/homebrew/bin/codex` and `/usr/local/bin/codex`; you can enter another executable path. The inherited environment is retained, including Node configuration, with common executable locations added to PATH.

Each login uses its own folder under `~/Library/Application Support/QuotaBar`. After login, credentials move to Keychain and the temporary folder is deleted. Normal cancellation deletes it after the child exits; a crash or forced termination can leave a `Login-*` directory, which you can remove after quitting QuotaBar. This is a minimal authentication shadow home; it does not clone your usual Codex configuration, sessions, or projects, or change `~/.codex`.

For these app-owned sessions, an expired access token triggers one refresh via Codex's OAuth token endpoint. Rotated tokens are saved to Keychain before another usage request. Imported sessions retain their complete authentication payload in Keychain for switching, but never grant QuotaBar refresh ownership. Once an app-owned sign-in is handed off to a client, QuotaBar also stops rotating that session's refresh token. Reconnect or let the client renew it when needed.

**Import credentials** lets you select an existing Codex `auth.json` instead. Press Cmd-Shift-G in the file chooser to reach hidden folders such as `~/.codex`.

## Connect Claude

Click **Add account → Claude → Sign in to Claude**. A new, nonpersistent WebKit cookie store is created for every attempt, independent of Safari and other accounts. The app captures the authenticated `sessionKey` and saves it to Keychain. It fetches the account's organizations and asks you to choose if there is more than one.

Some identity providers or bot challenges reject embedded browser login or subsequent native HTTP requests. In that case, use **Import credentials** to select a Claude Code `.credentials.json` containing `claudeAiOauth.accessToken` (typically `~/.claude/.credentials.json` on file-backed installations). Installations that keep credentials solely in Claude Code's Keychain entry do not expose this file; use **Save current CLI sign-in** to explicitly capture that entry and the CLI account identity. macOS may request permission. Imported tokens need the provider's usage/profile scope. Reconnect when the session expires; this app does not rotate Claude Code's refresh token.

Claude OAuth and web sessions both support multiple saved accounts. Claude web sessions are long-lived but can be revoked or expire.

## Switch between subscriptions

Use **Use this account…** from an account card’s menu, or the switching button beside an account in the menu bar. Close the provider’s CLI, desktop app, and editor sessions first. QuotaBar refuses a switch when it detects the affected client running. Start a new session after switching; an existing conversation does not move to another account. Environment variables, API-key helpers, managed policies, and client-specific profiles can override a saved login: verify `codex login status` or Claude Code `/status` before working.

- **Codex:** fresh OpenAI logins and complete imported `auth.json` sessions can be switched into a selected Codex home, defaulting to `$CODEX_HOME` visible to QuotaBar or `~/.codex`. The target must use file-backed credentials. A GUI app does not automatically inherit variables from your shell, so enter a custom home in the switching sheet when necessary. Keyring/Keychain/auto backends are rejected rather than silently writing credentials the client might ignore. Configuration, conversations, and projects are not swapped.
- **Claude Code:** sign in with `claude auth login`, close its sessions, then **Add account → Claude → Save current CLI sign-in**. Repeat for another subscription without calling logout to revoke a saved login. The default macOS `Claude Code-credentials` Keychain entry, or an existing file-backed `.credentials.json`, is captured with the account identity from `.claude.json`. Switching preserves current machine/project preferences while replacing account identity. Complete imported OAuth sessions need `user:inference`; a web session cookie or usage-only OAuth token cannot authenticate Claude Code. Custom `CLAUDE_CONFIG_DIR` Keychain profiles are not switched by this version. Conflicting file and Keychain credentials are preserved and reported.
- **Existing accounts:** accounts saved before 0.7.0 do not have a complete native session. Reconnect OpenAI or use **Reconnect → Save current CLI sign-in** for Claude Code. Monitoring logins remain available independently.

The outgoing session is saved before credentials are replaced, including any rotated tokens. Unknown outgoing subscription accounts are added to the dashboard instead of discarded. Complete client payloads and the last recovery backup live in Keychain; account metadata and usage history contain no secrets. File writes use private temporary files and atomic rename with mode `0600`; symbolic links are rejected. A failed multi-part switch attempts to restore the exact previous credential/settings bytes. **Restore previous sign-in** recovers the last encrypted backup, including an originally signed-out state. QuotaBar never calls provider logout or revokes a saved session during switching.

After handing a session to a client, QuotaBar leaves token renewal to that client and reads its current tokens when monitoring the selected account. Inactive client-owned sessions may need a fresh client login when their access tokens expire. The “Selected for CLI” badge records QuotaBar’s last successful switch, not a live assertion about every client process. Changing accounts outside QuotaBar can make it outdated; capture the current sign-in to reconcile it. Removing a dashboard account does not log the client out or delete recovery backups.

### Desktop and editor compatibility review

| Client | How to use another subscription |
| --- | --- |
| Codex CLI and Codex IDE extension | Official documentation says they share cached authentication. Switch the matching file-backed home, then restart the client/extension and verify its account. |
| Legacy standalone Codex desktop | Some versions may read the shared Codex home, but this was not verified with a live installation. Reopen and confirm the account; there is no universal automatic desktop-switch guarantee. |
| Current ChatGPT desktop / Codex desktop experience | OpenAI’s current documentation describes desktop browser sign-in separately from CLI/IDE cached credentials. Use the app’s account controls or sign in again. QuotaBar offers an open-app shortcut, not desktop credential injection. |
| Claude Code CLI / CLI-backed editor sessions | Default-profile switching is implemented. Restart the session; editor-specific configuration or credential environment variables can select a different login. |
| Claude Desktop, including its Code surface | Anthropic documents a separate OAuth login and explicitly says desktop sessions do not read CLI credential environment variables. Use the desktop app’s account controls. |
| Browser use of ChatGPT and Claude | Separate Safari/Chrome browser profiles keep both subscriptions signed in concurrently. This is a browser alternative, not switching a native desktop app. |
| Strict native desktop isolation | Separate macOS user accounts isolate each user’s app data and Keychain. Fast User Switching changes the whole desktop, so this is more cumbersome than CLI account switching. |

Research sources: [OpenAI authentication](https://developers.openai.com/codex/auth/), [OpenAI desktop settings](https://developers.openai.com/codex/app/settings/), [Codex credential storage source](https://github.com/openai/codex/blob/main/codex-rs/login/src/auth/storage.rs), and [Claude Code authentication](https://code.claude.com/docs/en/authentication). Janus’s session-switching behavior was reviewed as a comparison; this implementation is written independently in Swift. Copying arbitrary Electron profile folders, cookies, or app Keychain entries is not offered as desktop switching because it is not a documented cross-client login mechanism.

Switch transaction tests cover preserving rotated credentials, workspace identity, backup failure, partial writes, concurrent changes, rollback/recovery, absent logins, preference preservation, and private file writes/symlink rejection. No real provider credentials or macOS desktop login sessions were available here: validate both live CLI switching and the exact desktop versions you use before treating a session as switched.

macOS CI additionally runs `QuotaBar.app/Contents/MacOS/QuotaBar --verify-client-switching` against a disposable home and an in-memory Keychain. This exercises both native storage adapters, file/Keychain backend selection, conflicting credentials, account preference merging, and recovery after a partial Keychain write without accessing a user's sign-in.

## Scope and provider compatibility

OpenAI usage is **Codex subscription allowance**, not a universal meter for every ChatGPT feature. API billing and subscription quotas are different; an API key cannot report ChatGPT/Codex or Claude subscription allowance. The app does not calculate API spend, route requests, or run prompts. It can switch supported local Codex and Claude Code subscription sessions; native desktop account switching is separate.

Usage comes from provider-specific interfaces used by subscription clients:

| Source | Usage request | Authentication |
| --- | --- | --- |
| Codex | `https://chatgpt.com/backend-api/wham/usage` | Bearer token + ChatGPT account ID |
| Claude OAuth | `https://api.anthropic.com/api/oauth/usage` | Bearer token + OAuth beta header |
| Claude web | `https://claude.ai/api/organizations/{uuid}/usage` | Web session cookie |

These are not stable public third-party subscription APIs. Providers may change response formats, permissions, client policies, or login support. The OpenAI sign-in uses the official CLI's device flow rather than claiming an arbitrary application can register a general “Sign in with OpenAI” OAuth client. No provider credentials were available here, so live login and live usage requests have not been tested.

Missing windows remain unknown, never fabricated as 0%. Percentages reflect the last successful reading. Passing a reset timestamp does not assume that quota replenished; the app requests confirmation at the reset boundary and on its configured refresh interval. Enterprise or credit-only plans with no supported quota windows show an unrecognized usage response rather than invented allowance. OpenAI credit balances are displayed separately when reported. Claude extra-usage billing is not displayed.

## Implementation and verification

- `Sources/QuotaBar`: SwiftUI views, `MenuBarExtra`, Keychain, private Codex login process, isolated Claude WebKit login, persistence and refresh scheduling.
- `Sources/QuotaCore`: portable credential parsing, quota models, provider requests and response parsing.
- `Tests/QuotaCoreTests`: quota/reset parsing, absent and malformed windows, identity headers, organization selection, rate-limit handling, refresh ownership and metadata separation.

Swift is sufficient for all of these responsibilities. Rust would add a second toolchain and an FFI boundary without helping this app's current workload.

The expanded core suite has 79 tests covering alert persistence and deduplication, confirmed resets, disabled preferences, metadata migration, and pinned allowance behavior in addition to provider parsing and requests. All 79 pass on Swift 6.0.3/Linux. Swift source syntax parsing also passes. Linux compiles only the app's unsupported-platform fallback; it cannot validate SwiftUI, WebKit, Keychain, or macOS UI behavior. The repository workflow compiles the macOS app, runs the full test suite, validates both executable architectures, the ZIP and DMG, and publishes both installers as the app artifact. Live authentication, Keychain behavior, and visual UI behavior still require the following smoke checks.

### macOS smoke checks

1. Build the bundle, launch it, and check the empty dashboard and menu bar.
2. Sign in to two different OpenAI accounts; confirm their labels, plan/windows and that your existing Codex `auth.json` is untouched.
3. Sign in to two Claude accounts (or import OAuth credentials). Verify organization selection when applicable and compare readings with the provider's own usage page.
4. Close the dashboard and reopen it from the menu bar. Exercise search, provider filters, card/list layout, rename and Settings.
5. Disconnect the network and refresh. Last readings should remain visible with an error; restoring connectivity should recover.
6. Quit and relaunch. Accounts should persist, credentials should be in the `com.quotabar.accounts` Keychain service, and `accounts.json` should contain no tokens/cookies.
7. Remove an account and verify its QuotaBar Keychain item is removed. Test login cancellation and reconnecting an expired imported session.
8. In Settings, enable notifications. Check that per-account warning toggles persist after relaunch; verify real 80%/95% threshold alerts and confirmed recovery when provider usage changes. Revoking macOS notification permission should be reflected in Settings.
9. Pin an account/window and confirm the menu bar percentage updates immediately. Reconnect, remove the pinned account, and test a stale/error reading. The icon should not imply unknown allowance is zero.
10. Move the app to Applications, enable launch at login, and verify it appears in macOS Login Items. Sign out/in to check startup, then disable it and confirm registration is removed.
11. Check availability ordering/filtering with healthy, exhausted, failed and expired readings. Code-review exhaustion should not hide an otherwise usable Codex account.
12. Open History after several refreshes; test each date range/window, CSV export, relaunch persistence and clearing history. A reset should divide chart segments, and no data should be invented for closed-app periods.
13. Install the DMG on both Apple Silicon and Intel Macs, or inspect the executable with `lipo -info`. Wait for a reported reset and confirm automatic refresh and temporary unknown values if confirmation is delayed.

## References

Provider endpoint and credential format research used the open-source [CodexBar](https://github.com/steipete/CodexBar) implementation. This project is an independent implementation; no CodexBar source is bundled. The shadow-home approach follows the account-isolation idea you described from T3 Code.

### Version 0.4: credits, privacy, and custom alerts

- **OpenAI credits:** account cards and the menu overview show reported credit balance, unlimited status, and available reset-credit count separately from subscription percentages. Reset inventory is read through `GET /backend-api/wham/rate-limit-reset-credits` using that account's credentials, with a five-second timeout. An unsupported or failed inventory request leaves its count **Not reported** while retaining successful allowance readings. HTTP 429 cooldowns are respected; other failures back off for five minutes. QuotaBar never redeems reset credits or buys credits. Credit-only responses without quota windows remain unsupported.
- **Presentation mode:** use the dashboard eye button, menu settings, or Settings → General. It hides account labels, emails, usage values, balances, reset dates, history, and menu-bar tooltips. It silences new usage notifications and clears existing QuotaBar notifications. Provider names and connected-account counts remain visible. Mode persists across launches; polling and private local history continue. Disable it before connecting accounts or viewing/exporting history.
- **Custom alerts:** select an account in Settings → Usage alerts and choose a threshold from 1–99% consumed, replacing the preset warnings. OpenAI accounts can also set a numeric low-credit threshold. Unknown and unlimited balances never trigger low-credit warnings. Credit warning receipts survive relaunch and rearm after a reported top-up above the threshold. Existing account files retain their preferences and gain optional fields without migration steps.

The new implementation is independent Swift code. Codex Fuel Companion was reviewed for feature ideas; none of its restricted source or artwork was copied.

Additional Mac smoke checks: enable presentation mode while dashboard, menu, history, and Settings are open; verify identities and balances disappear, tooltips reveal no labels, CSV export is unavailable, and notifications stop. Restore normal mode, verify custom thresholds persist, and check credit inventory against a real eligible OpenAI account. These provider and OS interactions need a Mac and live accounts.

### Version 0.5: daily-use tools and release infrastructure

- **Menu-bar display:** choose remaining percentage, reset countdown, credit balance, or icon only in Settings → Menu bar. Pin an account independently of its display mode. Percentage and countdown use the selected window or the most constrained window. Stale readings get `~`; missing credit amounts stay unknown; elapsed reset times show **Due**, never synthetic refills. Presentation mode hides all readings and account tooltips.
- **Global shortcut:** Control + Option + Q opens/activates the dashboard from any app. Settings offers A–Z keys and Control+Option, Command+Shift, or Control+Option+Command modifiers. It can be disabled. macOS registration conflicts appear in Settings. This uses the native hot-key API, without Accessibility or Input Monitoring permissions. Letter choices refer to ANSI physical key positions; a non-US keyboard layout may label that key differently.
- **Connection health:** open the unified view from the dashboard or menu settings. It shows sessions needing reconnection, failed/stale readings, provider cooldowns, and each account's last successful refresh. Exhausted allowance is not classified as a broken connection. Authentication errors clear after a successful reconnect/refresh. Presentation mode hides this view's details.
- **Usage pace:** account cards and history show estimates from observed percentage changes, separate from availability and alerts. Estimates require at least three fresh, continuous readings spanning 30 minutes, at least two percentage points of consumption, and a known upcoming reset. A decrease, missing window, changed reset, or gap over an hour breaks the evidence. At most six hours are considered. Linear estimates disappear when readings become stale, quota is exhausted, or evidence is insufficient. They are not token counts, promises, or provider data; work intensity can change.
- **Automatic updates:** Sparkle performs manual checks, optional scheduled checks/downloads, signature verification, and installation in update-enabled signed release builds. The feed and ZIP are Ed25519-signed, HTTPS is required, and updates are verified before extraction. Checking/downloading is opt-in in Settings. System-profile reporting is disabled. Development artifacts deliberately omit a feed/public key and expose a downloads link instead. Framework resources and its license are bundled; no Rust runtime is introduced.

### Activate signed distribution and updates

The implementation and workflow are ready to review, but no signed/notarized release or live update feed has been produced by this session. Apple/Sparkle private signing credentials are not available in the execution environment; this session's GitHub integration cannot inspect Actions secrets. Ordinary macOS ZIP/DMG artifacts remain downloadable.

Create repository or `release` environment secrets in GitHub Settings → Secrets and variables → Actions:

| Secret | Purpose |
| --- | --- |
| `APPLE_CERTIFICATE_P12_BASE64` | Base64 export of your Developer ID Application certificate **including its private key** |
| `APPLE_CERTIFICATE_PASSWORD` | Password protecting that P12 export |
| `APPLE_SIGNING_IDENTITY` | Full `Developer ID Application: … (TEAMID)` identity |
| `APPLE_ID` | Apple developer account used for notarization |
| `APPLE_APP_PASSWORD` | Apple app-specific password for notarization |
| `APPLE_TEAM_ID` | Developer team identifier |
| `SPARKLE_PUBLIC_KEY` | Public Ed25519 key printed by Sparkle `generate_keys` |
| `SPARKLE_PRIVATE_KEY` | Base64 exported key from Sparkle `generate_keys -x`; retain it privately |

Do not commit private keys or passwords. Keep a backup of the Sparkle key so existing installations can trust future releases.

Run **Actions → Signed macOS release → Run workflow**, with a tag matching the bundle version (currently `v0.8.0`). The default **publish=false** creates a `QuotaBar-macOS-signed` artifact with notarized ZIP/DMG and signed `appcast.xml`. Inspect that artifact first. Set **publish=true** for a subsequent run when ready to publish a GitHub Release; it creates the tag at the built commit, uploads the three files, and marks that release latest. Publishing uses the GitHub workflow token. No release is published by the normal push/PR workflow.

The app uses `https://github.com/ar4ft/QuotaBar/releases/latest/download/appcast.xml`. A release must have both that feed and its signed ZIP available. `CFBundleVersion` must increase for every update. Publishing a non-update-enabled release as latest would interrupt that feed; use this workflow for public releases. The script validates matching public/private keys and the release tag, signs nested framework helpers, notarizes/staples the app and DMG, and deletes the temporary signing keychain and certificate afterward. Notarization and an end-to-end older-version update still need validation with your credentials.

Additional Mac smoke checks: test each display mode and privacy override; trigger the global shortcut with another app focused, change/disable it, and check conflict reporting; inspect connection health after an expired session and recovery. Confirm forecasts match a known history series and disappear for stale/reset data. For a configured signed release, enable update checks, test a higher build number from the signed feed, and verify that unsigned or tampered updates are refused. CI also launches the packaged development app briefly to catch missing embedded-framework or framework-load failures; it does not simulate these interactions.

### Build modes and manual signing

- `./scripts/build-app.sh` or `./scripts/build-app.sh --unsigned`: development ZIP/DMG with no Developer ID signing, no app-bundle sealing, no notarization, and no configured update feed. This mode ignores any inherited signing/notarization variables. Apple Silicon's compiler-generated ad-hoc executable signature and Sparkle's upstream framework signature are retained so the app can launch.
- `./scripts/build-app.sh --signed`: explicitly requested certificate signing, requiring a `Developer ID Application` identity. This mode optionally embeds the configured Sparkle public key and notarizes when the notarization profile is supplied. In GitHub Actions, the script rejects signed builds unless `GITHUB_EVENT_NAME` is `workflow_dispatch`.

**macOS development build** runs on pushes, pull requests, or manual dispatch; every run produces development artifacts without certificate signing. CI verifies the app bundle is not sealed, the executable has no certificate authority, the update key is absent, and the packaged app launches. **Signed macOS release** has only `workflow_dispatch`, an additional manual-event job guard, and explicitly invokes `--signed`; its signing secrets are confined to that separate workflow. The manual signed-release action continues to create signed/notarized ZIP/DMG plus the signed Sparkle feed when credentials are configured, with GitHub Release publishing opt-in.

### Version 0.6: macOS interface polish

The interface now follows Apple's [macOS design](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos), [toolbar](https://developer.apple.com/design/human-interface-guidelines/toolbars), [sidebar](https://developer.apple.com/design/human-interface-guidelines/sidebars), [accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility), [Dark Mode](https://developer.apple.com/design/human-interface-guidelines/dark-mode), and [app icon](https://developer.apple.com/design/human-interface-guidelines/app-icons) guidance:

- Native navigation title, toolbar actions, sidebar sections, semantic typography, and primary buttons that respect the user's accent color. Dashboard controls and summary tiles adapt to available width.
- System colors and semantic surface/separator colors adapt to light/dark appearances. Increase Contrast strengthens card boundaries. Status labels pair symbols with words, so color is never the only signal. Native progress indicators replace custom-drawn usage bars.
- VoiceOver labels for icon controls, sidebar account counts, summary values, allowance meters, pin state, and history rows. Decorative symbols are hidden from accessibility. Presentation mode's accessible values remain private.
- Settings is divided into General, Menu Bar, Alerts, and Updates tabs. Sheets use standard Cancel/Done buttons, keyboard actions, clearer destructive wording, and smaller/adaptive bounds for laptop displays.
- An original macOS app icon is rendered at all standard 1×/2× icon sizes and packaged as `QuotaBar.icns`. Layer SVG artwork is under `Resources/AppIcon`; the deterministic AppKit renderer is `scripts/render-icon.swift`. The flattened icon supports macOS 14 and the Xcode 26.2 build pipeline. The icon remains a flattened compatibility asset; a native Icon Composer layered asset is a separate future enhancement.

CI produces a separate **QuotaBar-UI-Previews** artifact containing native light/dark, high-contrast, compact-width, menu, Settings, Codex/Claude switching, and presentation-mode snapshots, plus the 1024px icon. Preview mode uses synthetic accounts with example.invalid addresses, private temporary preferences, and no credential reads, provider polling, or account-file writes. Run `QuotaBar.app/Contents/MacOS/QuotaBar --render-previews <directory>` on a Mac to reproduce them.

These changes are informed by the HIG; they are not an Apple certification or a completed accessibility audit. Manual VoiceOver, keyboard navigation, Increase Contrast/Reduce Transparency, and real-device layout checks remain part of release testing. Push/PR builds continue to skip certificate signing; only the manually dispatched signed-release workflow can sign/notarize.


## SwiftUI Pro review (0.8.0)

Reviewed with Paul Hudson’s [swiftui-pro](https://github.com/twostraws/swiftui-agent-skill) skill. Install locally with `npx skills add https://github.com/twostraws/swiftui-agent-skill --skill swiftui-pro --yes`; its source hash is recorded in `skills-lock.json`. Agent-tooling files are excluded from the app repository.

The app now builds with Swift 6.2 in Swift 6 language mode. CI selects Xcode 26.2 for both unsigned development and manual signed releases. macOS 14 remains supported: Settings uses the modern Tab API on macOS 15+, with a compatibility branch for macOS 14. Login, hot-key, and login-item helpers use Observation. The account store retains its existing AppStorage integration, and Sparkle retains its Combine/KVO bridge; neither is wrapped in an Observable macro that would break settings updates.

Dashboard summaries now refresh countdowns and availability with TimelineView. Dedicated settings panes and meter/summary components reduce large view bodies, with shared spacing/surface constants. Native status colors keep their text/symbol meanings, provider labels are explicit, and account switching is directly visible on cards. Login and switching sheets scroll and resize instead of requiring one fixed height. Very small remaining allowances and nearly exhausted windows are displayed/spoken accurately rather than rounded to a misleading 0% or 100%.

See [the review and applied changes](docs/swiftui-pro-review.md). Native previews and synthetic switching checks remain in CI. Certificate signing still happens only in the manually dispatched signed-release workflow. Live provider sessions and manual VoiceOver/navigation checks remain outside synthetic CI coverage.
