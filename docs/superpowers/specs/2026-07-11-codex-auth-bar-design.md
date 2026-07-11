# Codex Auth Bar — approved design

## Experience

Codex Auth Bar is a native accessory application: its persistent entry point is
the macOS menu bar, not the Dock. The compact popover optimizes the frequent
path—inspect limits, select an account, switch/restart, refresh, or launch a CLI
profile. A separate management window holds identity details, import/export,
profile editing, recovery, destructive maintenance, and experimental codext.

Account selection and config-profile selection are deliberately independent.
Profiles affect only CLI processes launched from the bar. The Desktop app uses
the base Codex config.

## Domain boundaries

`CodexAuthCore` owns models, auth parsing, upstream registry compatibility,
secure persistence, account workflows, usage parsing/fetching, local rollout
fallback, profile storage, auto-switch policy, secret redaction, and codext
verification. It depends only on Apple system frameworks.

The app target owns SwiftUI/AppKit scenes, user interaction, Codex process
orchestration, login presentation, notifications, Launch at Login, diagnostics,
and preferences. Filesystem and network work remain outside the main actor.

## Trust and data model

Codex credentials remain plaintext because that is the Codex `auth.json`
contract. Managed snapshots and backups therefore receive private permissions,
no-follow reads, atomic writes, and bounded retention. Registry mutation is
optimistically fingerprinted and locked. A secret-free transaction journal
allows deterministic recovery without copying credentials into app state.

JWT payloads are decoded only to derive local metadata; they are not treated as
signature-verified identity assertions. Remote usage calls are explicitly
disclosed, use ephemeral sessions, and are optional. Logs and diagnostics use a
shared conservative redactor.

## Lifecycle

Opening a management or settings window activates the accessory app while
preserving its no-Dock policy. Switch & Restart first asks Codex Desktop to
terminate normally. Only after termination does the transactional auth switch
start. Any interrupted transaction is recovered before Desktop is reopened.
The application never uses `killall` and never silently mutates auth beneath a
standard running Desktop instance during auto-switch.

## Distribution

App Sandbox is intentionally disabled because the product must manage arbitrary
user-selected `CODEX_HOME` paths and launch/restart Codex. Hardened Runtime stays
enabled. CI produces unsigned test artifacts only; public DMGs require Developer
ID signing, notarization, stapling, Gatekeeper assessment, and both architectures.
