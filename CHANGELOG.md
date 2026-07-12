# Changelog

## Unreleased

- No unreleased changes.

## 0.1.0-alpha.1 — 2026-07-12

- Published the first explicitly unsigned, ad-hoc signed developer preview for
  installation testing on macOS 14+.
- The preview is universal (`arm64 + x86_64`) and includes the WidgetKit
  extension, but is not Developer ID signed or notarized.

## 0.1.0-rc.1 — pending Developer ID signing

- Initial native Swift implementation of Codex Auth Bar.
- Upstream-compatible schema v4 account storage and auth switching.
- Menu-bar popover, management window, usage, profiles, auto-switch policy, and
  checksum-verified codext integration.
- API-key login/import, workspace names, local rollout fallback, actionable
  auto-switch notifications, recovery/maintenance UI, and redacted diagnostics.
- English/Russian localization and all Swift sources organized under `src/`.
- Native small, medium, and large WidgetKit views for multi-account usage limits.
- Public OSS documentation, GitHub Pages site, contribution templates, CI, and
  a protected signed/notarized release workflow.
