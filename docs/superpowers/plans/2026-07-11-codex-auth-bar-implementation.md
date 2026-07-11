# Codex Auth Bar — approved implementation plan

This document is the complete implementation baseline accepted on 2026-07-11.
Compatibility is pinned to `Loongphy/codex-auth` commit
`22d87d1531420102fa2f3d51d134f29344dda27c`. Upstream changes require a
separate compatibility review.

## Product decisions

- Native Swift 6 and SwiftUI application for macOS 14+.
- Universal `arm64 + x86_64` output.
- `MenuBarExtra(.window)` for quick actions, a management `Window`, and
  `Settings`; `LSUIElement=YES` and no Dock icon.
- Accounts and Codex CLI config profiles are independent selections.
- The primary action while Codex Desktop is running is **Switch & Restart**.
- Remote usage is enabled by default and disclosed in the UI; auto-switch and
  Launch at Login are disabled by default.
- Experimental codext is opt-in and a managed download is accepted only after
  pinned size, origin, archive, and SHA-256 verification.
- Distribution uses a Developer ID signed, notarized, stapled DMG. App Sandbox
  and Mac App Store distribution are unsupported. No public release is created
  before Apple signing credentials exist; CI artifacts are explicitly unsigned.
- There is no telemetry, analytics, external backend, or update framework in v1.
- All Swift application, package, and test source is stored below `src/`.

## Repository layout

```text
CodexAuthBar.xcodeproj
src/CodexAuthBar/                 # SwiftUI app, scenes, coordinators, resources
src/Packages/CodexAuthCore/       # Foundation/POSIX core and unit tests
src/CodexAuthBarTests/
src/CodexAuthBarUITests/
script/                           # build, package, and release tooling
docs/                             # architecture, security, compatibility, plans
```

## Core contracts

The core exposes actors for registry and account operations, `UsageFetching`
for remote/local usage integration, and `CodexProcessControlling` for Codex CLI
and Desktop orchestration. Public workflow models are `Codable`, `Sendable`,
and use stable snake-case keys. Registry v4, account records, auth metadata,
rate-limit snapshots, import/export/removal reports, switch receipts,
fingerprints, and recovery results are part of this contract.

## Disk contract

| Purpose | Path |
| --- | --- |
| Active authorization | `$CODEX_HOME/auth.json` |
| Compatible registry | `$CODEX_HOME/accounts/registry.json` |
| Account snapshots | `$CODEX_HOME/accounts/<key>.auth.json` |
| Rotation backups | `$CODEX_HOME/accounts/*.bak.<timestamp>[.N]` |
| Default exports | `$CODEX_HOME/accounts/backup/` |
| Application settings | `~/Library/Application Support/CodexAuthBar/` |
| Verified codext | `~/Library/Application Support/CodexAuthBar/codext/<version>/` |

Application-only preferences never enter `registry.json`, because upstream
tools may rewrite and discard unknown registry fields. `CODEX_HOME` resolution
order is app preference, then a non-empty existing directory from the process
environment, then `~/.codex`.

## 1. OSS scaffold and build loop

- Use bundle id `com.mesteriis.CodexAuthBar`, macOS 14, strict concurrency, and
  Swift 6.
- Provide app, local package, app test, and UI test targets.
- Provide `script/build_and_run.sh` with run, debug, logs, telemetry, and verify
  modes plus `.codex/environments/environment.toml`.
- Keep the accepted design and plan in `docs/superpowers/`.
- A smoke launch must prove that the menu-bar process starts and exits cleanly
  without terminating a separately running normal instance.

## 2. Compatible auth models and parsing

- Implement schema v4 and migrations from v2/v3; reject schemas newer than 4
  without writing.
- Preserve upstream time units and plan/auth-mode values.
- Decode local ChatGPT JWT metadata without signature verification. Identity
  precedence is `tokens.account_id`, JWT account id, then default/first
  organization.
- Reject mismatched account ids, missing user ids, malformed auth, and files
  over 10 MiB.
- Support API-key identity `apikey::<me.id>::<sha256(key)>` and CPA conversion.
- Copy standard auth snapshots byte-for-byte so unknown JSON fields survive.

## 3. Secure storage and recovery

- Enforce `0700` on managed directories and `0600` on registry, snapshots,
  backups, lock, and journal files.
