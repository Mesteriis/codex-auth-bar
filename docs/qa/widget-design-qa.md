# Codex Auth Widget Design QA

Reference: `docs/assets/codex-auth-widget-precision-ledger.png`

## Reproduce

Run `./script/render_widget_previews.sh`. The script renders the deterministic
`WidgetPreviewHarness.healthy` fixture with the production small, medium, and
large views in dark appearance; it does not read or modify live auth data.
The exported files are `widget-small.png`, `widget-medium.png`, and
`widget-large.png` in this directory.

## Findings

- Small hierarchy and dual-ring proportions: blocked — the 316 × 316 px dark export contains only the purple dual-ring strokes on a transparent canvas; header, account text, percentage labels, and reset footer are not visible for comparison.
- Medium three-row ledger spacing and alignment: blocked — the 676 × 316 px dark export contains one visible ring at the left; the required header, three ledger rows, labels, and material are not visible.
- Large six-row fixed-column alignment and truncation: blocked — the 676 × 708 px dark export contains two visible ring strokes; the required six-row ledger, fixed columns, labels, and material are not visible.
- Light, dark, and increased-contrast rendering: blocked — the deterministic script captures dark only, and the dark output is incomplete; light and increased-contrast have not been rendered.
- VoiceOver and numeric redundancy: pending — this is evaluated by the widget semantic and menu-bar UI accessibility regression commands below.

## Evidence

- `./script/render_widget_previews.sh`: passed on 2026-07-11; it ran only the three render tests and exported the PNGs above.
- `ImageRenderer` emitted non-empty PNG attachments at 2× scale. The incomplete rendered content is a P1 visual discrepancy against the approved reference, not a build failure.

## Regression commands

- `xcodebuild test -project CodexAuthBar.xcodeproj -scheme CodexAuthWidget -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`: passed (9 tests).
- `xcodebuild test -project CodexAuthBar.xcodeproj -scheme CodexAuthBarUITests -destination 'platform=macOS' CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=`: blocked before tests because the app and widget targets require a provisioning profile. No keyboard or VoiceOver UI-test result was produced.

final result: blocked
