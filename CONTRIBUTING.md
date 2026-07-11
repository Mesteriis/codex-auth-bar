# Contributing

1. Use macOS 14+ and Xcode 26 or newer.
2. Add a failing regression test before changing behavior.
3. Run `swift test --package-path src/Packages/CodexAuthCore`.
4. Run the Xcode test command from the README or `./script/build_and_run.sh --verify`.
5. Never commit real credentials, auth files, DerivedData, or signed artifacts.

Compatibility changes must name the upstream `codex-auth` commit they target
and update `docs/compatibility.md`.