- Use `openat`/`O_NOFOLLOW`, same-directory temporary files, `fsync`, atomic
  rename, and directory `fsync`. Preserve the mode of an existing live
  `auth.json`; create a new one as `0600`.
- Back up only when bytes differ, retain the latest five strictly recognized
  managed backups, and support collision suffixes.
- Serialize in-process work with actors and cross-process commits with an
  advisory lock.
- Compare inode, size, mtime, and SHA-256 fingerprints before commit. Reload and
  retry foreground mutations at most three times after concurrent changes.
- Switch through a token-free journal: sync, validate, backup, replace auth,
  update registry, remove journal.
- At startup reconcile old or target hashes. Never overwrite an unknown
  externally modified live auth file.

## 4. Account workflows

- Synchronize externally changed live auth before foreground operations.
- Support switch, previous switch, unique aliases, and search over alias,
  email, account name, and account key.
- Import a standard/CPA file, a JSON array, or direct JSON files from a folder;
  report each batch failure separately.
- Purge/rebuild from snapshots and backups, selecting the newest valid candidate
  per account key.
- Re-import updates auth and identity metadata while preserving alias, creation,
  and usage timestamps.
- Export standard or CPA; skip API-key records in CPA output.
- Removing the active account promotes the candidate with the highest minimum
  available limit. Malformed or externally unsynchronized live auth remains
  untouched. Removing the last managed account must not destroy unknown auth.
- Clean only recognized stale snapshots and managed backups and always preserve
  `accounts/backup/`.
- Remove `com.loongphy.codex-auth.auto` only through a separately confirmed
  maintenance action.

## 5. Usage, workspace names, and local fallback

- Use ephemeral sessions without cookies/cache and at most five concurrent
  requests.
- Support `GET https://chatgpt.com/backend-api/wham/usage`,
  `GET https://chatgpt.com/backend-api/accounts`, and
  `GET https://api.openai.com/v1/me`.
- Follow redirects only between explicitly expected HTTPS hosts. Never log
  authorization headers, access tokens, JWTs, refresh tokens, or API keys.
- Map 5-hour and weekly windows, reset time, credits/reset credits, plan, and
  status outcomes including 401, 403, timeout, and missing auth.
- Local-only refresh reads the latest usable `event_msg/token_count/rate_limits`
  event from the newest rollout and applies it only to the active account after
  its activation timestamp.
- Expose refresh all, active, and local-only actions. API refresh-all is the
  default; the unofficial endpoint disclosure and disable switch remain visible.

## 6. Login and Codex Desktop control

- Resolve the CLI in this order: explicit preference, Codex.app resource,
  `~/.local/bin`, Homebrew/npm candidates, inherited `PATH`.
- Detect `--profile`, `doctor`, and version capabilities. Use
  `codex doctor --json` when available and fall back to the explicit top-level
  config value when doctor cannot report credential storage.
- Block file switching for Keyring, Auto, Ephemeral, or unknown storage and
  instruct the user to set `cli_auth_credentials_store = "file"`; never edit
  the setting automatically.
- Run browser, device-code, and API-key login in a private scratch
  `CODEX_HOME`, passing `-c cli_auth_credentials_store=file`. Send API keys only
  through stdin, never argv or environment.
- Cancellation/failure removes scratch state and leaves live auth byte-identical.
- Switch & Restart gracefully terminates bundle `com.openai.codex`, switches,
  and reopens it. The timeout is ten seconds and `killall` is forbidden.
- If Codex does not terminate, do not modify auth and offer Switch only. If a
  transaction is interrupted after termination, run recovery before reopening.

## 7. Menu bar and management UI

- Popover: active identity, 5h/weekly progress and reset time, searchable
  accounts, previous, refresh, independent profile picker, add, manage,
  settings, and quit.
- Truncate visible identity names to 30 characters and show full identity in
  management details.
- Management tabs: Accounts, Import/Export, Profiles, Recovery/Maintenance,
  Experimental. Destructive actions require confirmation and produce reports.
- Use system materials, semantic colors, Light/Dark mode, `@MainActor
  @Observable AppModel`, keyboard navigation, VoiceOver labels, and English and
  Russian localization.
- Implement Launch at Login through `SMAppService.mainApp`, default off.

## 8. Codex config profiles

