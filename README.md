# Codex Auth Bar

A native macOS menu-bar app for managing and switching Codex accounts and
launching Codex CLI configuration profiles.

Codex Auth Bar is inspired by and behavior-compatible with
[Loongphy/codex-auth](https://github.com/Loongphy/codex-auth). It is an
independent Swift implementation and is not affiliated with OpenAI or Loongphy.

## Features

- Switch accounts from a compact menu-bar popover.
- Safe **Switch & Restart** flow for the Codex desktop app.
- Browser and device-code login in an isolated temporary `CODEX_HOME`.
- Import/export standard Codex auth files and CLIProxyAPI JSON.
- Account aliases, previous-account switching, removal, backups, and recovery.
- 5-hour/weekly usage display with remote or local-only refresh.
- Independent discovery and launch of `<name>.config.toml` profiles.
- Opt-in automatic switching policy.
- Experimental, checksum-verified codext integration.

## Requirements

- macOS 14 or newer.
- Apple Silicon or Intel Mac.
- Codex CLI for login and profile-launch features.

## Build

```bash
swift test --package-path src/Packages/CodexAuthCore
xcodebuild test -project CodexAuthBar.xcodeproj -scheme CodexAuthBar \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
xcodebuild analyze -project CodexAuthBar.xcodeproj -scheme CodexAuthBar \
  CODE_SIGNING_ALLOWED=NO
./script/build_and_run.sh --verify
```

All Swift application, package, and test source is stored under `src/`.

The app intentionally runs without App Sandbox because it manages
`~/.codex/auth.json`, starts the Codex CLI, and restarts the Codex desktop app.
It does not request Full Disk Access, Accessibility, or screen recording.

## Security and privacy

Codex itself stores credentials in `auth.json`; managed snapshots therefore
also contain plaintext credentials. Codex Auth Bar creates its managed
directory with mode `0700` and sensitive files with mode `0600`.

Remote refresh is enabled by default and sends the active access token only to:

- `https://chatgpt.com/backend-api/wham/usage`
- `https://chatgpt.com/backend-api/accounts`
- `https://api.openai.com/v1/me` for API-key identity

These ChatGPT backend endpoints are unofficial and may change. Remote refresh
can be disabled in Settings. The app has no analytics, telemetry service, or
external backend.

See [docs/security.md](docs/security.md) for recovery, custom `CODEX_HOME`,
remote API, plaintext credential, and experimental codext trust boundaries.

## Distribution

Unsigned CI builds are for testing only. A public release must be signed with a
Developer ID certificate, notarized, and stapled. The repository intentionally
does not publish unsigned GitHub Releases.

Mac App Store distribution and App Sandbox are not supported in v1.

## License

MIT. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for upstream notices.
