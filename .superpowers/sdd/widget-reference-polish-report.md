# Widget reference polish report

Date: 2026-07-11

## Scope

Final focused polish of the production Precision Ledger widget against
`docs/assets/codex-auth-widget-precision-ledger.png`.

## Changes

- Applied the one shared `WidgetLayoutMetrics.surfaceInset` inside the material
  surface for all widget families. The material now fills the widget canvas,
  while small, medium, and large content share the same visible internal
  gutter without family-specific padding.
- Reduced the ledger rings from 22/3 to 20/2 points and reduced adjacent
  percentage weight. Percentages remain adjacent to clean rings, not inside
  them; normal 5h remains blue and weekly remains purple.
- Defined a shared large-ledger grid that fits the 338pt canvas after the
  surface inset, reserves a four-point trailing gutter, and limits truncation
  to expendable account/plan labels while preserving reset status text.
- Made deterministic healthy render fixtures two minutes old. The production
  header now renders `2m`, with a unit test for the exact compact-recency value.
- Widened the large reset column from 53 to 64 points and rebalanced only the
  adjacent account/plan columns. The unavailable reset state now renders in
  full without changing the widget bounds or ledger order.

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
