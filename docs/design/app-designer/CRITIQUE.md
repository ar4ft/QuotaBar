# App Designer critique

Independent critic, same reviewer across rounds. Rubric adapted to macOS; HTML experiments do not establish live interaction or native rendering quality.

## Round 1: exploration

| Rubric | Score |
|---|---:|
| Concept | 4 |
| Category distinction | 4 |
| Skill distinction | 4 |
| Hierarchy | 4 |
| Typography | 4 |
| Color | 3 |
| Richness | 3 |
| Rhythm | 3 |
| Craft | 3 |
| Native fluency | 2 |
| Signature | 3 |
| Feature test | 3 |
| Fidelity | 2 provisional |

Not done. Critic asked to restore native chrome, credits/freshness, clarify allowance semantics, tighten rhythm and show the chosen design in dark/compact/list/menu states. The SwiftUI implementation addresses those asks; additional preview states verify selected-account highlighting. The allowance summary now says “With allowance” and “including running low.” The reset names its source account/window. Quarter marks are at 25/50/75%, explained by help text.

The three exploration frames passed App Designer's HTML scan with no failures/warnings at 3×. It checks browser geometry and solid-ground text contrast, not native SwiftUI accessibility. Native screenshots and tests are a separate check. No claim of perfect skill completion or an Apple award.

## Round 2: native SwiftUI

All twelve native screens and icon reviewed by the same critic. Concept/category/skill/hierarchy/type/rhythm/native fluency: 4 each. Color, richness, craft, signature, feature test: 3 each. Fidelity: 4 provisional. Seven of twelve lines reach 4: not done.

Must fixes: allow selected-account reapplication after external CLI login; improve adaptive foreground contrast of dark sidebar provider rows. Verification request: high-contrast appearance snapshots looked identical to dark; do not treat them as evidence of the full OS accessibility setting. These are addressed by keeping “Use again” enabled, explicit primary provider row foregrounds, setting the AppKit application appearance before each capture, and publishing each preview's appearance/system Increase Contrast metadata.

Optional asks declined for this iteration: additional menu freshness is useful but the existing stale/error line already warns about bad readings; a horizontally dense List is a separate interaction/layout redesign, beyond the user's selected visual direction. Both can be revisited without blocking these fixes. No decorative additions to inflate richness scores.

## Round 3: final native review

Same independent critic opened all twelve frames, the overview sheet and contrast metadata. Scores: concept/category distinction/skill distinction/hierarchy/type/color/rhythm/craft/native fluency **4** each; richness/signature/feature test **3** each. Fidelity **4 provisional**. Nine of twelve lines at 4, none below 3: done by the skill's stop rule. No concrete pixel defect identified. Changes from round 2: readable dark provider rows, native dark controls consistent with the rest of the window, enabled “Use again” while retaining selected marker/outline.

High-contrast metadata reports `requestedHighContrastAppearance: true`, `systemIncreaseContrast: false`. This proves which appearance was requested, not testing of the full OS Increase Contrast setting. That setting, VoiceOver, long names/additional windows at minimum width, and live stale/error/switching behavior remain manual release checks. Do not infer switching/export execution from screenshots; existing synthetic CI checks and core tests provide separate evidence.

Verification for implementation commit `5854e5afbba7bef3e2917528d5e9bcbbe446d329`: [macOS run](https://github.com/ar4ft/QuotaBar/actions/runs/37212643887) passed 99 core tests, native compilation, universal arm64/x86_64 optimized packaging, distributable launch/ZIP checks, synthetic switching/recovery checks, and the automatic-signing rejection guard. [ZIP/DMG](https://github.com/ar4ft/QuotaBar/actions/runs/37212643887/artifacts/11307396515) and [native previews with metadata](https://github.com/ar4ft/QuotaBar/actions/runs/37212643887/artifacts/11307326759) are published. These are unsigned development installers. No signed workflow was dispatched.

Before/after: compare [0.8.0 native previews](https://github.com/ar4ft/QuotaBar/actions/runs/37043717144) with the 0.9.0 previews above. The local working folder also contains `/workspace/scratch/quota-designer/before-after.html` and `/workspace/scratch/quota-designer/native-r3/sheet.png`. The exploration's App Designer HTML scan passed at 3× with no failures or warnings; native screenshots were visually reviewed rather than misrepresented as DOM-scan results. SF Pro and Mac controls are verified in native screenshots; Linux exploration fonts are approximations. Motion timing, real-device feel and real credentials are unverified.

No further code changes after the final critique. Future improvements from the critic (not blockers): actual OS contrast testing; stale/error captures; long names and more windows; compact menu freshness; a denser List interaction. Signature remains a familiar select/reapply flow with calibrated tracks; no claim of bespoke haptics or an award-level animation.
