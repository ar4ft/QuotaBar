# QuotaBar

A native macOS app for keeping multiple OpenAI and Claude subscription accounts in view. Written in Swift, with a SwiftUI dashboard and menu bar popover. macOS 14+, Xcode 16+. No external package dependencies.

## What it does

- Add, label, rename, reconnect, and remove multiple accounts for either provider.
- Browse a card dashboard or list; filter by provider and search by label/email.
- See each provider's reported usage percentage and reset countdown, including model-specific windows when available.
- Check all accounts in the macOS menu bar, even after closing the dashboard window.
- Refresh manually or periodically; choose usage consumed or allowance remaining in Settings.
- Preserve the last reading when a request fails and identify stale readings. Respect `Retry-After` on rate limits.
- Store credentials in macOS Keychain. Account metadata contains labels, usage snapshots, and timestamps only.

## Build and run on your Mac

```sh
cd QuotaBar
./scripts/build-app.sh
open dist/QuotaBar.app
```

You can also open `Package.swift` in Xcode and run the `QuotaBar` executable scheme. The script builds and ad-hoc signs a `.app` bundle for local use. It does not notarize the app. Distribution needs your own bundle identity, Developer ID signature and notarization. Rebuilding an ad-hoc signed app may prompt for Keychain access again.

To test:

```sh
swift test
```

The included GitHub Actions workflow compiles the macOS app, runs tests, and packages the app when used in a repository. It has not been run in this workspace.

## Connect OpenAI

1. Install the official Codex CLI if needed: `npm install -g @openai/codex`.
2. Click **Add account → OpenAI → Sign in with OpenAI**.
3. Use the displayed verification code and the verification page to log in to the desired account. Enable device-code login in your ChatGPT security settings if prompted.
4. Repeat for additional accounts. Use descriptive account labels.

The app invokes the CLI directly, without a shell, with a fresh private `CODEX_HOME` and file credential storage. It searches `/opt/homebrew/bin/codex` and `/usr/local/bin/codex`; you can enter another executable path. The inherited environment is retained, including Node configuration, with common executable locations added to PATH.

Each login uses its own folder under `~/Library/Application Support/QuotaBar`. After login, credentials move to Keychain and the temporary folder is deleted. Normal cancellation deletes it after the child exits; a crash or forced termination can leave a `Login-*` directory, which you can remove after quitting QuotaBar. This is a minimal authentication shadow home; it does not clone your usual Codex configuration, sessions, or projects, or change `~/.codex`.

For these app-owned sessions, an expired access token triggers one refresh via Codex's OAuth token endpoint. Rotated tokens are saved to Keychain before another usage request. Imported `auth.json` credentials intentionally do not carry a refresh token: reconnect or re-import a fresh file when they expire so QuotaBar cannot rotate another client's token.

**Import credentials** lets you select an existing Codex `auth.json` instead. Press Cmd-Shift-G in the file chooser to reach hidden folders such as `~/.codex`.

## Connect Claude

Click **Add account → Claude → Sign in to Claude**. A new, nonpersistent WebKit cookie store is created for every attempt, independent of Safari and other accounts. The app captures the authenticated `sessionKey` and saves it to Keychain. It fetches the account's organizations and asks you to choose if there is more than one.

Some identity providers or bot challenges reject embedded browser login or subsequent native HTTP requests. In that case, use **Import credentials** to select a Claude Code `.credentials.json` containing `claudeAiOauth.accessToken` (typically `~/.claude/.credentials.json` on file-backed installations). Installations that keep credentials solely in Claude Code's Keychain entry do not expose this file; this version does not automatically read another app's Keychain entries. Imported tokens need the provider's usage/profile scope. Reconnect when the session expires; this app does not rotate Claude Code's refresh token.

Claude OAuth and web sessions both support multiple saved accounts. Claude web sessions are long-lived but can be revoked or expire.

## Scope and provider compatibility

OpenAI usage is **Codex subscription allowance**, not a universal meter for every ChatGPT feature. API billing and subscription quotas are different; an API key cannot report ChatGPT/Codex or Claude subscription allowance. The app does not calculate API spend, route requests, run prompts, or switch another app's active account.

Usage comes from provider-specific interfaces used by subscription clients:

| Source | Usage request | Authentication |
| --- | --- | --- |
| Codex | `https://chatgpt.com/backend-api/wham/usage` | Bearer token + ChatGPT account ID |
| Claude OAuth | `https://api.anthropic.com/api/oauth/usage` | Bearer token + OAuth beta header |
| Claude web | `https://claude.ai/api/organizations/{uuid}/usage` | Web session cookie |

These are not stable public third-party subscription APIs. Providers may change response formats, permissions, client policies, or login support. The OpenAI sign-in uses the official CLI's device flow rather than claiming an arbitrary application can register a general “Sign in with OpenAI” OAuth client. No provider credentials were available here, so live login and live usage requests have not been tested.

Missing windows remain unknown, never fabricated as 0%. Percentages reflect the last successful reading. Passing a reset timestamp does not assume that quota replenished; the app requests a new reading on its configured refresh interval. Enterprise or credit-only plans with no supported quota windows show an unrecognized usage response rather than invented allowance. Extra usage spend/credit balances are not displayed in this version.

## Implementation and verification

- `Sources/QuotaBar`: SwiftUI views, `MenuBarExtra`, Keychain, private Codex login process, isolated Claude WebKit login, persistence and refresh scheduling.
- `Sources/QuotaCore`: portable credential parsing, quota models, provider requests and response parsing.
- `Tests/QuotaCoreTests`: quota/reset parsing, absent and malformed windows, identity headers, organization selection, rate-limit handling, refresh ownership and metadata separation.

Swift is sufficient for all of these responsibilities. Rust would add a second toolchain and an FFI boundary without helping this app's current workload.

The core's 18 tests pass on Swift 6.0.3/Linux. Swift source syntax parsing also passes. Linux compiles only the app's unsupported-platform fallback; it cannot validate SwiftUI, WebKit, Keychain, or macOS UI behavior. The macOS workflow and the following smoke checks are provided for the remaining validation.

### macOS smoke checks

1. Build the bundle, launch it, and check the empty dashboard and menu bar.
2. Sign in to two different OpenAI accounts; confirm their labels, plan/windows and that your existing Codex `auth.json` is untouched.
3. Sign in to two Claude accounts (or import OAuth credentials). Verify organization selection when applicable and compare readings with the provider's own usage page.
4. Close the dashboard and reopen it from the menu bar. Exercise search, provider filters, card/list layout, rename and Settings.
5. Disconnect the network and refresh. Last readings should remain visible with an error; restoring connectivity should recover.
6. Quit and relaunch. Accounts should persist, credentials should be in the `com.quotabar.accounts` Keychain service, and `accounts.json` should contain no tokens/cookies.
7. Remove an account and verify its QuotaBar Keychain item is removed. Test login cancellation and reconnecting an expired imported session.

## References

Provider endpoint and credential format research used the open-source [CodexBar](https://github.com/steipete/CodexBar) implementation. This project is an independent implementation; no CodexBar source is bundled. The shadow-home approach follows the account-isolation idea you described from T3 Code.