- Discover only `$CODEX_HOME/<name>.config.toml` where name matches
  `[A-Za-z0-9_-]+`.
- Create an empty profile; rename, delete, reveal, and open it; persist an
  independent selection. Never modify or generate base `config.toml`.
- Launch CLI with a private one-shot `.command` that safely quotes executable
  and profile, deletes itself, then executes `codex --profile <name>`.
- Provide Copy command. Disable launch when `--profile` is unsupported and
  explain the required Codex update.
- Codex Desktop continues using base config because app launch has no profile.

## 9. Opt-in automatic switching

- Store settings outside the registry: disabled by default, 5h threshold 10%,
  weekly threshold 5%, refresh interval 60 seconds.
- Trigger only when remaining is strictly below either threshold. Effective
  Free-plan 5h threshold is at least 35%.
- Candidate score is the minimum known 5h/weekly remaining value; an expired
  reset or no usable usage after refresh scores 100%. Break ties by newer
  `last_usage_at`, then newer `created_at`; require a strictly better candidate.
- Refresh the active account at most once per minute, at most one stale candidate
  per cycle, and at most the best three immediately before switching.
- Managed codext switches at its safe request boundary. Standard running Codex
  receives an actionable Switch & Restart notification instead of a silent
  auth mutation.
- If Desktop is not running, switch immediately and notify the user that
  existing CLI/VS Code sessions need restart.

## 10. Experimental codext

- Support a user-trusted custom executable and a managed pinned download.
- Pin `codext-v0.144.1-a8c9398`:
  - arm64 SHA-256 `bd6e06cc9093994af1f3c59943a2423199d998b0c304c6836022a22ce860df82`;
  - x64 SHA-256 `f57b2050e2e5ce89367c2bc9bfbcb04062979014e722f27fe746424fd975e8ea`.
- Verify expected HTTPS origin/final hosts, exact size, SHA-256, traversal,
  regular archive entries, and exactly `codext` plus `codex-code-mode-host`.
- Never install an unreviewed dynamic latest; manifest changes require a review
  PR.
- Launch Codex with `CODEX_HOME` and `CODEX_CLI_PATH`, gracefully terminating an
  existing instance first. Track only the PID launched in the current bar
  process; after restart treat an existing Codex as standard.
- Provide `--std`-equivalent diagnostics with bounded, redacted stdout/stderr.

## 11. OSS, CI, and release

- MIT license plus `THIRD_PARTY_NOTICES.md` containing the full Loongphy MIT
  notice and pinned commit. README wording must state that the project is
  inspired by and behavior-compatible with Loongphy/codex-auth. Provide a
  Russian README.
- Document plaintext auth storage, remote API disclosure, recovery, custom
  `CODEX_HOME`, codext risks, build/contribution flow, security reporting, and
  the no-sandbox architecture decision.
- PR CI runs core tests, app tests, UI tests, analyze, universal unsigned build,
  artifact architecture verification, and a synthetic-fixture secret scan.
- Name unsigned artifacts `CodexAuthBar-unsigned-*` and never publish them as a
  GitHub Release.
- Release uses a protected `release` environment and required Apple secrets,
  archives both architectures with Hardened Runtime, signs app and DMG,
  notarizes, staples, validates with `codesign`, `spctl`, and `stapler`, and
  publishes SHA-256.
- The first public candidate is `v0.1.0-rc.1` after Developer ID credentials,
  followed by `v0.1.0`. Sparkle is out of scope.

## Required verification

```bash
swift test --package-path src/Packages/CodexAuthCore
xcodebuild test -project CodexAuthBar.xcodeproj -scheme CodexAuthBar \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
xcodebuild analyze -project CodexAuthBar.xcodeproj -scheme CodexAuthBar \
  CODE_SIGNING_ALLOWED=NO
./script/build_and_run.sh --verify
```

Critical coverage includes migration and future-schema fail-closed behavior;
byte-identical failed login/import; switch permissions/backups/previous keys;
recovery at every transaction boundary; concurrent registry mutation; all
import/export forms; safe active/final/external removal; backup-directory
preservation; secret-free logs/journals/UI/test output; stubbed network tests;
profile traversal and shell quoting; codext checksum/traversal rejection;
menu-bar accessory behavior and accessibility; and signed-release validation
once credentials become available.
