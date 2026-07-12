# Codex Auth Bar

<p align="center">
  <strong>Switch Codex accounts from the macOS menu bar and keep usage limits visible on your desktop.</strong>
</p>

<p align="center">
  <a href="https://github.com/Mesteriis/codex-auth-bar/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/Mesteriis/codex-auth-bar/actions/workflows/ci.yml/badge.svg"></a>
  <a href="https://github.com/Mesteriis/codex-auth-bar/blob/main/LICENSE"><img alt="MIT License" src="https://img.shields.io/badge/license-MIT-blue.svg"></a>
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-black?logo=apple">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white">
</p>

<p align="center">
  <a href="README.ru.md">Русский</a> ·
  <a href="https://mesteriis.github.io/codex-auth-bar/">Website</a> ·
  <a href="https://github.com/Mesteriis/codex-auth-bar/releases">Releases</a> ·
  <a href="SECURITY.md">Security</a>
</p>

![Codex Auth Bar widgets](docs/qa/widget-large.png)

Codex Auth Bar is an open-source native SwiftUI app for macOS. It keeps Codex
account switching, usage limits, configuration profiles, recovery tools, and
desktop widgets in one menu-bar utility—without analytics or a separate
backend.

Inspired by and behavior-compatible with
[Loongphy/codex-auth](https://github.com/Loongphy/codex-auth/tree/22d87d1531420102fa2f3d51d134f29344dda27c).
This is an independent implementation and is not affiliated with OpenAI or
Loongphy.

## Highlights

- Switch between managed Codex accounts directly from the menu bar.
- Use **Switch & Restart** to close Codex cleanly, change auth, and reopen it.
- See 5-hour and weekly limits for every account in small, medium, and large
  WidgetKit widgets.
- Add accounts through browser login, device code, API key, file, folder, JSON
  array, or CLIProxyAPI import.
- Preserve byte-for-byte auth snapshots with atomic writes, backups, a
  transaction journal, and crash recovery.
- Discover and launch independent `<name>.config.toml` Codex CLI profiles.
- Opt into automatic switching and the checksum-pinned experimental codext
  integration.
- Use the complete English or Russian interface on Apple Silicon and Intel.

## Widgets

| Small | Medium |
|:---:|:---:|
| ![Small Codex Auth Bar widget](docs/qa/widget-small.png) | ![Medium Codex Auth Bar widget](docs/qa/widget-medium.png) |

The active account appears first; additional accounts follow in the medium and
large layouts. Values are drawn inside the rings without duplicate percent
symbols. Widget snapshots contain display names, plans, derived usage values,
and reset times only—never tokens, API keys, email addresses, or Codex account
identifiers.

Launch Codex Auth Bar once before adding a widget from the macOS widget gallery.
The widget is read-only: selecting it opens account management in the app. It
does not switch accounts or make network requests by itself.

Widget reload requests are coalesced to at most once every 15 minutes, and the
normal timeline refresh interval is 30 minutes. This respects WidgetKit's own
scheduling budget, so macOS can defer an update.

## Install

The current [`v0.1.0-alpha.1`](https://github.com/Mesteriis/codex-auth-bar/releases/tag/v0.1.0-alpha.1)
developer preview is available from GitHub Releases as a universal ad-hoc
signed build. It is **not Developer ID signed or notarized**. macOS can require
using **Open Anyway** in System Settings → Privacy & Security after the first
launch attempt. Install it only if you accept this preview limitation.

The first normal public binary will be `v0.1.0-rc.1`: a universal Developer ID
signed, notarized, and stapled DMG. Regular unsigned CI artifacts remain for
development testing only.

### Build from source

Requirements: macOS 14+, Xcode 16+, and the Xcode command-line tools.

```bash
git clone https://github.com/Mesteriis/codex-auth-bar.git
cd codex-auth-bar
swift test --package-path src/Packages/CodexAuthCore
xcodebuild build \
  -project CodexAuthBar.xcodeproj \
  -scheme CodexAuthBar \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
./script/build_and_run.sh
```

All Swift application, package, extension, and test source lives under `src/`.

## Usage

1. Start Codex Auth Bar and select its icon in the menu bar.
2. Select **Add** to import an existing auth file or run an isolated Codex login.
3. Select another account and use **Switch & Restart** when Codex Desktop is
   running.
4. Open **Manage…** for aliases, import/export, profiles, recovery, and
   experimental settings.
5. Add a Codex Auth Bar widget from the macOS widget gallery.

Account records are stored in the upstream-compatible registry at
`$CODEX_HOME/accounts/registry.json`; the active Codex authorization remains at
`$CODEX_HOME/auth.json`. The default `CODEX_HOME` is `~/.codex`.

## Security and privacy

Codex credentials are plaintext in `auth.json`, just as they are for Codex CLI.
Managed snapshots and backups therefore also contain credentials. Codex Auth
Bar creates the managed directory with mode `0700` and sensitive files with
mode `0600`, rejects symlinked managed files, and uses atomic replacement.

Remote usage refresh is enabled by default and sends the selected managed
account's credential only to these endpoints:

- `https://chatgpt.com/backend-api/wham/usage`
- `https://chatgpt.com/backend-api/accounts`
- `https://api.openai.com/v1/me` for API-key identity

The ChatGPT endpoints are unofficial and may change. Remote refresh can be
disabled in Settings. The app has no analytics, telemetry service, advertising,
or external backend. See [docs/security.md](docs/security.md) for the complete
trust model and [SECURITY.md](SECURITY.md) for vulnerability reporting.

## Compatibility and architecture

- Swift 6, SwiftUI, WidgetKit, macOS 14+
- Universal `arm64 + x86_64`
- Registry schema v4 with v2/v3 migration
- Native `MenuBarExtra`, management window, Settings, and WidgetKit extension
- No App Sandbox for the host app because it must manage Codex files and
  processes; the widget extension remains sandboxed and network-free

Technical details are in [docs/architecture.md](docs/architecture.md),
[docs/compatibility.md](docs/compatibility.md), and
[docs/implementation-status.md](docs/implementation-status.md).

## Contributing

Bug reports and focused pull requests are welcome. Read
[CONTRIBUTING.md](CONTRIBUTING.md), use the issue templates, and run the local
verification commands before opening a PR.

```bash
swift test --package-path src/Packages/CodexAuthCore
xcodebuild test -project CodexAuthBar.xcodeproj -scheme CodexAuthBar \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
xcodebuild test -project CodexAuthBar.xcodeproj -scheme CodexAuthWidget \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
xcodebuild analyze -project CodexAuthBar.xcodeproj -scheme CodexAuthBar \
  CODE_SIGNING_ALLOWED=NO
./script/build_and_run.sh --verify
```

## License

MIT. See [LICENSE](LICENSE) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)
for the pinned upstream attribution and third-party notices.
