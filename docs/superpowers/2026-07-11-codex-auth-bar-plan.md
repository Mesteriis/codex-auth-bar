# Codex Auth Bar implementation plan

Status: approved implementation baseline.

The complete requirement-by-requirement baseline is recorded in
[`plans/2026-07-11-codex-auth-bar-implementation.md`](plans/2026-07-11-codex-auth-bar-implementation.md),
with the product and trust-boundary design in
[`specs/2026-07-11-codex-auth-bar-design.md`](specs/2026-07-11-codex-auth-bar-design.md).

The project is a native Swift 6 / SwiftUI menu-bar app for macOS 14+, built as
a universal `arm64 + x86_64` binary. Compatibility is pinned to
`Loongphy/codex-auth` commit
`22d87d1531420102fa2f3d51d134f29344dda27c`, with opt-in auto-switch behavior
from the v0.2 line.

The implementation scope includes:

1. Registry schema v4 plus v2/v3 migration, byte-identical auth snapshots,
   API-key identity, transactional switching, backups, recovery, and
   concurrency detection.
2. Import, export, CPA conversion, purge, removal, aliases, cleanup, remote
   usage, workspace names, and local rollout fallback.
3. Isolated browser/device/API-key login, credential-store detection, safe
   `Switch & Restart`, and independent Codex CLI config profiles.
4. Menu-bar popover, management/settings/diagnostics windows, English and
   Russian localization, keyboard and VoiceOver semantics, and Launch at Login.
5. Opt-in auto-switch with candidate refresh bounds and actionable
   notifications, plus experimental checksum-pinned codext installation and
   managed-process tracking.
6. MIT OSS documentation, CI tests/analyze/universal unsigned artifacts, and a
   protected Developer ID signing/notarization DMG workflow. No public release
   is created until Apple credentials are available.

All Swift source and test code lives under `src/`. App-specific preferences
stay outside upstream `registry.json`. App Sandbox is disabled because the app
must manage `CODEX_HOME` and launch/restart Codex; Hardened Runtime remains
enabled. Telemetry and an external backend are out of scope.
