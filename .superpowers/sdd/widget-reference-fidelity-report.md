# Widget Reference Fidelity Report

Reference: `docs/assets/codex-auth-widget-precision-ledger.png`

Date: 2026-07-11

## Implemented

- Production `CodexAuthWidgetView` now owns a rounded `.regularMaterial` surface with a subtle semantic stroke, shadow, and 12 pt content inset. The deterministic renderer captures that production surface rather than relying on the canvas for it.
- Small, medium, and large layouts use protected edge clearance. The small reset footer is visible; medium has a header divider, three rows, and bottom clearance; large retains six fixed-column rows.
- Reset display is compact and localizable (`2d 14h` in English; localized Russian units), while VoiceOver retains the full relative reset phrase.
- Normal 5-hour capacity is blue and weekly capacity is purple. Orange/red override both series for warning/critical values. The ring glyph was removed; accessibility speaks low/critical state.
- Rings are clean gauges: small keeps `5h → W` center labels and one adjacent numeric legend per series; medium/large place each percentage once beside its ring. Visible `W` remains catalog-backed and VoiceOver expands it to Weekly.
- The large preview fixture uses the requested `3 healthy · 1 low · 1 stale` reference hierarchy. Ledger accessibility includes the displayed plan and status.

## Direct render review

Ran `./script/render_widget_previews.sh` and directly inspected:

- `docs/qa/widget-small.png` — material card, blue/purple paired rings, and unclipped compact reset footer match the reference hierarchy.
- `docs/qa/widget-medium.png` — divider plus three rows fit within the material card with clear edge spacing.
- `docs/qa/widget-large.png` — six ledger rows fit with fixed columns and the requested preview summary.

## Verification

- `xcodebuild test -project CodexAuthBar.xcodeproj -scheme CodexAuthWidget -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` — passed, 12 tests.
- `./script/render_widget_previews.sh` — passed, all three production-view PNG exports generated.

The only observed environment warning was the existing out-of-date CoreSimulator framework notice; it did not prevent the macOS widget suite or render export from passing.
