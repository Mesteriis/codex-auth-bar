# ADR 0001: Disable App Sandbox

- Status: Accepted
- Date: 2026-07-11

## Context

Codex Auth Bar must read and atomically replace Codex authorization files in
the default or a user-selected `CODEX_HOME`, discover profile files, execute the
installed Codex CLI, and gracefully terminate/relaunch Codex Desktop. These are
core product operations rather than optional document-picker interactions.

## Decision

The macOS app is distributed outside the Mac App Store with App Sandbox
disabled. Release builds retain Hardened Runtime and Developer ID signing,
notarization, stapling, and Gatekeeper validation. The app does not request Full
Disk Access, Accessibility, screen recording, JIT, unsigned executable memory,
or library-validation exceptions.

## Consequences

- Mac App Store distribution is unsupported.
- Filesystem code must enforce its own no-follow, permissions, atomicity,
  locking, backup, and recovery boundaries.
- Custom `CODEX_HOME` and executable paths remain explicit user trust choices.
- CI verifies `ENABLE_APP_SANDBOX=NO` and `ENABLE_HARDENED_RUNTIME=YES` through
  project/build contracts; the signed release also verifies the runtime flag.
