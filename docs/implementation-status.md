# Implementation status

This document maps the approved implementation plan to the repository. The
behavioral compatibility baseline is
[`Loongphy/codex-auth@22d87d1`](https://github.com/Loongphy/codex-auth/tree/22d87d1531420102fa2f3d51d134f29344dda27c).

All application, core, and test source code is under `src/`. Xcode project
metadata, scripts, documentation, and CI configuration remain at repository
root because they are build and repository infrastructure rather than source.

## Requirement traceability

| Plan area | Implementation evidence | Regression evidence |
| --- | --- | --- |
| OSS scaffold and build loop | `CodexAuthBar.xcodeproj`, `src/CodexAuthBar`, `src/Packages/CodexAuthCore`, `script/build_and_run.sh` | CI build-contract checks and `--verify` smoke run |
| Auth models and parsing | `Models.swift`, `AuthParser.swift`, `RegistryCodec.swift`, `CPAConverter.swift` | v2/v3 migrations, future-schema rejection, JWT identity precedence, mismatched IDs, API-key and CPA tests |
| Secure storage and recovery | `SecureFiles.swift`, `RegistryStore.swift` | private modes, no-follow access, fingerprints, atomic backup/switch, collision, retention, journal-stage and unknown-auth recovery tests |
| Account workflows | `AccountRepository.swift`, `AccountImportExport.swift` | switch/previous, reimport, file/folder/array/CPA import, purge, export, remove and clean tests |
| Usage and local fallback | `ChatGPTUsageService.swift`, `LocalUsageScanner.swift`, `Usage.swift` | URLProtocol-only API tests, redirect/status parsing, five-request concurrency bound and activation-time local fallback tests |
| Login and Codex control | `CodexProcessController.swift`, `ProcessContracts.swift` | failed/cancelled login byte identity, scratch cleanup, API-key stdin and credential-store tests |
| Menu bar and management UI | `CodexAuthBarApp.swift`, `MenuBarPopover.swift`, `ManagementView.swift`, `SettingsView.swift`, `Localizable.xcstrings` | app tests plus menu-bar launch, keyboard search and VoiceOver-labelled action UI tests |
| Widget extension/process boundary | `WidgetSnapshot.swift`, `WidgetSnapshotStore.swift`, `WidgetSnapshotPublisher.swift`, `src/CodexAuthWidget`, App Group entitlements and a credential-free local unsigned fallback | core/app/widget tests; fixture scan rejects credential and identity coding keys; CI checks extension sandbox, App Group, API-only settings, and universal nested binary |
| Config profiles | `ProfileName.swift`, `ProfileStore.swift`, profile UI and process controller | traversal rejection, CRUD and shell-quoting/self-delete command tests |
| Opt-in auto-switch | `AutoSwitchPolicy.swift`, `AppModel.swift` | Free-plan guard, threshold, scoring and candidate-selection tests |
| Experimental codext | `Codext.swift`, `CodextManager.swift` | pinned hashes, size/origin checks, bad hash and archive-traversal rejection tests |
| OSS, CI and release | `LICENSE`, `THIRD_PARTY_NOTICES.md`, public docs, `.github/workflows`, `script/package_release.sh` | unit/app/widget/UI/analyze/universal/fixture scan CI jobs, widget preview QA artifacts, and signed nested-extension verification commands |

## Release boundary

Unsigned PR artifacts are named `CodexAuthBar-unsigned` and are never published
as a GitHub Release. The protected GitHub `release` environment exists and the
release workflow requires Apple signing/notarization secrets. No public release
is created until those credentials are supplied; the first accepted public tag
is `v0.1.0-rc.1`. This is the intended completion state before enrollment in the
Apple Developer Program, not a bypass of the release gate.

## Validation commands

The authoritative gates are:

```bash
swift test --package-path src/Packages/CodexAuthCore
xcodebuild test -project CodexAuthBar.xcodeproj -scheme CodexAuthBar \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
xcodebuild test -project CodexAuthBar.xcodeproj -scheme CodexAuthBarUITests \
  -destination 'platform=macOS' CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- \
  DEVELOPMENT_TEAM=
xcodebuild test -project CodexAuthBar.xcodeproj -scheme CodexAuthWidget \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
xcodebuild analyze -project CodexAuthBar.xcodeproj -scheme CodexAuthBar \
  CODE_SIGNING_ALLOWED=NO
./script/build_and_run.sh --verify
```

CI additionally checks host and widget build-setting contracts, both entitlement
files, a two-architecture unsigned Release app plus nested widget extension,
secret-safe fixtures, snapshot coding keys, and packaging. A signed release
additionally verifies the nested extension signature and its signed App Group /
sandbox entitlements before running `codesign --verify --deep --strict`,
`spctl --assess`, notarization, stapling validation, and publishing a SHA-256
checksum. The visual reference and rendered widget QA artifacts are recorded in
[`qa/widget-design-qa.md`](qa/widget-design-qa.md).
