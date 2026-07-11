# Architecture

Implementation-to-plan traceability is maintained in
[`implementation-status.md`](implementation-status.md).

`CodexAuthCore` owns auth parsing, registry compatibility, secure persistence,
account workflows, usage parsing, profiles, auto-switch policy, and codext
verification. It depends only on Apple system frameworks.

The app target owns SwiftUI scenes, AppKit process integration, Terminal launch,
login orchestration, notifications, launch-at-login, and user preferences.
Preferences are not written into upstream `registry.json`.

All Swift targets are rooted under `src/`: the app in `src/CodexAuthBar`, the
local package in `src/Packages/CodexAuthCore`, and Xcode test targets in
`src/CodexAuthBarTests` and `src/CodexAuthBarUITests`.

App Sandbox is intentionally disabled. The release build uses Hardened Runtime
without Full Disk Access, Accessibility, or runtime-code-loading exceptions.
See [ADR 0001](adr/0001-disable-app-sandbox.md) for the accepted decision and
consequences.
