# Codex Auth Bar design

Native SwiftUI menu-bar application for full GUI management of Codex accounts,
compatible with the upstream registry and auth snapshot model. Complex account
management lives in a dedicated window; quick switching, usage, and profile
launch live in the popover. All writes are serialized, private, atomic, backed
up, and recoverable. Config profiles remain independent from auth accounts.
