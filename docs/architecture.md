# Architecture

Implementation-to-plan traceability is maintained in
[`implementation-status.md`](implementation-status.md).

`CodexAuthCore` owns auth parsing, registry compatibility, secure persistence,
account workflows, usage parsing, profiles, auto-switch policy, and codext
verification. It depends only on Apple system frameworks.

The app target owns SwiftUI scenes, AppKit process integration, Terminal launch,
login orchestration, notifications, launch-at-login, user preferences, and the
sanitized widget-snapshot publisher. Preferences are not written into upstream
`registry.json`.

`CodexAuthWidget` is a separate sandboxed WidgetKit extension. The containing
app and extension share only `group.com.mesteriis.CodexAuthBar`: the app writes
an atomic, credential-free derived snapshot and the extension reads it to build
30-minute timelines. Automatic WidgetKit reload requests are coalesced to 15
minutes. The extension has no network client entitlement, does not own an
account-switch path, and opens the containing app's account view only through
`codexauthbar://accounts`. Missing, stale, or offline snapshots render as state
rather than triggering remote Usage API calls.

All Swift targets are rooted under `src/`: the app in `src/CodexAuthBar`, the
widget extension in `src/CodexAuthWidget`, the local package in
`src/Packages/CodexAuthCore`, and Xcode test targets in `src/CodexAuthBarTests`,
`src/CodexAuthBarUITests`, and `src/CodexAuthWidgetTests`.

App Sandbox is intentionally disabled. The release build uses Hardened Runtime
without Full Disk Access, Accessibility, or runtime-code-loading exceptions.
See [ADR 0001](adr/0001-disable-app-sandbox.md) for the accepted decision and
consequences.

The App Group is therefore a signing prerequisite for contributors building the
integrated app and widget with a real signature. Unsigned local/CI tests inject
container URLs and do not claim to verify production provisioning.
