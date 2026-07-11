# Codex Auth Widget Design QA

Reference: `docs/assets/codex-auth-widget-precision-ledger.png`

## Reproduce

Run `./script/render_widget_previews.sh`. The script renders the production
`CodexAuthWidgetView` through `WidgetPreviewHarness` with deterministic
family-specific 1/3/6-account fixtures on an opaque dark test canvas; it does
not read or modify live auth data.
The exported files are `widget-small.png`, `widget-medium.png`, and
`widget-large.png` in this directory.

## Findings

- Small hierarchy and dual-ring proportions: pass — direct inspection of the 316 × 316 px dark export shows the header, account name, plan, centered dual rings, percentage, and reset footer.
- Medium three-row ledger spacing and alignment: pass — direct inspection of the 676 × 316 px dark export shows three named ledger rows, paired rings, reset text, and right-aligned numeric legends.
- Large six-row fixed-column alignment and truncation: pass — direct inspection of the 676 × 708 px dark export shows six rows, paired fixed-size rings, account-name truncation, and reset-column truncation.
- Dark rendering: pass — the opaque test canvas and production root view render text, rings, and widget material together. Light and increased-contrast artifacts are not part of this deterministic three-PNG export.
- VoiceOver and numeric redundancy: pass for widget semantics — the widget unit suite passes the numeric accessibility-value regression. Menu-bar keyboard/VoiceOver automation has a separate macOS TCC blocker below.

## Evidence

- `./script/render_widget_previews.sh`: passed on 2026-07-11; it ran only the three render tests and exported the PNGs above.
- `ImageRenderer` emitted non-empty 2× PNG attachments with an opaque dark canvas. The medium and large tests assert that their deterministic source fixtures contain 3 and 6 accounts, respectively.

## Regression commands

- `xcodebuild test -project CodexAuthBar.xcodeproj -scheme CodexAuthWidget -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`: passed (9 tests).
- `xcodebuild test -project CodexAuthBar.xcodeproj -scheme CodexAuthBarUITests -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=''`: builds and launches the UI suite, but the keyboard test is blocked by a pending macOS notification-permission dialog owned by `UserNotificationCenter`. Dismissing it causes XCTest to lose the app accessibility tree. The direct status-item path is also off-screen in this desktop layout.

final visual result: passed

## External automation blocker

The remaining menu-bar keyboard/VoiceOver UI check is not a visual widget
failure. On this machine, a stale per-bundle notification permission dialog is
shown by `UserNotificationCenter` before interaction. The app process is
launched with no existing Codex Auth Bar process, and the unsigned UI test
build succeeds; after XCTest dismisses the dialog, macOS removes the app’s
accessibility tree. `tccutil reset Notifications com.mesteriis.CodexAuthBar`
also failed locally. Clear the pending notification permission through macOS
and rerun the unsigned UI command above to complete that automation check.
