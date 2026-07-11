# Task 7 Report — Visual QA, Accessibility Regression, and Preview Artifacts

## Delivered

- Added three deterministic `ImageRenderer` tests for the production small,
  medium, and large widget views, using centralized size and scale fixtures.
- Added `WidgetPreviewHarness.view(family:colorScheme:)`, which renders the
  production `CodexAuthWidgetView` with a test-only family override and
  deterministic 1/3/6-account fixtures.
- Added `script/render_widget_previews.sh`, which runs only the render tests,
  exports XCTest attachments with `xcresulttool`, normalizes their names, and
  fails if any expected PNG is absent. It reads no live auth data.
- Generated and committed `docs/qa/widget-small.png`, `widget-medium.png`, and
  `widget-large.png` from a successful script run.
- Recorded direct visual inspection in `docs/qa/widget-design-qa.md`.

## Checks

- `./script/render_widget_previews.sh`: passed. Produced non-empty 2× PNGs:
  small 316 × 316, medium 676 × 316, large 676 × 708.
- `xcodebuild test -project CodexAuthBar.xcodeproj -scheme CodexAuthWidget -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`: passed, 9 tests.
- `xcodebuild test -project CodexAuthBar.xcodeproj -scheme CodexAuthBarUITests -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=''`: builds and launches the UI suite. The menu-bar keyboard test is interrupted by a stale `UserNotificationCenter` permission dialog and fails only after macOS removes the app accessibility tree.

## Blocker

The direct visual inspection now passes: the opaque dark render canvas and
production root view expose text, material, rings, and all required 1/3/6
family rows. The remaining issue is external macOS UI automation state, not
widget rendering: a pending notification permission dialog is owned by
`UserNotificationCenter`; dismissing it removes the test app accessibility
tree. No existing Codex Auth Bar process was present before the run, and
`tccutil reset Notifications com.mesteriis.CodexAuthBar` failed locally.
