# Architecture

`CodexAuthCore` owns auth parsing, registry compatibility, secure persistence,
account workflows, usage parsing, profiles, auto-switch policy, and codext
verification. It depends only on Apple system frameworks.

The app target owns SwiftUI scenes, AppKit process integration, Terminal launch,
login orchestration, notifications, launch-at-login, and user preferences.
Preferences are not written into upstream `registry.json`.

App Sandbox is intentionally disabled. The release build uses Hardened Runtime
without Full Disk Access, Accessibility, or runtime-code-loading exceptions.
