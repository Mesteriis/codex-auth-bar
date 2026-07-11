# Widget reference polish report

Date: 2026-07-11

## Scope

Final focused polish of the production Precision Ledger widget against
`docs/assets/codex-auth-widget-precision-ledger.png`.

## Changes

- Applied `WidgetLayoutMetrics.ledgerHorizontalInset` to medium and large
  ledger content. The measured six-point gutter protects the content without
  compressing the six-account large layout; its regression assertion now
  matches the production value.
- Added two points of top clearance and slightly increased stack spacing for
  the medium and large headers.
- Reduced the ledger rings from 22/3 to 20/2 points and reduced adjacent
  percentage weight. Percentages remain adjacent to clean rings, not inside
  them; normal 5h remains blue and weekly remains purple.
- Rebalanced large-ledger column widths after applying the gutter, eliminating
  account/plan overlap while preserving the 338×354 widget bound.
- Made deterministic healthy render fixtures two minutes old. The production
  header now renders `2m`, with a unit test for the exact compact-recency value.

## Visual inspection

Rendered `docs/qa/widget-small.png`, `docs/qa/widget-medium.png`, and
`docs/qa/widget-large.png` directly from production SwiftUI. The medium and
large ledger now have visible surface breathing room, lighter ring strokes and
type, un-clipped columns, and the expected `2m` header. The small render also
uses the two-minute fixture and remains within its 158×158 bound.

## Validation

- `./script/render_widget_previews.sh` — passed; all three production renders
  exported at 2× for 158×158, 338×158, and 338×354 bounds.
- `xcodebuild test -project CodexAuthBar.xcodeproj -scheme CodexAuthWidget -destination "platform=macOS,arch=$(uname -m)" -only-testing:CodexAuthWidgetTests/CodexAuthWidgetTests CODE_SIGNING_ALLOWED=NO` — passed, 13 tests.

The test environment emitted its pre-existing CoreSimulator version warning,
but macOS builds and tests completed successfully.
