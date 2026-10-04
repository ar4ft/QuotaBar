# QuotaBar: calm instrument panel

Brief: existing native SwiftUI macOS account-consumption manager for people with multiple OpenAI and Claude subscriptions. In the first ten seconds, compare remaining allowance and reset times, then select the account for a CLI session. User chose “Calm instrument panel.” Product scope comes from the conversation; visual concepts are self-authored. No paid image generation.

## Current app

Before: 0.8.0 native screenshots in the previous UI artifact. The equal three-stat card strip delays the useful account readings. Provider-colored icon chips repeat decoration. Default thin progress bars understate the app's central information.

Keep: both providers, every usage window and credits/reset credits; resets; availability, errors, staleness and refresh; switching and recovery; history/export; grid/list, search, sorting and availability filter; presentation privacy; menu-bar pinning, reconnect, settings and update actions. No navigation/tab changes, removed features or new authentication mechanism.

## Exploration

`explore.html` renders three desktop concepts with the same synthetic data:

- **Instrument panel** (object, light, grotesque, blue, shape): calibration tracks and system text. Chosen with the user's preference: precise and easy to compare at a glance.
- **Observatory** (place, dark, mono, orange, colour-material): amber signals against a deep ground. Lost because forced dark mode and pervasive mono weaken everyday native Mac readability.
- **Field guide** (printed, colour-field, serif, green, colour-material): green pages and editorial headings. Lost because the content is live instrument data rather than reading material.

No photography is needed for this utility. The richness comes from the allowance track shape, disciplined numeric scale and selection state. The existing appearance is object/light/grotesque/provider green-orange/colour-material; the chosen direction retains native readability intentionally rather than changing three axes for novelty.

## Tokens

System semantic colors remain the authority for text, backgrounds and separators, preserving Mac appearance and increased contrast. Reference values: light ground #F2F5F9, raised #FFFFFF, ink #172332, secondary #506074; dark ground #101820, raised #1B2835, ink #F1F5F8, secondary #B9C7D2. These are exploration values, not forced replacements for AppKit accessibility colors.

One system-blue signal for live allowance and selection. Orange is low allowance/error and green is available, always accompanied by words and symbols. Provider identity is stated as text and a neutral symbol, rather than a hue.

Type: SF Pro system styles. Reset display large-title bold, allowance title bold with tabular figures, account title headline, labels callout, metadata caption. Avoid fixed-size text. Space: 4/8 inside groups, 12 for rows, 20 within account objects, 24 between sections, 32 before readings. Radius: 12 for account objects, 2 for calibrated tracks. No shadows or content glass.

## Content

Synthetic samples: Personal / OpenAI / personal@example.invalid / Plus; 58% session left, reset 2h; 24% weekly left, reset 2d; credits 250 and 2 reset credits. Work / Claude / work@example.invalid / Pro; 14% session left, reset 1h 1m; 49% weekly left, reset 3d. Header: Next reset / 1h 1m; Connected / 2; Available / 2. All values represent provider windows independently, never a pooled balance.

Production copy and data remain provider-derived. Every allowance window retains its reset label. Privacy mode hides account details, balances and reset values.

## Signature: selecting an instrument channel

Trigger: Use account opens the existing confirmation sheet. First frame: target provider/client and account identity. Second: successful existing credential transaction, with saved recovery sign-in. Third: selected marker and accented outline on that account in the dashboard and a selected marker in the menu. No change is displayed before transaction success. No fabricated demo credential writes. Numeric readings transition only when values change; Reduce Motion disables animation. Keyboard users receive the same labels; no haptic dependence on Mac.

## Platform adaptation

Use Mac window sizes, native split view/sidebar/toolbars, scrollable sheets and ordinary desktop controls. No phone frame, thumb-zone controls, iOS-only glass/haptics, or phone tap-size requirements. System settings panes and the app icon retain the existing identity. Build with Xcode 26.2 / Swift 6.2, support macOS 14+. Authentication logic and manual-only certificate-signing policy are unchanged.

## Verification

App Designer's renderer/scanner is used on the HTML exploration at 3×. Local adaptation loads HTML and contact-sheet images from memory because browser file URLs are blocked; the scanner's phone dimensions are neutralized for desktop content. Native SwiftUI screenshots and CI are the implementation authority. HTML fonts on Linux are approximations, not claims of rendered SF Pro. Accessibility and live credentials still need hands-on Mac testing.

## Keep-list check after implementation

Checked means preserved in source and the applicable synthetic checks/previews, not live provider verification.

- [x] OpenAI and Claude account monitoring, all reported windows, credits/reset credits.
- [x] Reset times and their source account/window.
- [x] Availability, errors, stale readings, refresh and reconnect actions.
- [x] CLI switching, selected marker, credential reapplication and recovery.
- [x] History/export routes and storage behavior.
- [x] Grid/list, search, sorting and availability filtering.
- [x] Presentation privacy, menu pinning/actions, settings and updates.

User decisions outstanding: none for this iteration. The user chose the calm instrument-panel direction. Name, icon identity and navigation structure remain; the existing next-reset value is emphasized, not replaced by a different metric. See CRITIQUE.md for the scored rounds and verification limits.
